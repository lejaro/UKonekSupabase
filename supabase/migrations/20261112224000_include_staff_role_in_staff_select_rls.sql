-- Migration: 20261112224000_include_staff_role_in_staff_select_rls.sql
-- Description: Ensure legacy 'staff' (nurse) and 'specialist' (doctor) roles are included in
--              staff_select_unified so doctors see all nurse availability statuses in real time
--              and direct table reads match isScheduleRole() in scheduleController.js.

DROP POLICY IF EXISTS staff_select_unified ON public.staff;

CREATE POLICY staff_select_unified
  ON public.staff FOR SELECT
  TO authenticated
  USING (
    -- A. Own profile
    auth_user_id = (SELECT auth.uid())
    OR (
      (SELECT auth.jwt() ->> 'email') IS NOT NULL
      AND lower(trim(email)) = lower(trim((SELECT auth.jwt() ->> 'email')))
    )
    -- B. Active clinical staff (doctors, specialists, nurses, and legacy 'staff' nurses)
    OR (
      lower(coalesce(status, '')) = 'active'
      AND lower(coalesce(role, '')) IN ('doctor', 'specialist', 'nurse', 'staff')
    )
    -- C. Admin check via JWT metadata or is_admin()
    OR (((SELECT auth.jwt()) -> 'user_metadata' ->> 'role') = 'admin')
    OR (((SELECT auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
    OR (SELECT public.is_admin())
  );

COMMENT ON POLICY staff_select_unified ON public.staff IS
  'Restricts staff table SELECT to authenticated users while exposing active clinical staff (doctor, specialist, nurse, staff) for availability & Realtime sync.';
