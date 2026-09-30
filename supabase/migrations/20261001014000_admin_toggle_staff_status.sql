-- Migration: 20261001014000_admin_toggle_staff_status.sql
-- Description: Administrative RPC to toggle staff account status (active / disabled).
--              Enforces case-insensitive lowercase 'active' / 'disabled' to satisfy
--              staff_status_lowercase check constraint, prevents self-disabling,
--              and synchronizes auth.users banned_until state.

CREATE OR REPLACE FUNCTION public.toggle_staff_status_admin(
  target_staff_id bigint,
  p_status text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_normalized_status text;
  v_updated_staff public.staff%rowtype;
  v_auth_user_id uuid;
  v_staff_email text;
  v_current_email text;
BEGIN
  -- 1. Ensure caller has active administrator privileges
  IF NOT (public.is_admin() OR auth.role() = 'service_role' OR current_user = 'postgres') THEN
    RETURN json_build_object('success', false, 'error', 'Forbidden: admin role required');
  END IF;

  -- 2. Validate and normalize status to lowercase
  v_normalized_status := lower(trim(coalesce(p_status, '')));
  IF v_normalized_status NOT IN ('active', 'disabled') THEN
    RETURN json_build_object('success', false, 'error', 'Invalid status. Status must be active or disabled.');
  END IF;

  -- 3. Resolve target staff member
  SELECT auth_user_id, lower(trim(coalesce(email, '')))
    INTO v_auth_user_id, v_staff_email
  FROM public.staff
  WHERE id = target_staff_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Staff account not found');
  END IF;

  v_current_email := lower(trim(coalesce(auth.jwt()->>'email', '')));

  -- 4. Guardrail: Administrator cannot disable their own account
  IF (v_auth_user_id IS NOT NULL AND v_auth_user_id = auth.uid())
     OR (v_current_email <> '' AND v_staff_email = v_current_email) THEN
    RETURN json_build_object('success', false, 'error', 'Guardrail Active: You cannot disable your own admin account');
  END IF;

  -- 5. Update public.staff status
  UPDATE public.staff
  SET status = v_normalized_status
  WHERE id = target_staff_id
  RETURNING * INTO v_updated_staff;

  -- 6. Synchronize auth.users login access:
  --    If disabled: set banned_until far into future to immediately reject login / token refreshes.
  --    If active: clear banned_until to restore full login capability.
  IF v_auth_user_id IS NOT NULL THEN
    IF v_normalized_status = 'disabled' THEN
      UPDATE auth.users
      SET banned_until = '2099-01-01 00:00:00+00'::timestamptz
      WHERE id = v_auth_user_id;
    ELSE
      UPDATE auth.users
      SET banned_until = NULL
      WHERE id = v_auth_user_id;
    END IF;
  ELSIF v_staff_email <> '' THEN
    IF v_normalized_status = 'disabled' THEN
      UPDATE auth.users
      SET banned_until = '2099-01-01 00:00:00+00'::timestamptz
      WHERE lower(trim(email)) = v_staff_email;
    ELSE
      UPDATE auth.users
      SET banned_until = NULL
      WHERE lower(trim(email)) = v_staff_email;
    END IF;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', format('Staff account successfully %s', CASE WHEN v_normalized_status = 'disabled' THEN 'disabled' ELSE 'enabled' END),
    'status', v_normalized_status,
    'staff', row_to_json(v_updated_staff)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.toggle_staff_status_admin(bigint, text) TO authenticated;

-- Also update public.update_staff_account_admin to support optional p_status
CREATE OR REPLACE FUNCTION public.update_staff_account_admin(
  target_staff_id bigint,
  p_first_name text DEFAULT NULL,
  p_last_name text DEFAULT NULL,
  p_middle_name text DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_employee_id text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_birthday date DEFAULT NULL,
  p_status text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_updated_staff public.staff%rowtype;
  v_auth_user_id uuid;
  v_clean_status text := NULL;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin role required';
  END IF;

  SELECT auth_user_id INTO v_auth_user_id
  FROM public.staff
  WHERE id = target_staff_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Staff account not found';
  END IF;

  IF p_status IS NOT NULL AND trim(p_status) <> '' THEN
    v_clean_status := lower(trim(p_status));
    IF v_clean_status NOT IN ('active', 'disabled') THEN
      RAISE EXCEPTION 'Invalid status. Must be active or disabled';
    END IF;
  END IF;

  UPDATE public.staff
  SET
    first_name = coalesce(nullif(trim(p_first_name), ''), first_name),
    last_name = coalesce(nullif(trim(p_last_name), ''), last_name),
    middle_name = nullif(trim(p_middle_name), ''),
    username = coalesce(nullif(trim(p_username), ''), username),
    email = coalesce(nullif(trim(lower(p_email)), ''), email),
    employee_id = coalesce(nullif(trim(p_employee_id), ''), employee_id),
    role = coalesce(nullif(trim(lower(p_role)), ''), role),
    birthday = coalesce(p_birthday, birthday),
    status = coalesce(v_clean_status, status)
  WHERE id = target_staff_id
  RETURNING * INTO v_updated_staff;

  -- Synchronize auth.users email if changed
  IF v_auth_user_id IS NOT NULL AND p_email IS NOT NULL AND trim(p_email) <> '' THEN
    UPDATE auth.users
    SET email = lower(trim(p_email))
    WHERE id = v_auth_user_id;
  END IF;

  -- Synchronize banned_until if status updated
  IF v_auth_user_id IS NOT NULL AND v_clean_status IS NOT NULL THEN
    IF v_clean_status = 'disabled' THEN
      UPDATE auth.users SET banned_until = '2099-01-01 00:00:00+00'::timestamptz WHERE id = v_auth_user_id;
    ELSE
      UPDATE auth.users SET banned_until = NULL WHERE id = v_auth_user_id;
    END IF;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Staff account updated successfully',
    'staff', row_to_json(v_updated_staff)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_staff_account_admin(bigint, text, text, text, text, text, text, text, date, text) TO authenticated;
