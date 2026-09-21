-- Fix: allow the no-login staff dashboard to load today's queue.
-- Run this entire script in Supabase SQL Editor.

create or replace function public.get_today_queue_tickets()
returns setof public.queue_tickets
language sql
security definer
set search_path = public
as $$
  select *
  from public.queue_tickets
  where queue_date = current_date
  order by sequence_number asc;
$$;

revoke all on function public.get_today_queue_tickets() from public;
grant execute on function public.get_today_queue_tickets() to anon, authenticated;
