-- Migration: 20261011211500_enable_realtime_and_rls_for_prescription_headers.sql
-- Description:
--   1. Adds prescription_headers to supabase_realtime publication with REPLICA IDENTITY FULL
--      so instant mobile alerts trigger immediately when a doctor creates an e-prescription.
--   2. Grants SELECT to supabase_realtime_admin.
--   3. Adds RLS SELECT policy on prescription_headers for authenticated citizens to view/stream
--      their own prescription records.

-- 1. Ensure prescription_headers is in supabase_realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'prescription_headers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.prescription_headers;
  END IF;
END $$;

-- 2. Replica identity FULL so update/insert payloads include all row data
ALTER TABLE public.prescription_headers REPLICA IDENTITY FULL;

-- 3. Permissions for realtime admin
GRANT SELECT ON public.prescription_headers TO supabase_realtime_admin;

-- 4. Citizen SELECT policy on prescription_headers
DROP POLICY IF EXISTS prescription_headers_select_own_citizen ON public.prescription_headers;
CREATE POLICY prescription_headers_select_own_citizen
  ON public.prescription_headers FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.citizens c
      WHERE c.auth_user_id = auth.uid()
        AND (
          c.id = prescription_headers.patient_citizen_id
          OR c.id::text = prescription_headers.patient_identifier
          OR ('CIT-' || c.id::text) = prescription_headers.patient_identifier
          OR EXISTS (
            SELECT 1 FROM public.queue_tickets qt
            WHERE qt.citizen_id = c.id
              AND (
                qt.ticket_code = prescription_headers.patient_identifier
                OR ('QUEUE-' || qt.id::text) = prescription_headers.patient_identifier
                OR qt.id::text = prescription_headers.patient_identifier
              )
          )
        )
    )
  );
