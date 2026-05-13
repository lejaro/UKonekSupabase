-- Add availability and dispensing status to individual prescription items
ALTER TABLE public.prescription_items
ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS is_dispensed BOOLEAN DEFAULT FALSE;

-- Update the mobile API to include these new status flags
CREATE OR REPLACE FUNCTION public.get_my_medicine_schedule()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen_id bigint;
  v_result     json;
BEGIN
  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid();

  IF v_citizen_id IS NULL THEN
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
      ph.dispensed_at,
      COALESCE(NULLIF(TRIM(CONCAT_WS(' ', s.first_name, s.last_name)), ''), 'Doctor') AS doctor_name,
      pi.medicine_name,
      pi.quantity,
      COALESCE(pi.unit, '') AS unit,
      COALESCE(pi.dosage, '') AS dosage,
      COALESCE(pi.frequency, '') AS frequency,
      COALESCE(pi.duration, '') AS duration,
      COALESCE(pi.instructions, '') AS instructions,
      COALESCE(pi.additional_info, '') AS additional_info,
      COALESCE(pi.is_available, true) AS is_available,   -- Added availability flag
      COALESCE(pi.is_dispensed, false) AS is_dispensed    -- Added item-level dispense flag
    FROM public.prescription_items pi
    JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
    LEFT JOIN public.staff s ON s.id = ph.doctor_staff_id
    WHERE ph.dispensing_status != 'cancelled'
      AND (
        EXISTS (
          SELECT 1 FROM public.consultations con
          WHERE con.id = ph.consultation_id AND con.patient_citizen_id = v_citizen_id
        )
        OR ph.patient_identifier = v_citizen_id::text
      )
  ) t;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;
