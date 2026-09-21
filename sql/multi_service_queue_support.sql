-- ============================================================
-- MULTI-SERVICE QUEUE SUPPORT
-- Run after the previous queue/RLS SQL scripts.
-- ============================================================

create table if not exists public.queue_ticket_services (
    id uuid primary key default gen_random_uuid(),
    ticket_id uuid not null references public.queue_tickets(id)
        on delete cascade,
    service_id uuid references public.queue_services(id)
        on delete set null,
    service_name text not null,
    created_at timestamptz not null default now(),
    unique (ticket_id, service_name)
);

create index if not exists idx_queue_ticket_services_ticket_id
on public.queue_ticket_services(ticket_id);

alter table public.queue_ticket_services enable row level security;

drop policy if exists "Authenticated users can read ticket services"
on public.queue_ticket_services;

create policy "Authenticated users can read ticket services"
on public.queue_ticket_services
for select
to authenticated
using (true);

-- Create a multi-service RPC. It inserts one queue ticket and
-- stores every selected service in queue_ticket_services.
create or replace function public.create_queue_ticket_multi(
    p_customer_name text,
    p_service_ids uuid[] default '{}',
    p_service_names text[] default '{}',
    p_customer_phone text default null,
    p_customer_email text default null,
    p_customer_notes text default null,
    p_priority text default 'Regular',
    p_ticket_prefix text default 'A'
)
returns public.queue_tickets
language plpgsql
security definer
set search_path = public
as $$
declare
    v_today date := current_date;
    v_sequence integer;
    v_ticket public.queue_tickets;
    v_service_name text;
    v_index integer;
begin
    if trim(coalesce(p_customer_name, '')) = '' then
        raise exception 'Customer name is required';
    end if;

    if coalesce(array_length(p_service_names, 1), 0) = 0 then
        raise exception 'At least one service is required';
    end if;

    if p_priority not in ('Regular', 'Priority') then
        raise exception 'Invalid priority value';
    end if;

    perform pg_advisory_xact_lock(
        hashtext('members_services_queue_sequence_' || v_today::text)
    );

    select coalesce(max(sequence_number), 0) + 1
    into v_sequence
    from public.queue_tickets
    where queue_date = v_today;

    insert into public.queue_tickets (
        ticket_number,
        queue_date,
        sequence_number,
        ticket_prefix,
        customer_name,
        customer_phone,
        customer_email,
        customer_notes,
        service_id,
        service_name,
        priority
    )
    values (
        p_ticket_prefix || lpad(v_sequence::text, 3, '0'),
        v_today,
        v_sequence,
        p_ticket_prefix,
        trim(p_customer_name),
        p_customer_phone,
        p_customer_email,
        p_customer_notes,
        case
            when coalesce(array_length(p_service_ids, 1), 0) >= 1
            then p_service_ids[1]
            else null
        end,
        array_to_string(p_service_names, ', '),
        p_priority
    )
    returning * into v_ticket;

    for v_index in 1..coalesce(array_length(p_service_names, 1), 0) loop
        v_service_name := trim(p_service_names[v_index]);

        insert into public.queue_ticket_services (
            ticket_id,
            service_id,
            service_name
        )
        values (
            v_ticket.id,
            case
                when coalesce(array_length(p_service_ids, 1), 0) >= v_index
                then p_service_ids[v_index]
                else null
            end,
            v_service_name
        )
        on conflict (ticket_id, service_name) do nothing;
    end loop;

    insert into public.queue_events (
        ticket_id,
        event_type,
        new_status,
        notes
    )
    values (
        v_ticket.id,
        'Created',
        v_ticket.status,
        'Queue ticket created with multiple services'
    );

    return v_ticket;
end;
$$;

revoke all on function public.create_queue_ticket_multi(
    text, uuid[], text[], text, text, text, text, text
) from public;

grant execute on function public.create_queue_ticket_multi(
    text, uuid[], text[], text, text, text, text, text
) to anon, authenticated;
