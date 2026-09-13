-- ==============================================================================
-- Migration: 20260913140000_fix_staff_rls_recursion_for_realtime.sql
-- Description: Fix PostgreSQL 42501 error in realtime.apply_rls:
--              "query would be affected by row-level security policy for table staff"
--              This eliminates recursive function calls (is_admin(), is_active_staff())
--              inside policies on public.staff so Supabase Realtime can broadcast
--              doctor availability status updates instantly to mobile and web clients.
-- ==============================================================================

-- 1. Ensure supabase_realtime publication and replica identity
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'staff'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.staff;
  END IF;
END $$;

ALTER TABLE public.staff REPLICA IDENTITY FULL;

-- Grant supabase_realtime_admin permissions to read staff and queue_tickets
GRANT USAGE ON SCHEMA public TO supabase_realtime_admin;
GRANT SELECT ON public.staff TO supabase_realtime_admin;
GRANT SELECT ON public.queue_tickets TO supabase_realtime_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO supabase_realtime_admin;

-- 2. Drop all recursive/self-referencing policies on public.staff
DROP POLICY IF EXISTS staff_select_admin ON public.staff;
DROP POLICY IF EXISTS staff_select_policy ON public.staff;
DROP POLICY IF EXISTS staff_select_citizens_view_doctors ON public.staff;
DROP POLICY IF EXISTS staff_update_admin ON public.staff;
DROP POLICY IF EXISTS staff_delete_admin ON public.staff;
DROP POLICY IF EXISTS staff_select_unified ON public.staff;
DROP POLICY IF EXISTS staff_update_unified ON public.staff;
DROP POLICY IF EXISTS staff_delete_unified ON public.staff;

-- 3. Create non-recursive, lightning-fast RLS policies for public.staff
-- NOTE: Never query public.staff within a policy on public.staff!
CREATE POLICY staff_select_unified
  ON public.staff FOR SELECT
  TO authenticated, anon
  USING (
    -- A. Own profile
    auth_user_id = auth.uid()
    OR (auth.jwt()->>'email' IS NOT NULL AND lower(trim(email)) = lower(trim(auth.jwt()->>'email')))
    -- B. Active clinical staff (doctors & nurses) visible to citizens and public clients
    OR (lower(coalesce(status, '')) = 'active' AND lower(coalesce(role, '')) IN ('doctor', 'nurse'))
    -- C. Admin check via JWT metadata (no table query recursion)
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  );

CREATE POLICY staff_update_unified
  ON public.staff FOR UPDATE
  TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  )
  WITH CHECK (
    auth_user_id = auth.uid()
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  );

CREATE POLICY staff_delete_unified
  ON public.staff FOR DELETE
  TO authenticated
  USING (
    ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  );

COMMENT ON POLICY staff_select_unified ON public.staff IS
  'Direct column and JWT policy with zero table recursion, allowing Realtime WAL filter engine to broadcast doctor availability updates without 42501 errors.';
