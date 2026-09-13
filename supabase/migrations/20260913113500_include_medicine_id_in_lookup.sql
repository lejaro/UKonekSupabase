-- Migration: 20260913113500_include_medicine_id_in_lookup.sql
-- Description: Include medicine_id in lookup_prescription_by_code items

CREATE OR REPLACE FUNCTION public.lookup_prescription_by_code(p_code text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id bigint;
  v_role text;
  v_header record;
  v_items json;
  v_doctor text;
BEGIN
  SELECT s.id, lower(trim(coalesce(s.role, '')))
  INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = auth.uid()
    AND lower(trim(coalesce(s.status, ''))) = 'active'
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  IF v_role <> 'pharmacist' THEN
    RETURN json_build_object('error', 'Forbidden');
  END IF;

  SELECT ph.*
  INTO v_header
  FROM public.prescription_headers ph
  WHERE trim(upper(ph.prescription_code)) = trim(upper(coalesce(p_code, '')))
  LIMIT 1;

  IF v_header.id IS NULL THEN
    RETURN json_build_object('error', 'Prescription not found');
  END IF;

  SELECT trim(concat_ws(' ', s.first_name, s.last_name))
  INTO v_doctor
  FROM public.staff s
  WHERE s.id = v_header.doctor_staff_id
  LIMIT 1;

  SELECT json_agg(json_build_object(
    'id',                 pi.id,
    'medicine_id',        pi.medicine_id,
    'medicine_name',      pi.medicine_name,
    'quantity',           pi.quantity,
    'dispensed_quantity', coalesce(pi.dispensed_quantity, 0),
    'remaining_quantity', coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)),
    'is_dispensed',       coalesce(pi.is_dispensed, false),
    'last_dispensed_at',  pi.last_dispensed_at,
    'unit',               pi.unit,
    'dosage',             pi.dosage,
    'frequency',          pi.frequency,
    'instructions',       pi.instructions
  ) ORDER BY pi.id)
  INTO v_items
  FROM public.prescription_items pi
  WHERE pi.prescription_id = v_header.id;

  RETURN json_build_object(
    'id',                   v_header.id,
    'prescription_code',    v_header.prescription_code,
    'patient_identifier',   v_header.patient_identifier,
    'doctor_name',          coalesce(nullif(v_doctor, ''), 'Unknown'),
    'issued_at',            v_header.issued_at,
    'dispensing_status',    v_header.dispensing_status,
    'dispensed_at',         v_header.dispensed_at,
    'first_dispensed_at',   v_header.first_dispensed_at,
    'last_dispensed_at',    v_header.last_dispensed_at,
    'items',                coalesce(v_items, '[]'::json)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.lookup_prescription_by_code(text) TO authenticated;
