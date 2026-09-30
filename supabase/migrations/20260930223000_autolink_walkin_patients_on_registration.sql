-- Upgrade complete_my_citizen_profile to automatically claim and link
-- past walk-in records (triage vitals, consultations, prescriptions, queue tickets, and OTC dispenses)
-- when an unregistered walk-in patient completes mobile or web registration.

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
BEGIN
  -- 1. Validate username
  v_username := nullif(trim(coalesce(p_username, '')), '');
  IF v_username IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Username is required.');
  END IF;

  -- 2. Check if username is taken by ANY citizen or staff
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

  -- 3. Resolve authenticated user's email
  v_auth_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  IF v_auth_email = '' THEN
     SELECT lower(trim(email)) INTO v_auth_email FROM auth.users WHERE id = auth.uid();
  END IF;

  -- 4. Block staff accounts from creating citizen profiles
  IF EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
       OR lower(trim(s.email)) = v_auth_email
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'This account is a staff account and cannot register as a citizen.');
  END IF;

  -- 5. Check if citizen record already exists for this auth_user_id
  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
  LIMIT 1;

  IF v_citizen_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'This account has already completed registration. Please sign in instead.');
  END IF;

  v_clean_contact := nullif(trim(coalesce(p_contact_number, '')), '');

  -- 6. Check if an unlinked walk-in record (auth_user_id IS NULL) exists for this patient
  -- Matching by verified contact number OR exact name + date of birth
  SELECT c.id INTO v_existing_walkin_id
  FROM public.citizens c
  WHERE c.auth_user_id IS NULL
    AND (
      (v_clean_contact IS NOT NULL AND nullif(trim(c.contact_number), '') = v_clean_contact)
      OR (
        lower(trim(c.firstname)) = lower(trim(p_firstname))
        AND lower(trim(c.surname)) = lower(trim(p_surname))
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
      firstname = coalesce(nullif(trim(p_firstname), ''), firstname),
      surname = coalesce(nullif(trim(p_surname), ''), surname),
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
      trim(p_firstname),
      trim(p_surname),
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

  -- 7. Retroactively sync any past consultations, prescriptions, queue tickets, or OTC dispenses
  -- that were recorded under the walk-in name but had patient_citizen_id as NULL
  IF v_citizen_id IS NOT NULL THEN
    -- Consultations
    UPDATE public.consultations
    SET patient_citizen_id = v_citizen_id
    WHERE patient_citizen_id IS NULL
      AND (
        patient_identifier ILIKE ('%' || trim(p_firstname) || '%' || trim(p_surname) || '%')
        OR patient_identifier ILIKE ('%' || trim(p_surname) || '%' || trim(p_firstname) || '%')
        OR patient_identifier = v_citizen_id::text
        OR patient_identifier ILIKE ('CIT-' || v_citizen_id::text)
      );

    -- Prescription Headers
    UPDATE public.prescription_headers
    SET patient_citizen_id = v_citizen_id
    WHERE patient_citizen_id IS NULL
      AND (
        patient_identifier ILIKE ('%' || trim(p_firstname) || '%' || trim(p_surname) || '%')
        OR patient_identifier ILIKE ('%' || trim(p_surname) || '%' || trim(p_firstname) || '%')
        OR patient_identifier = v_citizen_id::text
        OR patient_identifier ILIKE ('CIT-' || v_citizen_id::text)
      );

    -- Queue Tickets
    UPDATE public.queue_tickets
    SET citizen_id = v_citizen_id
    WHERE citizen_id IS NULL
      AND walkin_patient_name IS NOT NULL
      AND (
        walkin_patient_name ILIKE ('%' || trim(p_firstname) || '%' || trim(p_surname) || '%')
        OR walkin_patient_name ILIKE ('%' || trim(p_surname) || '%' || trim(p_firstname) || '%')
      );

    -- OTC Dispenses
    UPDATE public.otc_dispenses
    SET citizen_id = v_citizen_id
    WHERE citizen_id IS NULL
      AND walkin_patient_name IS NOT NULL
      AND (
        walkin_patient_name ILIKE ('%' || trim(p_firstname) || '%' || trim(p_surname) || '%')
        OR walkin_patient_name ILIKE ('%' || trim(p_surname) || '%' || trim(p_firstname) || '%')
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
