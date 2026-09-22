-- CUSTOM STAFF AUTHENTICATION (NO EMAIL / NO SUPABASE EMAIL AUTH)
-- Run this entire script once in Supabase SQL Editor.
-- Registration passcode: CHANGE-ME-2026

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'staff_account_status') then
    create type public.staff_account_status as enum ('active','disabled');
  end if;
end $$;

create table if not exists public.staff_accounts (
  id uuid primary key default gen_random_uuid(),
  username text not null,
  username_normalized text generated always as (lower(trim(username))) stored,
  password_hash text not null,
  status public.staff_account_status not null default 'active',
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

create unique index if not exists staff_accounts_username_normalized_key
  on public.staff_accounts(username_normalized);

create table if not exists public.staff_auth_config (
  id integer primary key check (id = 1),
  registration_passcode_hash bytea not null,
  updated_at timestamptz not null default now()
);

insert into public.staff_auth_config(id, registration_passcode_hash)
values (1, extensions.digest('CHANGE-ME-2026', 'sha256'))
on conflict (id) do nothing;

create table if not exists public.staff_sessions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_accounts(id) on delete cascade,
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);

create index if not exists staff_sessions_staff_id_idx on public.staff_sessions(staff_id);
create index if not exists staff_sessions_expires_at_idx on public.staff_sessions(expires_at);

alter table public.staff_accounts enable row level security;
alter table public.staff_auth_config enable row level security;
alter table public.staff_sessions enable row level security;

-- No direct browser access to these tables.
drop policy if exists "No direct staff account access" on public.staff_accounts;
drop policy if exists "No direct staff config access" on public.staff_auth_config;
drop policy if exists "No direct staff session access" on public.staff_sessions;

create or replace function public.register_staff(
  p_username text,
  p_password text,
  p_passcode text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text := lower(trim(p_username));
  v_staff_id uuid;
begin
  if v_username !~ '^[a-z0-9][a-z0-9._-]{2,49}$' then
    raise exception 'Username must be 3-50 characters and use only letters, numbers, dot, underscore, or hyphen.';
  end if;

  if length(p_password) < 6 then
    raise exception 'Password must contain at least 6 characters.';
  end if;

  if p_passcode is null or extensions.digest(p_passcode, 'sha256') <>
     (select registration_passcode_hash from public.staff_auth_config where id = 1) then
    raise exception 'Invalid staff registration passcode.';
  end if;

  if exists (select 1 from public.staff_accounts where username_normalized = v_username) then
    raise exception 'Username is already registered.';
  end if;

  insert into public.staff_accounts(username, password_hash)
  values (v_username, extensions.crypt(p_password, extensions.gen_salt('bf', 10)))
  returning id into v_staff_id;

  return jsonb_build_object(
    'success', true,
    'staff_id', v_staff_id,
    'username', v_username
  );
exception
  when unique_violation then
    raise exception 'Username is already registered.';
end;
$$;

grant execute on function public.register_staff(text,text,text) to anon, authenticated;

create or replace function public.login_staff(
  p_username text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff public.staff_accounts%rowtype;
  v_token text;
begin
  select * into v_staff
  from public.staff_accounts
  where username_normalized = lower(trim(p_username))
  limit 1;

  if v_staff.id is null or v_staff.status <> 'active' then
    raise exception 'Invalid username or password.';
  end if;

  if v_staff.password_hash <> extensions.crypt(p_password, v_staff.password_hash) then
    raise exception 'Invalid username or password.';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.staff_sessions(staff_id, token_hash, expires_at)
  values (v_staff.id, extensions.digest(v_token, 'sha256'), now() + interval '12 hours');

  update public.staff_accounts
  set last_login_at = now()
  where id = v_staff.id;

  delete from public.staff_sessions where expires_at < now();

  return jsonb_build_object(
    'success', true,
    'token', v_token,
    'staff_id', v_staff.id,
    'username', v_staff.username,
    'expires_at', (now() + interval '12 hours')
  );
end;
$$;

grant execute on function public.login_staff(text,text) to anon, authenticated;

create or replace function public.verify_staff_session(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff public.staff_accounts%rowtype;
begin
  select a.* into v_staff
  from public.staff_sessions s
  join public.staff_accounts a on a.id = s.staff_id
  where s.token_hash = extensions.digest(p_token, 'sha256')
    and s.expires_at > now()
    and a.status = 'active'
  limit 1;

  if v_staff.id is null then
    raise exception 'Staff session expired or invalid.';
  end if;

  return jsonb_build_object('valid', true, 'staff_id', v_staff.id, 'username', v_staff.username);
end;
$$;

grant execute on function public.verify_staff_session(text) to anon, authenticated;

create or replace function public.logout_staff(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.staff_sessions
  where token_hash = extensions.digest(p_token, 'sha256');
  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.logout_staff(text) to anon, authenticated;

-- Staff-only queue RPCs. These bypass table RLS only after the staff token is verified.
create or replace function public.staff_get_queue_counters(p_token text)
returns setof public.queue_counters
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public.verify_staff_session(p_token);
  return query
    select * from public.queue_counters order by counter_name;
end;
$$;
grant execute on function public.staff_get_queue_counters(text) to anon, authenticated;

create or replace function public.staff_get_queue_tickets(p_token text)
returns setof public.queue_tickets
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public.verify_staff_session(p_token);
  return query
    select * from public.queue_tickets order by joined_at desc limit 1000;
end;
$$;
grant execute on function public.staff_get_queue_tickets(text) to anon, authenticated;

create or replace function public.staff_update_queue_ticket(
  p_token text,
  p_ticket_id uuid,
  p_status text,
  p_counter_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff jsonb;
  v_username text;
begin
  v_staff := public.verify_staff_session(p_token);
  v_username := v_staff->>'username';

  if p_status in ('Called','Serving') then
    update public.queue_tickets
    set status = p_status,
        called_at = coalesce(called_at, now()),
        serving_at = case when p_status = 'Serving' then coalesce(serving_at, now()) else serving_at end,
        counter_id = p_counter_id,
        updated_at = now()
    where id = p_ticket_id;
  elsif p_status in ('Completed','Done') then
    update public.queue_tickets
    set status = 'Completed', completed_at = now(), updated_at = now()
    where id = p_ticket_id;
  elsif p_status = 'Skipped' then
    update public.queue_tickets
    set status = 'Skipped', updated_at = now()
    where id = p_ticket_id;
  else
    raise exception 'Invalid queue status.';
  end if;

  if not found then raise exception 'Queue ticket not found.'; end if;
  return jsonb_build_object('success', true, 'username', v_username);
end;
$$;
grant execute on function public.staff_update_queue_ticket(text,uuid,text,uuid) to anon, authenticated;

-- Change the registration passcode later with:
-- update public.staff_auth_config
-- set registration_passcode_hash = extensions.digest('YOUR-NEW-PASSCODE','sha256'), updated_at = now()
-- where id = 1;
