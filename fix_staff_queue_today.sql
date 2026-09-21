-- Run this in Supabase SQL Editor.
-- This function uses Philippine time and checks queue_date first,
-- then joined_at if queue_date is NULL.

create or replace function public.get_today_queue_tickets()
returns setof public.queue_tickets
language sql
security definer
set search_path = public
as $$
  select q.*
  from public.queue_tickets q
  where coalesce(
    q.queue_date,
    (q.joined_at at time zone 'Asia/Manila')::date
  ) = (now() at time zone 'Asia/Manila')::date
  order by q.sequence_number asc;
$$;

revoke all on function public.get_today_queue_tickets() from public;
grant execute on function public.get_today_queue_tickets() to anon, authenticated;
