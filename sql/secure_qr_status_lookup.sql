-- ============================================================
-- Secure QR Ticket Status Lookup
-- Run in Supabase SQL Editor.
-- ============================================================

create or replace function public.get_queue_ticket_status(
    p_qr_token uuid
)
returns table (
    ticket_number text,
    customer_name text,
    service_name text,
    status text,
    priority text,
    queue_date date,
    joined_at timestamptz,
    called_at timestamptz
)
language sql
security definer
set search_path = public
as $$
    select
        qt.ticket_number,
        qt.customer_name,
        qt.service_name,
        qt.status,
        qt.priority,
        qt.queue_date,
        qt.joined_at,
        qt.called_at
    from public.queue_tickets qt
    where qt.qr_token = p_qr_token
    limit 1;
$$;

revoke all on function public.get_queue_ticket_status(uuid) from public;
grant execute on function public.get_queue_ticket_status(uuid) to anon, authenticated;
