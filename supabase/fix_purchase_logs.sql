-- ==============================================================================
-- Comprehensive Fix: supabase/fix_purchase_logs.sql
-- Run this in Supabase SQL Editor to make Purchase Logs 100% resilient
-- ==============================================================================

-- 1. Drop existing conflicting signatures
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs();
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(bigint, integer);
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(integer, bigint);

-- 2. Resilient get_my_prescription_dispense_logs RPC
CREATE OR REPLACE FUNCTION public.get_my_prescription_dispense_logs(
  p_limit integer DEFAULT 50,
  p_prescription_id bigint DEFAULT NULL
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
  -- 1. Resolve citizen by auth_user_id or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
  LIMIT 1;

  IF v_citizen.id IS NULL THEN
    RETURN;
  END IF;

  -- Ensure citizen auth_user_id is linked
  IF v_citizen.auth_user_id IS NULL AND auth.uid() IS NOT NULL THEN
    UPDATE public.citizens SET auth_user_id = auth.uid() WHERE id = v_citizen.id;
  END IF;

  RETURN QUERY
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
    -- Direct consultation patient link
    con.patient_citizen_id = v_citizen.id

    -- Direct patient identifier link
    OR ph.patient_identifier = v_citizen.id::text
    OR ph.patient_identifier ILIKE ('CIT-' || v_citizen.id::text)
    OR (
      ph.patient_identifier ~ '^\D*\d+\D*$' 
      AND regexp_replace(ph.patient_identifier, '\D', '', 'g') = v_citizen.id::text
    )

    -- Queue Ticket reference (e.g. Q-20260902-MC-001 or QUEUE-...)
    OR EXISTS (
      SELECT 1 FROM public.queue_tickets qt
      WHERE qt.citizen_id = v_citizen.id
        AND (
          qt.ticket_code = ph.patient_identifier
          OR ('QUEUE-' || qt.id::text) = ph.patient_identifier
          OR qt.id::text = ph.patient_identifier
        )
    )

    -- Consultation patient_identifier reference
    OR (con.patient_identifier IS NOT NULL AND (
      con.patient_identifier = v_citizen.id::text
      OR con.patient_identifier ILIKE ('CIT-' || v_citizen.id::text)
      OR (v_citizen.firstname IS NOT NULL AND length(trim(v_citizen.firstname)) > 1 AND con.patient_identifier ILIKE ('%' || trim(v_citizen.firstname) || '%'))
      OR (v_citizen.surname IS NOT NULL AND length(trim(v_citizen.surname)) > 1 AND con.patient_identifier ILIKE ('%' || trim(v_citizen.surname) || '%'))
    ))

    -- Name-based reference
    OR (
      v_citizen.firstname IS NOT NULL 
      AND length(trim(v_citizen.firstname)) > 1 
      AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.firstname) || '%')
    )
    OR (
      v_citizen.surname IS NOT NULL 
      AND length(trim(v_citizen.surname)) > 1 
      AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.surname) || '%')
    )

    -- Email reference
    OR (
      v_citizen.email IS NOT NULL 
      AND length(trim(v_citizen.email)) > 3 
      AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.email) || '%')
    )
  )
  AND (p_prescription_id IS NULL OR ph.id = p_prescription_id)
  ORDER BY pid.dispensed_at DESC
  LIMIT v_limit;
END;
$$;

-- 3. Zero-argument overload for backwards compatibility
CREATE OR REPLACE FUNCTION public.get_my_prescription_dispense_logs()
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
  SELECT * FROM public.get_my_prescription_dispense_logs(50, NULL);
$$;

GRANT EXECUTE ON FUNCTION public.get_my_prescription_dispense_logs(integer, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_prescription_dispense_logs() TO authenticated;


-- 4. Upgrade get_my_prescribed_medicines with same matching rules
CREATE OR REPLACE FUNCTION public.get_my_prescribed_medicines(
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id                    bigint,
  prescription_code     text,
  dispensing_status     text,
  issued_at             timestamptz,
  dispensed_at          timestamptz,
  doctor_name           text,
  medicine_name         text,
  quantity              integer,
  dispensed_quantity    integer,
  remaining_quantity    integer,
  unit                  text,
  dosage                text,
  frequency             text,
  duration              text,
  instructions          text,
  additional_info       text,
  is_dispensed          boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen record;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
BEGIN
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
  SELECT
    ph.id,
    ph.prescription_code,
    ph.dispensing_status,
    ph.issued_at,
    ph.dispensed_at,
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') AS doctor_name,
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.dispensed_quantity, 0) AS dispensed_quantity,
    coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) AS remaining_quantity,
    coalesce(pi.unit, '') AS unit,
    coalesce(pi.dosage, '') AS dosage,
    coalesce(pi.frequency, '') AS frequency,
    coalesce(pi.duration, '') AS duration,
    coalesce(pi.instructions, '') AS instructions,
    coalesce(pi.additional_info, '') AS additional_info,
    coalesce(pi.is_dispensed, false) AS is_dispensed
  FROM public.prescription_items pi
  JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
  LEFT JOIN public.consultations con ON con.id = ph.consultation_id
  LEFT JOIN public.staff s ON s.id = ph.doctor_staff_id
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
    OR (
      v_citizen.firstname IS NOT NULL 
      AND length(trim(v_citizen.firstname)) > 1 
      AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.firstname) || '%')
    )
    OR (
      v_citizen.surname IS NOT NULL 
      AND length(trim(v_citizen.surname)) > 1 
      AND ph.patient_identifier ILIKE ('%' || trim(v_citizen.surname) || '%')
    )
  )
  ORDER BY ph.issued_at DESC, pi.id ASC
  LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_prescribed_medicines(integer) TO authenticated;


-- 5. Diagnostic RPC to verify dispense records and patient linkage
CREATE OR REPLACE FUNCTION public.get_dispense_debug_summary()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dispense_count integer;
  v_header_count integer;
  v_item_count integer;
  v_recent_dispenses json;
  v_recent_headers json;
BEGIN
  SELECT count(*) INTO v_dispense_count FROM public.prescription_item_dispenses;
  SELECT count(*) INTO v_header_count FROM public.prescription_headers;
  SELECT count(*) INTO v_item_count FROM public.prescription_items;

  SELECT coalesce(json_agg(row_to_json(d)), '[]'::json) INTO v_recent_dispenses
  FROM (
    SELECT id, prescription_id, prescription_item_id, dispensed_quantity, dispensed_at
    FROM public.prescription_item_dispenses
    ORDER BY id DESC LIMIT 5
  ) d;

  SELECT coalesce(json_agg(row_to_json(h)), '[]'::json) INTO v_recent_headers
  FROM (
    SELECT id, prescription_code, patient_identifier, consultation_id, dispensing_status, issued_at
    FROM public.prescription_headers
    ORDER BY id DESC LIMIT 5
  ) h;

  RETURN json_build_object(
    'total_dispenses', v_dispense_count,
    'total_headers', v_header_count,
    'total_items', v_item_count,
    'recent_dispenses', v_recent_dispenses,
    'recent_headers', v_recent_headers
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dispense_debug_summary() TO anon, authenticated;
