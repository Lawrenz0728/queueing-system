-- Run in Supabase SQL Editor.
-- Allows the no-login staff dashboard to read queue records.

grant usage on schema public to anon;
grant select on table public.queue_tickets to anon;

alter table public.queue_tickets enable row level security;

drop policy if exists "Staff dashboard can read queue tickets" on public.queue_tickets;
create policy "Staff dashboard can read queue tickets"
on public.queue_tickets
for select
to anon
using (true);
