-- Fix ambiguous column reference in get_my_consultations RPC
CREATE OR REPLACE FUNCTION public.get_my_consultations(
  p_limit integer DEFAULT 50,
  p_citizen_id bigint DEFAULT NULL
)
RETURNS TABLE (
  id bigint,
  patient_identifier text,
  patient_citizen_id bigint,
  doctor_staff_id bigint,
  doctor_name text,
  symptoms text,
  diagnosis text,
  notes text,
  hpi text,
  pmh text,
  allergies text,
  immunization_status text,
  social_history text,
  physical_exam jsonb,
  differential_diagnosis text,
  lab_orders text,
  follow_up_date date,
  consulted_at timestamptz,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_citizen record;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
BEGIN
  -- Resolve citizen by explicit ID, auth_user_id, or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE (p_citizen_id IS NOT NULL AND c.id = p_citizen_id)
     OR c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT u.email FROM auth.users u WHERE u.id = auth.uid()))
  ORDER BY
    (CASE WHEN p_citizen_id IS NOT NULL AND c.id = p_citizen_id THEN 0
          WHEN c.auth_user_id = auth.uid() THEN 1
          ELSE 2 END) ASC
  LIMIT 1;

  IF v_citizen.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.patient_identifier,
    c.patient_citizen_id,
    c.doctor_staff_id,
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') AS doctor_name,
    c.symptoms,
    c.diagnosis,
    c.notes,
    c.hpi,
    c.pmh,
    c.allergies,
    c.immunization_status,
    c.social_history,
    c.physical_exam,
    c.differential_diagnosis,
    c.lab_orders,
    c.follow_up_date,
    c.consulted_at,
    c.created_at
  FROM public.consultations c
  LEFT JOIN public.staff s ON s.id = c.doctor_staff_id
  WHERE (
    c.patient_citizen_id = v_citizen.id
    OR c.patient_identifier = v_citizen.id::text
    OR c.patient_identifier ILIKE ('CIT-' || v_citizen.id::text)
    OR (
      c.patient_identifier ~ '^\D*\d+\D*$'
      AND regexp_replace(c.patient_identifier, '\D', '', 'g') = v_citizen.id::text
    )
    OR EXISTS (
      SELECT 1 FROM public.queue_tickets qt
      WHERE qt.citizen_id = v_citizen.id
        AND (
          qt.ticket_code = c.patient_identifier
          OR ('QUEUE-' || qt.id::text) = c.patient_identifier
          OR qt.id::text = c.patient_identifier
        )
    )
    OR (v_citizen.firstname IS NOT NULL AND length(trim(v_citizen.firstname)) > 1 AND c.patient_identifier ILIKE ('%' || trim(v_citizen.firstname) || '%'))
    OR (v_citizen.surname IS NOT NULL AND length(trim(v_citizen.surname)) > 1 AND c.patient_identifier ILIKE ('%' || trim(v_citizen.surname) || '%'))
  )
  ORDER BY c.consulted_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_consultations(integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_consultations(integer, bigint) TO authenticated;
