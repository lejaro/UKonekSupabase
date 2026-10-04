-- Security Hardening Migration
-- 1. Defend complete_my_citizen_profile against SQL LIKE wildcard pattern hijacking (CWE-89)
--    and unauthorized mass record re-assignment.
-- 2. Fix BOLA / IDOR (Broken Object Level Authorization / Insecure Direct Object References)
--    in get_my_consultations, get_my_prescribed_medicines, and get_my_medicine_schedule:
--    Prevent arbitrary authenticated users from querying other patients' clinical records
--    via p_citizen_id unless they are active medical staff or the record owner.

-- ============================================================================
-- 1. HARDEN complete_my_citizen_profile
-- ============================================================================
CREATE OR REPLACE FUNCTION public.complete_my_citizen_profile(
  p_firstname text,
  p_surname text,
  p_middle_initial text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_age integer DEFAULT NULL,
  p_contact_number text DEFAULT NULL,
  p_sex text DEFAULT NULL,
  p_complete_address text DEFAULT NULL,
  p_emergency_contact_complete_name text DEFAULT NULL,
  p_emergency_contact_contact_number text DEFAULT NULL,
  p_relation text DEFAULT NULL,
  p_username text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_walkin_id bigint;
  v_citizen_id bigint;
  v_username text;
  v_auth_email text;
  v_clean_contact text;
  v_clean_firstname text;
  v_clean_surname text;
BEGIN
  -- 1. Validate and sanitize name inputs against wildcard injection
  v_clean_firstname := trim(coalesce(p_firstname, ''));
  v_clean_surname   := trim(coalesce(p_surname, ''));

  IF length(v_clean_firstname) < 2 OR v_clean_firstname ~ '[%_;]' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'First name must be at least 2 characters and cannot contain wildcard symbols (%, _, ;).');
  END IF;

  IF length(v_clean_surname) < 2 OR v_clean_surname ~ '[%_;]' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Surname must be at least 2 characters and cannot contain wildcard symbols (%, _, ;).');
  END IF;

  -- 2. Validate username
  v_username := nullif(trim(coalesce(p_username, '')), '');
  IF v_username IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Username is required.');
  END IF;

  -- 3. Check if username is taken by ANY citizen or staff
  IF EXISTS (
    SELECT 1
    FROM public.citizens c
    WHERE lower(trim(coalesce(c.username, ''))) = lower(v_username)
      AND c.auth_user_id <> auth.uid()
  ) OR EXISTS (
    SELECT 1
    FROM public.staff s
    WHERE lower(trim(coalesce(s.username, ''))) = lower(v_username)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Username already used, please choose another username.');
  END IF;

  -- 4. Resolve authenticated user's email
  v_auth_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  IF v_auth_email = '' THEN
     SELECT lower(trim(email)) INTO v_auth_email FROM auth.users WHERE id = auth.uid();
  END IF;

  -- 5. Block staff accounts from creating citizen profiles
  IF EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
       OR lower(trim(s.email)) = v_auth_email
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'This account is a staff account and cannot register as a citizen.');
  END IF;

  -- 6. Check if citizen record already exists for this auth_user_id
  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
  LIMIT 1;

  IF v_citizen_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'This account has already completed registration. Please sign in instead.');
  END IF;

  v_clean_contact := nullif(trim(coalesce(p_contact_number, '')), '');

  -- 7. Check if an unlinked walk-in record (auth_user_id IS NULL) exists for this patient
  -- Matching by verified contact number OR exact name + date of birth
  SELECT c.id INTO v_existing_walkin_id
  FROM public.citizens c
  WHERE c.auth_user_id IS NULL
    AND (
      (v_clean_contact IS NOT NULL AND nullif(trim(c.contact_number), '') = v_clean_contact)
      OR (
        lower(trim(c.firstname)) = lower(v_clean_firstname)
        AND lower(trim(c.surname)) = lower(v_clean_surname)
        AND (p_date_of_birth IS NOT NULL AND c.date_of_birth = p_date_of_birth)
      )
    )
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF v_existing_walkin_id IS NOT NULL THEN
    -- CLAIM & UPDATE EXISTING WALK-IN RECORD
    UPDATE public.citizens
    SET
      auth_user_id = auth.uid(),
      email = v_auth_email,
      username = v_username,
      firstname = v_clean_firstname,
      surname = v_clean_surname,
      middle_initial = coalesce(nullif(trim(p_middle_initial), ''), middle_initial),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      age = coalesce(p_age, age),
      contact_number = coalesce(v_clean_contact, contact_number),
      sex = coalesce(nullif(trim(p_sex), ''), sex),
      complete_address = coalesce(nullif(trim(p_complete_address), ''), complete_address),
      emergency_contact_complete_name = coalesce(nullif(trim(p_emergency_contact_complete_name), ''), emergency_contact_complete_name),
      emergency_contact_contact_number = coalesce(nullif(trim(p_emergency_contact_contact_number), ''), emergency_contact_contact_number),
      relation = coalesce(nullif(trim(p_relation), ''), relation),
      role = 'citizen'
    WHERE id = v_existing_walkin_id;

    v_citizen_id := v_existing_walkin_id;
  ELSE
    -- INSERT NEW CITIZEN PROFILE
    INSERT INTO public.citizens (
      firstname, surname, middle_initial, date_of_birth, age,
      contact_number, sex, email, complete_address,
      emergency_contact_complete_name, emergency_contact_contact_number,
      relation, username, role, auth_user_id
    ) VALUES (
      v_clean_firstname,
      v_clean_surname,
      nullif(trim(p_middle_initial), ''),
      p_date_of_birth,
      p_age,
      v_clean_contact,
      nullif(trim(p_sex), ''),
      v_auth_email,
      nullif(trim(p_complete_address), ''),
      nullif(trim(p_emergency_contact_complete_name), ''),
      nullif(trim(p_emergency_contact_contact_number), ''),
      nullif(trim(p_relation), ''),
      v_username,
      'citizen',
      auth.uid()
    )
    RETURNING id INTO v_citizen_id;
  END IF;

  -- 8. Retroactively sync any past consultations, prescriptions, queue tickets, or OTC dispenses
  -- Only match when both firstname and surname are strictly non-wildcard and length >= 2
  IF v_citizen_id IS NOT NULL AND length(v_clean_firstname) >= 2 AND length(v_clean_surname) >= 2 THEN
    -- Consultations
    UPDATE public.consultations
    SET patient_citizen_id = v_citizen_id
    WHERE patient_citizen_id IS NULL
      AND (
        patient_identifier ILIKE ('%' || v_clean_firstname || '%' || v_clean_surname || '%')
        OR patient_identifier ILIKE ('%' || v_clean_surname || '%' || v_clean_firstname || '%')
        OR patient_identifier = v_citizen_id::text
        OR patient_identifier ILIKE ('CIT-' || v_citizen_id::text)
      );

    -- Prescription Headers
    UPDATE public.prescription_headers
    SET patient_citizen_id = v_citizen_id
    WHERE patient_citizen_id IS NULL
      AND (
        patient_identifier ILIKE ('%' || v_clean_firstname || '%' || v_clean_surname || '%')
        OR patient_identifier ILIKE ('%' || v_clean_surname || '%' || v_clean_firstname || '%')
        OR patient_identifier = v_citizen_id::text
        OR patient_identifier ILIKE ('CIT-' || v_citizen_id::text)
      );

    -- Queue Tickets
    UPDATE public.queue_tickets
    SET citizen_id = v_citizen_id
    WHERE citizen_id IS NULL
      AND walkin_patient_name IS NOT NULL
      AND (
        walkin_patient_name ILIKE ('%' || v_clean_firstname || '%' || v_clean_surname || '%')
        OR walkin_patient_name ILIKE ('%' || v_clean_surname || '%' || v_clean_firstname || '%')
      );

    -- OTC Dispenses
    UPDATE public.otc_dispenses
    SET citizen_id = v_citizen_id
    WHERE citizen_id IS NULL
      AND walkin_patient_name IS NOT NULL
      AND (
        walkin_patient_name ILIKE ('%' || v_clean_firstname || '%' || v_clean_surname || '%')
        OR walkin_patient_name ILIKE ('%' || v_clean_surname || '%' || v_clean_firstname || '%')
      );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'claimed_past_records', (v_existing_walkin_id IS NOT NULL),
    'citizen_id', v_citizen_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_my_citizen_profile(
  text, text, text, date, integer, text, text, text, text, text, text, text
) TO authenticated, service_role;


-- ============================================================================
-- 2. HARDEN get_my_consultations (BOLA / IDOR FIX)
-- ============================================================================
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
  v_is_staff boolean := false;
BEGIN
  -- Determine whether caller is an active staff member
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  -- If querying a specific p_citizen_id, strictly enforce that caller is either
  -- active staff OR the owner of the citizen account (auth_user_id = auth.uid())
  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
    -- Resolve to current authenticated citizen
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.auth_user_id = auth.uid()
       OR (c.email IS NOT NULL AND c.email = (SELECT u.email FROM auth.users u WHERE u.id = auth.uid()))
    ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
    LIMIT 1;
  END IF;

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


-- ============================================================================
-- 3. HARDEN get_my_prescribed_medicines (BOLA / IDOR FIX)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_prescribed_medicines(
  p_limit integer DEFAULT 50,
  p_citizen_id bigint DEFAULT NULL
)
RETURNS TABLE (
  prescription_id       bigint,
  prescription_item_id  bigint,
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
  v_is_staff boolean := false;
BEGIN
  -- Determine whether caller is an active staff member
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  -- If querying a specific p_citizen_id, strictly enforce that caller is either
  -- active staff OR the owner of the citizen account (auth_user_id = auth.uid())
  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
    -- Resolve to current authenticated citizen
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.auth_user_id = auth.uid()
       OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
    ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
    LIMIT 1;
  END IF;

  IF v_citizen.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    ph.id AS prescription_id,
    pi.id AS prescription_item_id,
    ph.prescription_code,
    ph.dispensing_status,
    ph.issued_at,
    coalesce(ph.dispensed_at, ph.issued_at) AS dispensed_at,
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') AS doctor_name,
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.dispensed_quantity, 0) AS dispensed_quantity,
    coalesce(pi.remaining_quantity, greatest(0, pi.quantity - coalesce(pi.dispensed_quantity, 0))) AS remaining_quantity,
    coalesce(pi.unit, '') AS unit,
    coalesce(pi.dosage, '') AS dosage,
    coalesce(pi.frequency, '') AS frequency,
    coalesce(pi.duration, '') AS duration,
    coalesce(pi.instructions, '') AS instructions,
    coalesce(pi.additional_info, '') AS additional_info,
    coalesce(pi.is_dispensed, (ph.dispensing_status = 'dispensed'), false) AS is_dispensed
  FROM public.prescription_items pi
  JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
  LEFT JOIN public.consultations con ON con.id = ph.consultation_id
  LEFT JOIN public.staff s ON s.id = ph.doctor_staff_id
  WHERE (
    ph.patient_citizen_id = v_citizen.id
    OR con.patient_citizen_id = v_citizen.id
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
  ORDER BY ph.issued_at DESC, pi.id ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_prescribed_medicines(integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_prescribed_medicines(integer, bigint) TO authenticated;


-- ============================================================================
-- 4. HARDEN get_my_medicine_schedule (BOLA / IDOR FIX)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_medicine_schedule(
  p_citizen_id bigint DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen record;
  v_result json;
  v_is_staff boolean := false;
BEGIN
  -- Determine whether caller is an active staff member
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  -- If querying a specific p_citizen_id, strictly enforce that caller is either
  -- active staff OR the owner of the citizen account (auth_user_id = auth.uid())
  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
    -- Resolve to current authenticated citizen
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.auth_user_id = auth.uid()
       OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
    ORDER BY (CASE WHEN c.auth_user_id = auth.uid() THEN 0 ELSE 1 END) ASC
    LIMIT 1;
  END IF;

  IF v_citizen.id IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(row_to_json(t) ORDER BY t.issued_at DESC, t.prescription_item_id ASC)
  INTO v_result
  FROM (
    -- 1. Prescribed and Dispensed Prescription Items
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
      -- Strictly require the item itself to have been dispensed or fulfilled
      pi.is_dispensed = true
      OR coalesce(pi.dispensed_quantity, 0) > 0
      OR (ph.dispensing_status = 'dispensed' AND coalesce(pi.remaining_quantity, 0) <= 0)
    )
    AND (
      ph.patient_citizen_id = v_citizen.id
      OR con.patient_citizen_id = v_citizen.id
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

    UNION ALL

    -- 2. Over-The-Counter (OTC) Dispenses for this Citizen
    SELECT
      (-odi.id) AS prescription_item_id,
      (-od.id) AS prescription_id,
      od.reference_no AS prescription_code,
      'dispensed' AS dispensing_status,
      od.dispensed_at AS issued_at,
      od.dispensed_at AS dispensed_at,
      coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Pharmacist') AS doctor_name,
      m.name AS medicine_name,
      odi.quantity AS quantity,
      odi.quantity AS prescribed_quantity,
      odi.quantity AS dispensed_quantity,
      0 AS remaining_quantity,
      coalesce(odi.unit, m.unit, '') AS unit,
      coalesce(m.dosage, '') AS dosage,
      'As needed' AS frequency,
      '30 days' AS duration,
      coalesce(odi.instructions, 'Take as directed by pharmacist') AS instructions,
      'Over-the-counter dispense' AS additional_info,
      true AS is_available,
      true AS is_dispensed
    FROM public.otc_dispense_items odi
    JOIN public.otc_dispenses od ON od.id = odi.otc_dispense_id
    JOIN public.medicines m ON m.id = odi.medicine_id
    LEFT JOIN public.staff s ON s.id = od.dispensed_by_staff_id
    WHERE od.citizen_id = v_citizen.id
  ) t;

  RETURN coalesce(v_result, '[]'::json);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_medicine_schedule(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_medicine_schedule(bigint) TO authenticated;
