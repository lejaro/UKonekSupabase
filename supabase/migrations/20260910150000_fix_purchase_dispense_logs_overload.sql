-- ==============================================================================
-- Migration: 20260910150000_fix_purchase_dispense_logs_overload.sql
-- Description: Fix PGRST203 (ambiguous overloaded function) error on
--              get_my_prescription_dispense_logs that caused the mobile app
--              to return 0 purchase logs even when prescriptions were dispensed.
--              Also adds fallback synthesis for prescriptions dispensed as a whole.
-- ==============================================================================

-- 1. Drop ALL conflicting overloaded signatures
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(bigint, integer) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(integer, bigint) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(bigint) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(integer) CASCADE;

DROP FUNCTION IF EXISTS public.get_my_dispense_history() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_dispense_history(bigint, integer) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_dispense_history(integer, bigint) CASCADE;

-- 2. Create single canonical function with robust matching and fallback synthesis
CREATE OR REPLACE FUNCTION public.get_my_prescription_dispense_logs(
  p_prescription_id bigint DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  dispense_id           bigint,
  prescription_id       bigint,
  prescription_code     text,
  prescription_item_id  bigint,
  medicine_name         text,
  dosage                text,
  dispensed_quantity    integer,
  unit                  text,
  note                  text,
  pharmacist_name       text,
  dispensed_at          timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen record;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
BEGIN
  -- Resolve citizen by auth_user_id or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
  LIMIT 1;

  IF v_citizen.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH logged_dispenses AS (
    SELECT
      pid.id AS dispense_id,
      ph.id AS prescription_id,
      ph.prescription_code,
      pi.id AS prescription_item_id,
      coalesce(m.name, pi.medicine_name) AS medicine_name,
      coalesce(pi.dosage, '') AS dosage,
      pid.dispensed_quantity,
      coalesce(pid.unit, pi.unit, '') AS unit,
      coalesce(pid.note, '') AS note,
      coalesce(
        nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
        'Pharmacist'
      ) AS pharmacist_name,
      pid.dispensed_at
    FROM public.prescription_item_dispenses pid
    JOIN public.prescription_headers ph ON ph.id = pid.prescription_id
    JOIN public.prescription_items pi ON pi.id = pid.prescription_item_id
    LEFT JOIN public.medicines m ON m.id = pid.medicine_id
    LEFT JOIN public.staff s ON s.id = pid.dispensed_by_staff_id
    LEFT JOIN public.consultations con ON con.id = ph.consultation_id
    WHERE (
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
    AND (p_prescription_id IS NULL OR ph.id = p_prescription_id)
  ),
  synthesized_dispenses AS (
    -- For prescriptions marked dispensed or partial where no rows were logged into prescription_item_dispenses
    SELECT
      (ph.id * 10000 + pi.id) AS dispense_id,
      ph.id AS prescription_id,
      ph.prescription_code,
      pi.id AS prescription_item_id,
      pi.medicine_name,
      coalesce(pi.dosage, '') AS dosage,
      coalesce(nullif(pi.dispensed_quantity, 0), pi.quantity, 1) AS dispensed_quantity,
      coalesce(pi.unit, '') AS unit,
      coalesce(nullif(trim(pi.instructions), ''), 'Fulfilled by Pharmacy') AS note,
      coalesce(
        nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
        'Pharmacist'
      ) AS pharmacist_name,
      coalesce(ph.dispensed_at, ph.issued_at) AS dispensed_at
    FROM public.prescription_items pi
    JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
    LEFT JOIN public.staff s ON s.id = ph.dispensed_by_staff_id
    LEFT JOIN public.consultations con ON con.id = ph.consultation_id
    WHERE ph.dispensing_status IN ('dispensed', 'partial')
      AND (pi.is_dispensed = true OR pi.dispensed_quantity > 0 OR ph.dispensing_status = 'dispensed')
      AND NOT EXISTS (
        SELECT 1 FROM public.prescription_item_dispenses pid_check
        WHERE pid_check.prescription_id = ph.id
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
      AND (p_prescription_id IS NULL OR ph.id = p_prescription_id)
  )
  SELECT * FROM logged_dispenses
  UNION ALL
  SELECT * FROM synthesized_dispenses
  ORDER BY dispensed_at DESC
  LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_prescription_dispense_logs(bigint, integer) TO authenticated;

-- 3. Alias function get_my_dispense_history for guaranteed unambiguous access
CREATE OR REPLACE FUNCTION public.get_my_dispense_history(
  p_prescription_id bigint DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  dispense_id           bigint,
  prescription_id       bigint,
  prescription_code     text,
  prescription_item_id  bigint,
  medicine_name         text,
  dosage                text,
  dispensed_quantity    integer,
  unit                  text,
  note                  text,
  pharmacist_name       text,
  dispensed_at          timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.get_my_prescription_dispense_logs(p_prescription_id, p_limit);
$$;

GRANT EXECUTE ON FUNCTION public.get_my_dispense_history(bigint, integer) TO authenticated;
