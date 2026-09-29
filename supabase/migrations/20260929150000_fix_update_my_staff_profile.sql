-- Migration: 20260929150000_fix_update_my_staff_profile.sql
-- Description: Allow staff to update their display name, last name, username, and doctor specialization.

DROP FUNCTION IF EXISTS public.update_my_staff_profile(text, text);
DROP FUNCTION IF EXISTS public.update_my_staff_profile(text, text, text);
DROP FUNCTION IF EXISTS public.update_my_staff_profile(text, text, text, text);

CREATE OR REPLACE FUNCTION public.update_my_staff_profile(
  p_display_name text,
  p_doctor_specialization text DEFAULT NULL,
  p_last_name text DEFAULT NULL,
  p_username text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email text;
  v_role text;
  v_display_name text;
  v_last_name text;
  v_username text;
  v_profile json;
BEGIN
  v_display_name := nullif(trim(coalesce(p_display_name, '')), '');
  IF v_display_name IS NULL THEN
    RETURN json_build_object('error', 'Display name is required');
  END IF;

  v_last_name := trim(coalesce(p_last_name, ''));
  v_username := nullif(trim(coalesce(p_username, '')), '');
  IF v_username IS NULL THEN
    v_username := v_display_name;
  END IF;

  -- Ensure current auth user is linked to an active staff profile
  SELECT lower(email) INTO v_user_email
  FROM auth.users
  WHERE id = auth.uid()
  LIMIT 1;

  IF v_user_email IS NULL THEN
    RETURN json_build_object('error', 'Authenticated user not found');
  END IF;

  UPDATE public.staff
  SET auth_user_id = auth.uid()
  WHERE auth_user_id IS NULL
    AND lower(email) = v_user_email
    AND lower(coalesce(status, '')) = 'active';

  SELECT lower(coalesce(role, '')) INTO v_role
  FROM public.staff
  WHERE auth_user_id = auth.uid()
    AND lower(coalesce(status, '')) = 'active'
  LIMIT 1;

  IF v_role IS NULL THEN
    RETURN json_build_object('error', 'Active staff profile not found');
  END IF;

  UPDATE public.staff
  SET
    first_name = v_display_name,
    last_name = nullif(v_last_name, ''),
    username = v_username,
    doctor_specialization = CASE
      WHEN v_role = 'doctor' THEN nullif(trim(coalesce(p_doctor_specialization, '')), '')
      ELSE doctor_specialization
    END
  WHERE auth_user_id = auth.uid()
    AND lower(coalesce(status, '')) = 'active';

  SELECT row_to_json(t) INTO v_profile
  FROM (
    SELECT id, first_name, middle_name, last_name, username, role, email, status, doctor_specialization
    FROM public.staff
    WHERE auth_user_id = auth.uid()
      AND lower(coalesce(status, '')) = 'active'
    LIMIT 1
  ) t;

  RETURN json_build_object(
    'message', 'Profile updated successfully',
    'profile', v_profile
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_my_staff_profile(text, text, text, text) TO authenticated, service_role;
