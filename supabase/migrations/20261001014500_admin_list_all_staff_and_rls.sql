-- Migration: 20261001014500_admin_list_all_staff_and_rls.sql
-- Description: Enable administrators to view and manage all staff accounts
--              regardless of status (including disabled accounts and pharmacists).

-- 1. Create list_all_staff_admin RPC for secure retrieval of all staff
CREATE OR REPLACE FUNCTION public.list_all_staff_admin()
RETURNS TABLE (
  id bigint,
  first_name text,
  middle_name text,
  last_name text,
  birthday date,
  gender text,
  username text,
  employee_id text,
  email text,
  role text,
  consent_given boolean,
  status text,
  is_online boolean,
  last_seen timestamptz,
  doctor_specialization text,
  availability_status text,
  created_at timestamptz,
  auth_user_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT (public.is_admin() OR auth.role() = 'service_role' OR current_user = 'postgres') THEN
    RAISE EXCEPTION 'Forbidden: admin role required';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.first_name::text,
    s.middle_name::text,
    s.last_name::text,
    s.birthday,
    s.gender::text,
    s.username::text,
    s.employee_id::text,
    s.email::text,
    s.role::text,
    s.consent_given,
    s.status::text,
    s.is_online,
    s.last_seen,
    s.doctor_specialization::text,
    s.availability_status::text,
    s.created_at,
    s.auth_user_id
  FROM public.staff s
  ORDER BY s.id DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_all_staff_admin() TO authenticated;

-- 2. Update staff_select_unified RLS policy to include public.is_admin()
DROP POLICY IF EXISTS staff_select_unified ON public.staff;
CREATE POLICY staff_select_unified
  ON public.staff FOR SELECT
  TO authenticated, anon
  USING (
    -- A. Own profile
    auth_user_id = auth.uid()
    OR (auth.jwt()->>'email' IS NOT NULL AND lower(trim(email)) = lower(trim(auth.jwt()->>'email')))
    -- B. Active clinical staff (doctors & nurses) visible to citizens and public clients
    OR (lower(coalesce(status, '')) = 'active' AND lower(coalesce(role, '')) IN ('doctor', 'nurse'))
    -- C. Admin check via JWT metadata or is_admin() function
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
    OR public.is_admin()
  );

-- 3. Update staff_update_unified RLS policy to include public.is_admin()
DROP POLICY IF EXISTS staff_update_unified ON public.staff;
CREATE POLICY staff_update_unified
  ON public.staff FOR UPDATE
  TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
    OR public.is_admin()
  )
  WITH CHECK (
    auth_user_id = auth.uid()
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
    OR public.is_admin()
  );
