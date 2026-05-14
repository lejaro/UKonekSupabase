-- ───────────────────────────────────────────────────────────────────────────
-- WIPE CLINICAL DATA (CONSULTATIONS, PRESCRIPTIONS, INTAKE LOGS)
-- ───────────────────────────────────────────────────────────────────────────

-- 1. Wipe Medicine Intake Logs
DELETE FROM public.medicine_intake_logs;

-- 2. Wipe Prescription Items
DELETE FROM public.prescription_items;

-- 3. Wipe Prescription Headers
DELETE FROM public.prescription_headers;

-- 4. Wipe Consultations
DELETE FROM public.consultations;

-- 5. Wipe Vital Signs
DELETE FROM public.vital_signs;

-- Resetting sequences
ALTER SEQUENCE IF EXISTS public.medicine_intake_logs_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS public.prescription_items_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS public.prescription_headers_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS public.consultations_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS public.vital_signs_id_seq RESTART WITH 1;

DO $$ BEGIN
  RAISE NOTICE 'All clinical data has been wiped.';
END $$;
