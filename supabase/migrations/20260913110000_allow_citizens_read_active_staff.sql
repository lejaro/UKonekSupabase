-- Migration: 20260913110000_allow_citizens_read_active_staff.sql
-- Description: Allow authenticated citizens (and anon) to view active clinical staff (doctors and nurses).
-- This enables Supabase Realtime (which respects RLS) to broadcast staff availability changes to mobile citizen clients.

-- 1. Ensure staff table is in supabase_realtime publication and replica identity is FULL
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

-- 2. Allow authenticated users and anon clients to select active clinical staff (doctors and nurses)
-- This permits Realtime websocket engine to broadcast postgres_changes on public.staff to mobile citizen sessions.
DROP POLICY IF EXISTS staff_select_citizens_view_doctors ON public.staff;
CREATE POLICY staff_select_citizens_view_doctors
  ON public.staff FOR SELECT
  TO authenticated, anon
  USING (
    lower(coalesce(status, '')) = 'active'
    AND lower(coalesce(role, '')) IN ('doctor', 'nurse')
  );

COMMENT ON POLICY staff_select_citizens_view_doctors ON public.staff IS
  'Permits mobile citizens and public clients to read active doctors and nurses so Supabase Realtime broadcasts availability status changes.';
