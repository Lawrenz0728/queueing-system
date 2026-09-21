-- ============================================================
-- Queue Statistics for the Customer Ticket Page
-- Run this in Supabase SQL Editor.
-- ============================================================

create or replace function public.get_queue_stats()
returns table (
    in_line_count bigint,
    waiting_count bigint
)
language sql
security definer
set search_path = public
as $$
    select
        count(*) filter (
            where status in ('Waiting', 'Ongoing')
        ) as in_line_count,
        count(*) filter (
            where status = 'Waiting'
        ) as waiting_count
    from public.queue_tickets
    where queue_date = current_date;
$$;

revoke all on function public.get_queue_stats() from public;
grant execute on function public.get_queue_stats() to anon, authenticated;
