-- ==============================================================================
-- Migration: 20260910160000_fix_medicine_schedule_rpc.sql
-- Description: Upgrade get_my_medicine_schedule() to support:
--              1. Robust patient citizen identification (ID, CIT- prefix, email, queue ticket).
--              2. Full prescription dispense inclusion (even if dispensed_quantity was unpopulated).
--              3. Explicit is_dispensed boolean flag in returned JSON.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_my_medicine_schedule()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen record;
  v_result json;
BEGIN
  -- Resolve citizen by auth_user_id or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
  LIMIT 1;

  IF v_citizen.id IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(row_to_json(t) ORDER BY t.issued_at DESC, t.prescription_item_id ASC)
  INTO v_result
  FROM (
    SELECT
      pi.id AS prescription_item_id,
      ph.id AS prescription_id,
      ph.prescription_code,
      ph.dispensing_status,
      ph.issued_at,
      coalesce(ph.dispensed_at, ph.issued_at) AS dispensed_at,
      coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') AS doctor_name,
      pi.medicine_name,
      coalesce(nullif(pi.dispensed_quantity, 0), pi.quantity, 1) AS quantity,
      coalesce(pi.quantity, 0) AS prescribed_quantity,
      coalesce(nullif(pi.dispensed_quantity, 0), pi.quantity, 1) AS dispensed_quantity,
      coalesce(pi.remaining_quantity, greatest(0, pi.quantity - coalesce(nullif(pi.dispensed_quantity, 0), pi.quantity, 0))) AS remaining_quantity,
      coalesce(pi.unit, '') AS unit,
      coalesce(pi.dosage, '') AS dosage,
      coalesce(pi.frequency, '') AS frequency,
      coalesce(pi.duration, '') AS duration,
      coalesce(pi.instructions, '') AS instructions,
      coalesce(pi.additional_info, '') AS additional_info,
      coalesce(pi.is_available, true) AS is_available,
      true AS is_dispensed
    FROM public.prescription_items pi
    JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
    LEFT JOIN public.staff s ON s.id = ph.doctor_staff_id
    LEFT JOIN public.consultations con ON con.id = ph.consultation_id
    WHERE (
      ph.dispensing_status IN ('partial', 'dispensed')
      OR pi.is_dispensed = true
      OR coalesce(pi.dispensed_quantity, 0) > 0
    )
    AND (
      con.patient_citizen_id = v_citizen.id
      OR ph.patient_identifier = v_citizen.id::text
      OR ph.patient_identifier ILIKE ('CIT-' || v_citizen.id::text)
      OR (
        ph.patient_identifier ~ '^\D*\d+\D*$' 
        AND regexp_replace(ph.patient_identifier, '\D', '', 'g') = v_citizen.id::text
      )
      OR EXISTS (
        SELECT 1 FROM public.queue_tickets qt
        WHERE qt.citizen_id = v_citizen.id
          AND (
            qt.ticket_code = ph.patient_identifier
            OR ('QUEUE-' || qt.id::text) = ph.patient_identifier
            OR qt.id::text = ph.patient_identifier
          )
      )
      OR (v_citizen.firstname IS NOT NULL AND length(trim(v_citizen.firstname)) > 1 AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.firstname) || '%'))
      OR (v_citizen.surname IS NOT NULL AND length(trim(v_citizen.surname)) > 1 AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.surname) || '%'))
    )
  ) t;

  RETURN coalesce(v_result, '[]'::json);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_medicine_schedule() FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_medicine_schedule() TO authenticated;
