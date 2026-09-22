-- Fresh registration RPC using the exact parameter order currently requested by the live page.
DROP FUNCTION IF EXISTS public.register_staff_v4(text, text, text);

CREATE OR REPLACE FUNCTION public.register_staff_v4(
    p_passcode text,
    p_password text,
    p_username text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_username text;
    v_staff_id uuid;
    v_expected_hash text;
BEGIN
    v_username := lower(trim(coalesce(p_username, '')));

    IF v_username = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Username is required.');
    END IF;

    IF length(coalesce(p_password, '')) < 6 THEN
        RETURN jsonb_build_object('success', false, 'message', 'Password must be at least 6 characters.');
    END IF;

    SELECT registration_passcode_hash
    INTO v_expected_hash
    FROM public.staff_settings
    WHERE id = 1;

    IF v_expected_hash IS NULL
       OR extensions.crypt(coalesce(p_passcode, ''), v_expected_hash) <> v_expected_hash THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid registration passcode.');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.staff_accounts
        WHERE lower(username) = v_username
    ) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Username is already registered.');
    END IF;

    INSERT INTO public.staff_accounts (
        username,
        password_hash,
        status
    )
    VALUES (
        v_username,
        extensions.crypt(p_password, extensions.gen_salt('bf')),
        'active'
    )
    RETURNING id INTO v_staff_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Staff account created successfully.',
        'staff_id', v_staff_id,
        'username', v_username
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_staff_v4(text, text, text)
TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'register_staff_v4';
