-- Temporary diagnostic RPC to inspect dispense logs and prescription headers
CREATE OR REPLACE FUNCTION public.debug_dump_dispense_logs()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pids json;
  v_headers json;
  v_citizens json;
  v_items json;
BEGIN
  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) INTO v_pids
  FROM (SELECT * FROM public.prescription_item_dispenses ORDER BY id DESC LIMIT 10) t;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) INTO v_headers
  FROM (SELECT id, prescription_code, consultation_id, patient_identifier, citizen_id, doctor_staff_id, dispensing_status, issued_at FROM public.prescription_headers ORDER BY id DESC LIMIT 10) t;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) INTO v_items
  FROM (SELECT id, prescription_id, medicine_name, quantity, dispensed_quantity, remaining_quantity FROM public.prescription_items ORDER BY id DESC LIMIT 10) t;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json) INTO v_citizens
  FROM (SELECT id, auth_user_id, firstname, surname, email, contact_number FROM public.citizens ORDER BY id DESC LIMIT 10) t;

  RETURN json_build_object(
    'prescription_item_dispenses', v_pids,
    'prescription_headers', v_headers,
    'prescription_items', v_items,
    'citizens', v_citizens
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_dump_dispense_logs() TO anon, authenticated;
