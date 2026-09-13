-- ==============================================================================
-- Migration: 20260913130000_reset_operational_data_preserve_users_and_inventory.sql
-- Description: Safely clear all operational, transactional, clinical, queue,
--              prescription, and audit records from the remote database while
--              strictly preserving:
--                ✓ auth.users                 (All Supabase Auth login accounts)
--                ✓ public.staff               (Doctors, nurses, pharmacists, admins)
--                ✓ public.citizens            (Registered citizen/patient profiles)
--                ✓ public.doctor_schedules    (Doctor shift assignments)
--                ✓ public.medicines           (Medicine catalog & stock quantities)
--                ✓ public.medicine_restock_logs (Inventory restock history)
--                ✓ public.system_config       (Clinic parameters & queue quotas)
--                ✓ public.announcements       (Public notices & advisories)
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
    'appointments',

    -- Auditing & Feedback
    'feedbacks',
    'audit_log',
    'clinic_transactions',
    'staff_login_logs',

    -- Temporary Auth & Registration State
    'citizen_otps',
    'pending_citizen_signups',
    'staff_email_verifications',
    'pending_staff'
  ];
BEGIN
  -- 1. Safely truncate each operational table only if it exists
  FOREACH tbl IN ARRAY tables_to_truncate LOOP
    IF to_regclass('public.' || quote_ident(tbl)) IS NOT NULL THEN
      EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE', tbl);
      RAISE NOTICE 'Truncated operational table: public.%', tbl;
    END IF;
  END LOOP;

  -- 2. Restore active medicines catalog & ensure clean inventory stock
  IF to_regclass('public.medicines') IS NOT NULL THEN
    UPDATE public.medicines
    SET
      archived_at = NULL,
      qty = GREATEST(qty, 0)
    WHERE archived_at IS NOT NULL OR qty < 0;
    RAISE NOTICE 'Sanitized public.medicines stock and unarchived active inventory.';
  END IF;

  -- 3. Reset staff availability status so all active staff start in fresh 'available' state
  IF to_regclass('public.staff') IS NOT NULL THEN
    UPDATE public.staff
    SET availability_status = 'available'
    WHERE status = 'active';
    RAISE NOTICE 'Reset active staff availability_status to available.';
  END IF;
END $$;
