-- ============================================================
-- 1PNX Piloting Services Manager
-- Separate Queueing System Tables for Supabase
-- ============================================================
-- This script creates queue-specific tables separately from the
-- existing bookings table.
--
-- Run this script in Supabase SQL Editor.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. Queue services
-- ------------------------------------------------------------
create table if not exists public.queue_services (
    id uuid primary key default gen_random_uuid(),
    service_code text not null unique,
    service_name text not null,
    description text,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

insert into public.queue_services (service_code, service_name, description)
values
    ('SPEED', 'Speed', 'Speed service'),
    ('STEAL', 'Steal', 'Steal service'),
    ('EVENT', 'Event', 'Event service'),
    ('DEAD_SERVER', 'Dead Server', 'Dead server service')
on conflict (service_code) do nothing;

-- ------------------------------------------------------------
-- 2. Counters
-- ------------------------------------------------------------
create table if not exists public.queue_counters (
    id uuid primary key default gen_random_uuid(),
    counter_number integer not null unique,
    counter_name text not null,
    assigned_service_id uuid references public.queue_services(id)
        on delete set null,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3. Queue tickets
-- ------------------------------------------------------------
create table if not exists public.queue_tickets (
    id uuid primary key default gen_random_uuid(),

    -- Public ticket details
    ticket_number text not null unique,
    queue_date date not null default current_date,
    sequence_number integer not null,
    ticket_prefix text not null default 'A',

    -- Customer details
    customer_name text not null,
    customer_phone text,
    customer_email text,
    customer_notes text,

    -- Selected service
    service_id uuid references public.queue_services(id)
        on delete set null,
    service_name text,

    -- Queue status
    status text not null default 'Waiting'
        check (status in (
            'Waiting',
            'Called',
            'Serving',
            'Completed',
            'Skipped',
            'Cancelled'
        )),

    priority text not null default 'Regular'
        check (priority in ('Regular', 'Priority')),

    -- Counter and staff assignment
    counter_id uuid references public.queue_counters(id)
        on delete set null,
    called_by uuid references auth.users(id)
        on delete set null,

    -- QR/passcode access
    qr_token uuid not null default gen_random_uuid() unique,
    passcode_hash text,
    passcode_hint text,

    -- Time tracking
    joined_at timestamptz not null default now(),
    called_at timestamptz,
    serving_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    updated_at timestamptz not null default now(),

    -- Optional link to the existing booking
    booking_id uuid,

    constraint queue_tickets_unique_daily_sequence
        unique (queue_date, sequence_number)
);

-- ------------------------------------------------------------
-- 4. Queue activity/history
-- ------------------------------------------------------------
create table if not exists public.queue_events (
    id uuid primary key default gen_random_uuid(),
    ticket_id uuid not null references public.queue_tickets(id)
        on delete cascade,
    event_type text not null
        check (event_type in (
            'Created',
            'Called',
            'Recalled',
            'Serving',
            'Completed',
            'Skipped',
            'Cancelled',
            'Transferred',
            'PriorityChanged'
        )),
    previous_status text,
    new_status text,
    counter_id uuid references public.queue_counters(id)
        on delete set null,
    performed_by uuid references auth.users(id)
        on delete set null,
    notes text,
    created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 5. Queue settings
-- ------------------------------------------------------------
create table if not exists public.queue_settings (
    id uuid primary key default gen_random_uuid(),
    setting_key text not null unique,
    setting_value text not null,
    description text,
    updated_at timestamptz not null default now()
);

insert into public.queue_settings
    (setting_key, setting_value, description)
values
    ('ticket_prefix', 'A', 'Default ticket prefix'),
    ('daily_reset', 'true', 'Reset sequence number each day'),
    ('display_refresh_seconds', '5', 'TV display refresh interval'),
    ('allow_priority', 'true', 'Allow priority queue tickets')
on conflict (setting_key) do nothing;

-- ------------------------------------------------------------
-- 6. Indexes
-- ------------------------------------------------------------
create index if not exists idx_queue_tickets_queue_date
    on public.queue_tickets (queue_date);

create index if not exists idx_queue_tickets_status
    on public.queue_tickets (status);

create index if not exists idx_queue_tickets_counter_id
    on public.queue_tickets (counter_id);

create index if not exists idx_queue_tickets_joined_at
    on public.queue_tickets (joined_at);

create index if not exists idx_queue_events_ticket_id
    on public.queue_events (ticket_id);

create index if not exists idx_queue_events_created_at
    on public.queue_events (created_at);

-- ------------------------------------------------------------
-- 7. Automatic updated_at trigger
-- ------------------------------------------------------------
create or replace function public.set_queue_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_queue_tickets_updated_at
on public.queue_tickets;

create trigger trg_queue_tickets_updated_at
before update on public.queue_tickets
for each row
execute function public.set_queue_updated_at();

drop trigger if exists trg_queue_settings_updated_at
on public.queue_settings;

create trigger trg_queue_settings_updated_at
before update on public.queue_settings
for each row
execute function public.set_queue_updated_at();

-- ------------------------------------------------------------
-- 8. Row Level Security
-- ------------------------------------------------------------
alter table public.queue_services enable row level security;
alter table public.queue_counters enable row level security;
alter table public.queue_tickets enable row level security;
alter table public.queue_events enable row level security;
alter table public.queue_settings enable row level security;

-- Authenticated users can read queue configuration.
drop policy if exists "Authenticated users can read queue services"
on public.queue_services;

create policy "Authenticated users can read queue services"
on public.queue_services
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read queue counters"
on public.queue_counters;

create policy "Authenticated users can read queue counters"
on public.queue_counters
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read queue settings"
on public.queue_settings;

create policy "Authenticated users can read queue settings"
on public.queue_settings
for select
to authenticated
using (true);

-- Authenticated users can manage queue records.
-- Replace these broad policies with role-based policies if your
-- application later adds an admin/staff role system.

drop policy if exists "Authenticated users can manage queue tickets"
on public.queue_tickets;

create policy "Authenticated users can manage queue tickets"
on public.queue_tickets
for all
to authenticated
using (true)
with check (true);

drop policy if exists "Authenticated users can read queue events"
on public.queue_events;

create policy "Authenticated users can read queue events"
on public.queue_events
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can create queue events"
on public.queue_events;

create policy "Authenticated users can create queue events"
on public.queue_events
for insert
to authenticated
with check (true);

-- ------------------------------------------------------------
-- 9. Helper function for generating the next daily ticket
-- ------------------------------------------------------------
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
security invoker
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

    -- Serialize sequence generation for the same date.
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

-- ------------------------------------------------------------
-- 10. Initial counters (optional)
-- ------------------------------------------------------------
-- Uncomment and edit if you want to create counters immediately.
--
-- insert into public.queue_counters (counter_number, counter_name)
-- values
--     (1, 'Counter 1'),
--     (2, 'Counter 2'),
--     (3, 'Counter 3');

-- ============================================================
-- END OF SCRIPT
-- ============================================================
