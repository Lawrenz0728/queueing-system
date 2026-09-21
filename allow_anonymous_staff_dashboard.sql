-- TEMPORARY: Allow the no-login staff dashboard to read and manage queue data.
-- Apply this in Supabase SQL Editor.
-- Warning: this permits anyone with your Supabase project URL/key to access queue data.

drop policy if exists "Anonymous can read queue tickets" on public.queue_tickets;
create policy "Anonymous can read queue tickets"
on public.queue_tickets
for select
to anon
using (true);

drop policy if exists "Anonymous can update queue tickets" on public.queue_tickets;
create policy "Anonymous can update queue tickets"
on public.queue_tickets
for update
to anon
using (true)
with check (true);

drop policy if exists "Anonymous can read queue counters" on public.queue_counters;
create policy "Anonymous can read queue counters"
on public.queue_counters
for select
to anon
using (true);
