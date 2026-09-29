-- Migration: 20260929130000_prevent_duplicate_citizen_registration.sql
-- Description:
--   1. Create is_citizen_email_available() RPC to securely check email uniqueness against
--      public.citizens, public.staff, and auth.users before OTP / registration.
--   2. Create is_citizen_username_available() RPC to verify username uniqueness.
--   3. Update complete_my_citizen_profile() to strictly prevent overwriting existing citizen
--      profiles during credential setup.

-- 1. Helper function: is_citizen_email_available
CREATE OR REPLACE FUNCTION public.is_citizen_email_available(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_normalized text;
BEGIN
  v_normalized := lower(trim(coalesce(p_email, '')));
  IF v_normalized = '' OR v_normalized NOT LIKE '%_@__%.__%' THEN
    RETURN false;
  END IF;

  -- 1. Check if email exists in public.citizens
  IF EXISTS (
    SELECT 1 FROM public.citizens WHERE lower(trim(email)) = v_normalized
  ) THEN
    RETURN false;
  END IF;

  -- 2. Check if email exists in public.staff
  IF EXISTS (
    SELECT 1 FROM public.staff WHERE lower(trim(email)) = v_normalized
  ) THEN
    RETURN false;
  END IF;

  -- 3. Check if email exists in auth.users with password or linked to profile
  IF EXISTS (
    SELECT 1 FROM auth.users u
    WHERE lower(trim(u.email)) = v_normalized
      AND (
        (u.encrypted_password IS NOT NULL AND length(u.encrypted_password) > 0)
        OR EXISTS (SELECT 1 FROM public.citizens c WHERE c.auth_user_id = u.id)
        OR EXISTS (SELECT 1 FROM public.staff s WHERE s.auth_user_id = u.id)
      )
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_citizen_email_available(text) TO anon, authenticated, service_role;

-- 2. Helper function: is_citizen_username_available
CREATE OR REPLACE FUNCTION public.is_citizen_username_available(p_username text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_normalized text;
BEGIN
  v_normalized := lower(trim(coalesce(p_username, '')));
  IF v_normalized = '' THEN
    RETURN false;
  END IF;

  -- Check if username exists in public.citizens
  IF EXISTS (
    SELECT 1 FROM public.citizens WHERE lower(trim(username)) = v_normalized
  ) THEN
    RETURN false;
  END IF;

  -- Check if username exists in public.staff
  IF EXISTS (
    SELECT 1 FROM public.staff WHERE lower(trim(username)) = v_normalized
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_citizen_username_available(text) TO anon, authenticated, service_role;

-- 3. Update complete_my_citizen_profile to block overwriting existing citizen accounts
CREATE OR REPLACE FUNCTION public.complete_my_citizen_profile(
  p_firstname text,
  p_surname text,
  p_middle_initial text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_age integer DEFAULT NULL,
  p_contact_number text DEFAULT NULL,
  p_sex text DEFAULT NULL,
  p_complete_address text DEFAULT NULL,
  p_emergency_contact_complete_name text DEFAULT NULL,
  p_emergency_contact_contact_number text DEFAULT NULL,
  p_relation text DEFAULT NULL,
  p_username text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen_id bigint;
  v_username text;
  v_auth_email text;
BEGIN
  -- 1. Validate username
  v_username := nullif(trim(coalesce(p_username, '')), '');
  IF v_username IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Username is required.');
  END IF;

  -- 2. Check if username is taken by ANY citizen or staff
  IF EXISTS (
    SELECT 1
    FROM public.citizens c
    WHERE lower(trim(coalesce(c.username, ''))) = lower(v_username)
      AND c.auth_user_id <> auth.uid()
  ) OR EXISTS (
    SELECT 1
    FROM public.staff s
    WHERE lower(trim(coalesce(s.username, ''))) = lower(v_username)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Username already used, please choose another username.');
  END IF;

  -- 3. Resolve authenticated user's email
  v_auth_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  IF v_auth_email = '' THEN
     SELECT lower(trim(email)) INTO v_auth_email FROM auth.users WHERE id = auth.uid();
  END IF;

  -- 4. Block staff accounts from creating citizen profiles
  IF EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
       OR lower(trim(s.email)) = v_auth_email
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'This account is a staff account and cannot register as a citizen.');
  END IF;

  -- 5. Check if citizen record already exists for this auth_user_id or email
  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
     OR (v_auth_email <> '' AND lower(trim(c.email)) = v_auth_email)
  LIMIT 1;

  IF v_citizen_id IS NOT NULL THEN
    -- STRICT GUARD: Do not allow overwriting an existing citizen profile during registration
    RETURN jsonb_build_object('ok', false, 'error', 'This account has already completed registration. Please sign in instead.');
  END IF;

  -- 6. Insert new citizen profile
  INSERT INTO public.citizens (
    firstname, surname, middle_initial, date_of_birth, age,
    contact_number, sex, email, complete_address,
    emergency_contact_complete_name, emergency_contact_contact_number,
    relation, username, role, auth_user_id
  ) VALUES (
    trim(p_firstname),
    trim(p_surname),
    nullif(trim(p_middle_initial), ''),
    p_date_of_birth,
    p_age,
    nullif(trim(p_contact_number), ''),
    nullif(trim(p_sex), ''),
    v_auth_email,
    nullif(trim(p_complete_address), ''),
    nullif(trim(p_emergency_contact_complete_name), ''),
    nullif(trim(p_emergency_contact_contact_number), ''),
    nullif(trim(p_relation), ''),
    v_username,
    'citizen',
    auth.uid()
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_my_citizen_profile(
  text, text, text, date, integer, text, text, text, text, text, text, text
) TO authenticated, service_role;
