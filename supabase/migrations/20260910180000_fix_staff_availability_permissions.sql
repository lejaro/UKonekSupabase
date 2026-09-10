-- ==============================================================================
-- Migration: 20260910180000_fix_staff_availability_permissions.sql
-- Description: Fix doctor availability status not updating:
--   1. Allow self, admin, and clinical staff (nurses/triage) to update availability.
--   2. Robustly normalize input statuses ('break', 'on break', 'on_break', 'unavailable', 'off duty', 'off_duty', 'available', 'onduty').
--   3. Set row_security = off locally in SECURITY DEFINER to bypass table-level RLS blocks.
--   4. Allow 'admin' role rows in staff table to have availability_status updated.
--   5. Add row_security = off to list_staff_accounts() and list_available_doctor_schedules().
-- ==============================================================================

-- 1. Redefine public.set_staff_availability
CREATE OR REPLACE FUNCTION public.set_staff_availability(
  p_target_staff_id bigint default null,
  p_status text default 'available'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email text;
  v_actor_staff_id bigint;
  v_actor_role text;
  v_target_staff_id bigint;
  v_status text;
  v_is_admin boolean := false;
BEGIN
  -- Disable RLS locally so the security definer function can query & update public.staff safely
  PERFORM set_config('row_security', 'off', true);

  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  IF auth.uid() IS NULL AND v_user_email = '' THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Auto-link auth.uid to staff row if not yet linked
  UPDATE public.staff
  SET auth_user_id = auth.uid()
  WHERE auth.uid() IS NOT NULL
    AND auth_user_id IS NULL
    AND lower(email) = v_user_email
    AND lower(coalesce(status, '')) = 'active';

  -- Resolve the calling staff record
  SELECT s.id, lower(coalesce(s.role, ''))
    INTO v_actor_staff_id, v_actor_role
  FROM public.staff s
  WHERE lower(coalesce(s.status, '')) = 'active'
    AND (
      (auth.uid() IS NOT NULL AND s.auth_user_id = auth.uid())
      OR (v_user_email <> '' AND lower(s.email) = v_user_email)
    )
  ORDER BY CASE WHEN lower(coalesce(s.role, '')) = 'doctor' THEN 0 ELSE 1 END, s.id ASC
  LIMIT 1;

  -- Check if caller is admin via is_admin() or role
  v_is_admin := (v_actor_role = 'admin') OR public.is_admin();

  IF v_actor_staff_id IS NULL AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Active staff account required';
  END IF;

  v_target_staff_id := coalesce(p_target_staff_id, v_actor_staff_id);

  IF v_target_staff_id IS NULL THEN
    RAISE EXCEPTION 'Target staff ID is required';
  END IF;

  -- ENFORCE PERMISSIONS:
  -- Allowed if:
  --   1. Updating own availability (v_target_staff_id = v_actor_staff_id)
  --   2. Admin user (v_is_admin = true)
  --   3. Clinical / triage staff managing stations (v_actor_role in ('nurse', 'staff'))
  IF v_target_staff_id <> coalesce(v_actor_staff_id, -1) AND NOT v_is_admin AND v_actor_role NOT IN ('nurse', 'staff') THEN
    RAISE EXCEPTION 'Forbidden: you can only update your own availability status';
  END IF;

  -- Robust status normalization
  v_status := lower(trim(coalesce(p_status, 'available')));
  IF v_status IN ('on break', 'break', 'on_break') THEN
    v_status := 'on_break';
  ELSIF v_status IN ('unavailable', 'off duty', 'off_duty', 'offduty') THEN
    v_status := 'unavailable';
  ELSIF v_status IN ('available', 'on duty', 'on_duty', 'onduty') THEN
    v_status := 'available';
  END IF;

  IF v_status NOT IN ('available', 'on_break', 'unavailable') THEN
    RAISE EXCEPTION 'Invalid availability status: %', p_status;
  END IF;

  -- Update target staff record (supports doctors, nurses, specialists, staff, and admin)
  UPDATE public.staff
  SET availability_status = v_status
  WHERE id = v_target_staff_id
    AND lower(trim(coalesce(role, ''))) IN ('doctor', 'nurse', 'staff', 'specialist', 'admin')
    AND lower(coalesce(status, '')) = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unable to update staff availability for staff id %', v_target_staff_id;
  END IF;

  RETURN json_build_object(
    'staff_id', v_target_staff_id,
    'availability_status', v_status,
    'success', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_staff_availability(bigint, text) TO authenticated;

-- 2. Redefine list_staff_accounts with row_security = off
CREATE OR REPLACE FUNCTION public.list_staff_accounts()
RETURNS TABLE (
  id bigint,
  first_name varchar,
  middle_name varchar,
  last_name varchar,
  birthday date,
  gender varchar,
  username varchar,
  employee_id varchar,
  email varchar,
  role varchar,
  status varchar,
  doctor_specialization text,
  is_online boolean,
  last_seen timestamptz,
  availability_status text,
  created_at timestamptz,
  auth_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('row_security', 'off', true);
  RETURN QUERY
  SELECT
    s.id,
    s.first_name,
    s.middle_name,
    s.last_name,
    s.birthday,
    s.gender,
    s.username,
    s.employee_id,
    s.email,
    s.role,
    s.status,
    s.doctor_specialization,
    s.is_online,
    s.last_seen,
    coalesce(s.availability_status, 'available') AS availability_status,
    s.created_at,
    s.auth_user_id
  FROM public.staff s
  WHERE lower(coalesce(s.status, '')) = 'active'
  ORDER BY s.id DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_staff_accounts() TO authenticated, anon;

-- 3. Redefine list_available_doctor_schedules with row_security = off
CREATE OR REPLACE FUNCTION public.list_available_doctor_schedules(
  p_date_from date default current_date,
  p_date_to date default (current_date + interval '30 days')::date
)
RETURNS TABLE (
  id bigint,
  doctor_staff_id bigint,
  doctor_name varchar,
  specialization text,
  schedule_date date,
  start_time time,
  end_time time,
  notes text,
  availability_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('row_security', 'off', true);

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  PERFORM public.purge_expired_doctor_schedules();

  RETURN QUERY
  SELECT
    ds.id,
    ds.doctor_staff_id,
    coalesce(
      nullif(trim(ds.doctor_name), ''),
      trim(concat(coalesce(s.first_name, ''), ' ', coalesce(s.last_name, '')))
    )::varchar AS doctor_name,
    coalesce(s.doctor_specialization, '')::text AS specialization,
    ds.schedule_date,
    ds.start_time,
    ds.end_time,
    ds.notes,
    coalesce(s.availability_status, 'available') AS availability_status
  FROM public.doctor_schedules ds
  JOIN public.staff s
    ON s.id = ds.doctor_staff_id
  WHERE lower(trim(coalesce(s.role, ''))) = 'doctor'
    AND lower(trim(coalesce(s.status, ''))) = 'active'
    AND lower(trim(coalesce(s.availability_status, 'available'))) IN ('available', 'on_break')
    AND ds.schedule_date >= p_date_from
    AND ds.schedule_date <= p_date_to
  ORDER BY ds.schedule_date ASC, ds.start_time ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_available_doctor_schedules(date, date) TO authenticated;
