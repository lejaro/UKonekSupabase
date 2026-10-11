-- ==============================================================================
-- Script: supabase/refresh_operational_data.sql
-- Description: Safely refresh and reset all transactional and operational clinic data.
--
-- PRESERVED DATA (UNTOUCHED):
--   ✓ auth.users                 (All Supabase Auth login accounts)
--   ✓ public.staff               (All doctor, nurse, pharmacist & admin accounts)
--   ✓ public.citizens            (All registered citizen profiles & credentials)
--   ✓ public.medicines           (Entire medicine catalog and inventory)
--   ✓ public.doctor_schedules    (Doctor clinic shift configurations)
--   ✓ public.system_config       (Clinic parameters & daily queue quotas)
-- ==============================================================================

DO $$
DECLARE
  tbl text;
  tables_to_truncate text[] := ARRAY[
    -- Pharmacy & Dispensing
    'dispense_returns',
    'prescription_item_dispenses',
    'otc_dispense_items',
    'otc_dispenses',

    -- Prescriptions & Patient Intake
    'prescription_items',
    'prescription_headers',
    'medicine_intake_logs',

    -- Clinical Encounters
    'consultation_attachments',
    'consultations',
    'vital_signs',
    'lab_orders',

    -- Queueing & Appointments
    'queue_tickets',

    -- Auditing & Feedback & Transactions
    'feedbacks',
    'audit_log',
    'clinic_transactions',
    'staff_login_logs',

    -- Temporary Auth & Registration State
    'pending_citizen_signups'
  ];
BEGIN
  -- 1. Safely truncate each operational table only if it exists
  FOREACH tbl IN ARRAY tables_to_truncate LOOP
    IF to_regclass('public.' || quote_ident(tbl)) IS NOT NULL THEN
      EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE', tbl);
      RAISE NOTICE 'Cleared operational table: public.%', tbl;
    END IF;
  END LOOP;

  -- 2. Restore active medicines catalog & sanitize stock
  IF to_regclass('public.medicines') IS NOT NULL THEN
    UPDATE public.medicines
    SET
      archived_at = NULL,
      qty = GREATEST(qty, 0)
    WHERE archived_at IS NOT NULL OR qty < 0;
    RAISE NOTICE 'Medicines inventory preserved and verified.';
  END IF;

  -- 3. Reset staff availability status so all active staff start in fresh 'available' state
  IF to_regclass('public.staff') IS NOT NULL THEN
    UPDATE public.staff
    SET availability_status = 'available'
    WHERE status = 'active';
    RAISE NOTICE 'Staff availability status reset to available.';
  END IF;
END $$;
