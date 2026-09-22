-- Create a fresh RPC name to avoid the stale register_staff_v2 schema entry.
drop function if exists public.register_staff_v3(text, text, text);

create function public.register_staff_v3(
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
        return json_build_object('success', false, 'message', 'Username is required.');
    end if;

    if v_username !~ '^[A-Za-z0-9._-]{3,50}$' then
        return json_build_object('success', false, 'message',
            'Username must be 3-50 characters and use only letters, numbers, dot, underscore, or hyphen.');
    end if;

    if p_password is null or length(p_password) < 6 then
        return json_build_object('success', false, 'message', 'Password must be at least 6 characters.');
    end if;

    select registration_passcode_hash
      into v_passcode_hash
      from public.staff_settings
     where id = 1;

    if v_passcode_hash is null then
        return json_build_object('success', false, 'message', 'Registration passcode is not configured.');
    end if;

    if crypt(coalesce(p_passcode, ''), v_passcode_hash) <> v_passcode_hash then
        return json_build_object('success', false, 'message', 'Invalid registration passcode.');
    end if;

    if exists (
        select 1 from public.staff_accounts
        where lower(username) = lower(v_username)
    ) then
        return json_build_object('success', false, 'message', 'Username is already registered.');
    end if;

    insert into public.staff_accounts (username, password_hash)
    values (v_username, crypt(p_password, gen_salt('bf')))
    returning id into v_id;

    return json_build_object(
        'success', true,
        'message', 'Staff account created successfully.',
        'staff_id', v_id,
        'username', v_username
    );
end;
$$;

grant execute on function public.register_staff_v3(text, text, text) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

select
    p.proname,
    pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'register_staff_v3';
