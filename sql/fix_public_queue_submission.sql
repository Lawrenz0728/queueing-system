-- ============================================================
-- FIX: Public customer queue submission (Supabase)
-- Run this in Supabase SQL Editor.
-- ============================================================

-- 1. Allow visitors to read active service names.
drop policy if exists "Public can read active queue services"
on public.queue_services;

create policy "Public can read active queue services"
on public.queue_services
for select
to anon, authenticated
using (is_active = true);

-- 2. Recreate the ticket function as SECURITY DEFINER.
-- This allows the public customer page to submit a ticket without
-- requiring the customer to log in.
create or replace function public.create_queue_ticket(
    p_customer_name text,
    p_service_id uuid default null,
    p_service_name text default null,
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
begin
    if trim(coalesce(p_customer_name, '')) = '' then
        raise exception 'Customer name is required';
    end if;

    if p_priority not in ('Regular', 'Priority') then
        raise exception 'Invalid priority value';
    end if;

    perform pg_advisory_xact_lock(
        hashtext('1pnx_queue_sequence_' || v_today::text)
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
        p_service_id,
        p_service_name,
        p_priority
    )
    returning * into v_ticket;

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
        'Queue ticket created'
    );

    return v_ticket;
end;
$$;

-- 3. Allow the customer page to call the function.
revoke all on function public.create_queue_ticket(
    text, uuid, text, text, text, text, text, text
) from public;

grant execute on function public.create_queue_ticket(
    text, uuid, text, text, text, text, text, text
) to anon, authenticated;

-- 4. Ensure the function owner can write the internal records.
-- The SECURITY DEFINER function performs these inserts safely
-- without exposing direct table-write access to anonymous visitors.

-- 5. Optional: allow anonymous lookup only if you accept that
-- customer ticket details can be publicly queried.
-- This is intentionally NOT enabled here for privacy.
