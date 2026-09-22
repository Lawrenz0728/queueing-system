-- FINAL FIX FOR REGISTER_STAFF_V2
-- Your current Supabase function exists, but its INPUT PARAMETER NAMES are:
-- p_passcode, p_password, p_username
-- while the webpage calls:
-- p_username, p_password, p_passcode.
--
-- PostgreSQL does not allow changing input parameter names with CREATE OR REPLACE,
-- so we must DROP the existing function and recreate it with the exact names
-- used by the webpage.

drop function if exists public.register_staff_v2(text, text, text);

create function public.register_staff_v2(
    p_username text,
    p_password text,
    p_passcode text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_username text;
    v_id uuid;
    v_passcode_hash text;
begin
    v_username := trim(coalesce(p_username, ''));

    if v_username = '' then
        return json_build_object(
            'success', false,
            'message', 'Username is required.'
        );
    end if;

    if v_username !~ '^[A-Za-z0-9._-]{3,50}$' then
        return json_build_object(
            'success', false,
            'message', 'Username must be 3-50 characters and use only letters, numbers, dot, underscore, or hyphen.'
        );
    end if;

    if p_password is null or length(p_password) < 6 then
        return json_build_object(
            'success', false,
            'message', 'Password must be at least 6 characters.'
        );
    end if;

    select registration_passcode_hash
      into v_passcode_hash
      from public.staff_settings
     where id = 1;

    if v_passcode_hash is null then
        return json_build_object(
            'success', false,
            'message', 'Staff registration passcode is not configured in Supabase.'
        );
    end if;

    if crypt(coalesce(p_passcode, ''), v_passcode_hash) <> v_passcode_hash then
        return json_build_object(
            'success', false,
            'message', 'Invalid registration passcode.'
        );
    end if;

    if exists (
        select 1
          from public.staff_accounts
         where lower(username) = lower(v_username)
    ) then
        return json_build_object(
            'success', false,
            'message', 'Username is already registered.'
        );
    end if;

    insert into public.staff_accounts (username, password_hash)
    values (
        v_username,
        crypt(p_password, gen_salt('bf'))
    )
    returning id into v_id;

    return json_build_object(
        'success', true,
        'message', 'Staff account created successfully.',
        'staff_id', v_id,
        'username', v_username
    );
end;
$$;

grant execute on function public.register_staff_v2(text, text, text)
to anon, authenticated;

-- Ask PostgREST to reload its schema cache.
select pg_notify('pgrst', 'reload schema');

-- Verification: this must show:
-- p_username text, p_password text, p_passcode text
select
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'register_staff_v2';
