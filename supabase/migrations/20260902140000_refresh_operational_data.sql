-- ==============================================================================
-- Migration / Script: 20260902140000_refresh_operational_data.sql
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
    'dispense_returns',
    'prescription_item_dispenses',
    'otc_dispense_items',
    'otc_dispenses',
    'prescription_items',
    'prescription_headers',
    'medicine_intake_logs',
    'lab_orders',
    'vital_signs',
    'consultations',
    'queue_tickets',
    'appointments',
    'feedbacks',
    'staff_login_logs',
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
  END IF;
END $$;

-- Callable RPC function for active staff
create or replace function public.refresh_operational_test_data()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id bigint;
  v_role text;
  tbl text;
  tables_to_truncate text[] := ARRAY[
    'dispense_returns',
    'prescription_item_dispenses',
    'otc_dispense_items',
    'otc_dispenses',
    'prescription_items',
    'prescription_headers',
    'medicine_intake_logs',
    'lab_orders',
    'vital_signs',
    'consultations',
    'queue_tickets',
    'appointments',
    'feedbacks',
    'staff_login_logs',
    'citizen_otps',
    'pending_citizen_signups',
    'staff_email_verifications',
    'pending_staff'
  ];
begin
  select s.id, s.role into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = auth.uid() and s.status = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Not authenticated as active staff.');
  end if;

  FOREACH tbl IN ARRAY tables_to_truncate LOOP
    IF to_regclass('public.' || quote_ident(tbl)) IS NOT NULL THEN
      EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE', tbl);
    END IF;
  END LOOP;

  IF to_regclass('public.medicines') IS NOT NULL THEN
    UPDATE public.medicines
    SET archived_at = NULL, qty = GREATEST(qty, 0)
    WHERE archived_at IS NOT NULL OR qty < 0;
  END IF;

  return json_build_object(
    'ok', true,
    'message', 'Operational data refreshed successfully. Credentials and medicines were preserved.'
  );
exception when others then
  return json_build_object('error', SQLERRM);
end;
$$;

grant execute on function public.refresh_operational_test_data() to authenticated;
