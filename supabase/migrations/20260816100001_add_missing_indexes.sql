-- =============================================================================
-- P1-6: Add 3 Live-Confirmed Missing Indexes
--
-- Live DB verification (2026-08-16) confirmed these 3 indexes are missing
-- and required for hot query paths:
-- 1. prescription_headers(patient_identifier) - used in health records OR queries
-- 2. lab_orders(patient_citizen_id) - used in patient health records modal
-- 3. lab_orders(created_at DESC) - used in dashboard lab orders section ordering
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_prescription_headers_patient_identifier 
  ON public.prescription_headers(patient_identifier);

CREATE INDEX IF NOT EXISTS idx_lab_orders_patient_citizen_id 
  ON public.lab_orders(patient_citizen_id);

CREATE INDEX IF NOT EXISTS idx_lab_orders_created_at 
  ON public.lab_orders(created_at DESC);
