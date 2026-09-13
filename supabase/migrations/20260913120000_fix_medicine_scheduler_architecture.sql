-- ==============================================================================
-- Migration: 20260913120000_fix_medicine_scheduler_architecture.sql
-- Description:
--   1. Add permanent patient_citizen_id column to prescription_headers with backfill
--      so prescriptions survive daily queue ticket purges.
--   2. Upgrade get_my_medicine_schedule(p_citizen_id) with precise item-level dispensing
--      filtering (no undispened items on partial Rx), OTC dispenses support, and optional citizen ID.
--   3. Upgrade get_my_prescribed_medicines(p_limit, p_citizen_id) to return prescription_item_id
--      and support robust citizen identification.
--   4. Upgrade get_my_prescription_dispense_logs(p_prescription_id, p_limit, p_citizen_id)
--      with OTC dispense inclusion and optional citizen ID.
--   5. Fix partial dispense timestamp updating in dispense_prescription_items.
-- ==============================================================================

-- ── 1. Add patient_citizen_id to prescription_headers ─────────────────────────
ALTER TABLE public.prescription_headers
  ADD COLUMN IF NOT EXISTS patient_citizen_id BIGINT REFERENCES public.citizens(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_prescription_headers_citizen
  ON public.prescription_headers(patient_citizen_id);

-- Backfill patient_citizen_id from multiple reliable sources:
-- Source A: Linked consultations
UPDATE public.prescription_headers ph
SET patient_citizen_id = con.patient_citizen_id
FROM public.consultations con
WHERE con.id = ph.consultation_id
  AND con.patient_citizen_id IS NOT NULL
  AND ph.patient_citizen_id IS NULL;

-- Source B: patient_identifier starting with CIT-
UPDATE public.prescription_headers ph
SET patient_citizen_id = substring(ph.patient_identifier FROM '(?i)CIT-(\d+)')::bigint
WHERE ph.patient_citizen_id IS NULL
  AND ph.patient_identifier ~* '^CIT-\d+$'
  AND EXISTS (
    SELECT 1 FROM public.citizens c
    WHERE c.id = substring(ph.patient_identifier FROM '(?i)CIT-(\d+)')::bigint
  );

-- Source C: Numeric patient_identifier directly matching citizen ID
UPDATE public.prescription_headers ph
SET patient_citizen_id = ph.patient_identifier::bigint
WHERE ph.patient_citizen_id IS NULL
  AND ph.patient_identifier ~ '^\d+$'
  AND EXISTS (
    SELECT 1 FROM public.citizens c
    WHERE c.id = ph.patient_identifier::bigint
  );

-- Source D: Active or historical queue tickets
UPDATE public.prescription_headers ph
SET patient_citizen_id = qt.citizen_id
FROM public.queue_tickets qt
WHERE ph.patient_citizen_id IS NULL
  AND qt.citizen_id IS NOT NULL
  AND (
    qt.ticket_code = ph.patient_identifier
    OR ('QUEUE-' || qt.id::text) = ph.patient_identifier
    OR qt.id::text = ph.patient_identifier
  );

-- Source E: Consultation patient_identifier fallback
UPDATE public.prescription_headers ph
SET patient_citizen_id = substring(con.patient_identifier FROM '(?i)CIT-(\d+)')::bigint
FROM public.consultations con
WHERE ph.consultation_id = con.id
  AND ph.patient_citizen_id IS NULL
  AND con.patient_identifier ~* '^CIT-\d+$'
  AND EXISTS (
    SELECT 1 FROM public.citizens c
    WHERE c.id = substring(con.patient_identifier FROM '(?i)CIT-(\d+)')::bigint
  );


-- ── 2. Upgrade get_my_medicine_schedule RPC ──────────────────────────────────
DROP FUNCTION IF EXISTS public.get_my_medicine_schedule() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_medicine_schedule(bigint) CASCADE;

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
BEGIN
  -- Resolve citizen by explicit ID, auth_user_id, or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE (p_citizen_id IS NOT NULL AND c.id = p_citizen_id)
     OR c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  ORDER BY
    (CASE WHEN p_citizen_id IS NOT NULL AND c.id = p_citizen_id THEN 0
          WHEN c.auth_user_id = auth.uid() THEN 1
          ELSE 2 END) ASC
  LIMIT 1;

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


-- ── 3. Upgrade get_my_prescribed_medicines RPC ────────────────────────────────
DROP FUNCTION IF EXISTS public.get_my_prescribed_medicines() CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescribed_medicines(integer) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescribed_medicines(integer, bigint) CASCADE;

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
BEGIN
  -- Resolve citizen by explicit ID, auth_user_id, or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE (p_citizen_id IS NOT NULL AND c.id = p_citizen_id)
     OR c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
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


-- ── 4. Upgrade get_my_prescription_dispense_logs RPC ──────────────────────────
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(bigint, integer) CASCADE;
DROP FUNCTION IF EXISTS public.get_my_prescription_dispense_logs(bigint, integer, bigint) CASCADE;

CREATE OR REPLACE FUNCTION public.get_my_prescription_dispense_logs(
  p_prescription_id bigint DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_citizen_id bigint DEFAULT NULL
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
  -- Resolve citizen by explicit ID, auth_user_id, or authenticated email
  SELECT * INTO v_citizen
  FROM public.citizens c
  WHERE (p_citizen_id IS NOT NULL AND c.id = p_citizen_id)
     OR c.auth_user_id = auth.uid()
     OR (c.email IS NOT NULL AND c.email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  ORDER BY
    (CASE WHEN p_citizen_id IS NOT NULL AND c.id = p_citizen_id THEN 0
          WHEN c.auth_user_id = auth.uid() THEN 1
          ELSE 2 END) ASC
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
    AND (p_prescription_id IS NULL OR ph.id = p_prescription_id)
  ),
  fallback_dispenses AS (
    SELECT
      ph.id * 1000 + pi.id AS dispense_id,
      ph.id AS prescription_id,
      ph.prescription_code,
      pi.id AS prescription_item_id,
      pi.medicine_name,
      coalesce(pi.dosage, '') AS dosage,
      coalesce(nullif(pi.dispensed_quantity, 0), pi.quantity, 1) AS dispensed_quantity,
      coalesce(pi.unit, '') AS unit,
      'Fulfilled by Pharmacy' AS note,
      'Pharmacist' AS pharmacist_name,
      coalesce(ph.dispensed_at, ph.issued_at) AS dispensed_at
    FROM public.prescription_items pi
    JOIN public.prescription_headers ph ON ph.id = pi.prescription_id
    LEFT JOIN public.consultations con ON con.id = ph.consultation_id
    WHERE (
      ph.dispensing_status IN ('dispensed', 'partial')
      OR pi.is_dispensed = true
      OR coalesce(pi.dispensed_quantity, 0) > 0
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
    )
    AND (p_prescription_id IS NULL OR ph.id = p_prescription_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.prescription_item_dispenses pid
      WHERE pid.prescription_id = ph.id
        AND pid.prescription_item_id = pi.id
    )
  ),
  otc_dispenses_list AS (
    SELECT
      (-odi.id) AS dispense_id,
      (-od.id) AS prescription_id,
      od.reference_no AS prescription_code,
      (-odi.id) AS prescription_item_id,
      m.name AS medicine_name,
      coalesce(m.dosage, '') AS dosage,
      odi.quantity AS dispensed_quantity,
      coalesce(odi.unit, m.unit, '') AS unit,
      coalesce(odi.instructions, 'Over-the-counter dispense') AS note,
      coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Pharmacist') AS pharmacist_name,
      od.dispensed_at
    FROM public.otc_dispense_items odi
    JOIN public.otc_dispenses od ON od.id = odi.otc_dispense_id
    JOIN public.medicines m ON m.id = odi.medicine_id
    LEFT JOIN public.staff s ON s.id = od.dispensed_by_staff_id
    WHERE od.citizen_id = v_citizen.id
      AND p_prescription_id IS NULL
  )
  SELECT * FROM (
    SELECT * FROM logged_dispenses
    UNION ALL
    SELECT * FROM fallback_dispenses
    UNION ALL
    SELECT * FROM otc_dispenses_list
  ) combined
  ORDER BY combined.dispensed_at DESC, combined.dispense_id DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_prescription_dispense_logs(bigint, integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_prescription_dispense_logs(bigint, integer, bigint) TO authenticated;

-- Alias for backwards compatibility
CREATE OR REPLACE FUNCTION public.get_my_dispense_history(
  p_prescription_id bigint DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_citizen_id bigint DEFAULT NULL
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
  SELECT * FROM public.get_my_prescription_dispense_logs(p_prescription_id, p_limit, p_citizen_id);
$$;

REVOKE ALL ON FUNCTION public.get_my_dispense_history(bigint, integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_dispense_history(bigint, integer, bigint) TO authenticated;


-- ── 5. Fix dispense_prescription_items: ensure dispensed_at is always set ─────
CREATE OR REPLACE FUNCTION public.dispense_prescription_items(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id bigint;
  v_role text;
  v_header_id bigint;
  v_header_status text;
  v_row record;
  v_item record;
  v_medicine_id bigint;
  v_medicine_qty integer;
  v_medicine_expiry date;
  v_new_status text;
  v_total_rows integer;
  v_target_med_id bigint;
BEGIN
  -- Resolve caller
  SELECT s.id, lower(trim(coalesce(s.role, '')))
  INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = (SELECT auth.uid())
    AND lower(trim(coalesce(s.status, ''))) = 'active'
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated as active staff');
  END IF;

  IF v_role <> 'pharmacist' THEN
    RETURN json_build_object('error', 'Forbidden: only pharmacists can dispense prescriptions');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN json_build_object('error', 'No dispense items provided');
  END IF;

  BEGIN
    -- Lock target prescription header
    SELECT ph.id, ph.dispensing_status
    INTO v_header_id, v_header_status
    FROM public.prescription_headers ph
    WHERE upper(trim(ph.prescription_code)) = upper(trim(coalesce(p_prescription_code, '')))
    LIMIT 1
    FOR UPDATE;

    IF v_header_id IS NULL THEN
      RAISE EXCEPTION 'Prescription not found';
    END IF;

    IF v_header_status = 'cancelled' THEN
      RAISE EXCEPTION 'Prescription has been cancelled and cannot be dispensed';
    END IF;

    IF v_header_status = 'expired' THEN
      RAISE EXCEPTION 'Prescription has expired and can no longer be dispensed';
    END IF;

    IF v_header_status = 'dispensed' THEN
      RAISE EXCEPTION 'Prescription is already fully dispensed';
    END IF;

    -- Disallow duplicate item IDs in request payload
    IF EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer)
      GROUP BY r.prescription_item_id
      HAVING count(*) > 1
    ) THEN
      RAISE EXCEPTION 'Duplicate prescription_item_id in request payload';
    END IF;

    -- Process items in deterministic ascending order to prevent deadlocks
    FOR v_row IN
      SELECT r.prescription_item_id, r.quantity, r.medicine_id
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer, medicine_id bigint)
      ORDER BY r.prescription_item_id ASC
    LOOP
      IF v_row.prescription_item_id IS NULL THEN
        RAISE EXCEPTION 'prescription_item_id is required for every item';
      END IF;

      IF v_row.quantity IS NULL OR v_row.quantity < 0 THEN
        RAISE EXCEPTION 'Dispense quantity cannot be negative for item %', v_row.prescription_item_id;
      END IF;

      IF v_row.quantity = 0 THEN
        CONTINUE;
      END IF;

      SELECT
        pi.id,
        pi.medicine_id,
        pi.medicine_name,
        pi.unit,
        pi.quantity,
        coalesce(pi.dispensed_quantity, 0) AS dispensed_quantity,
        coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) AS remaining_quantity
      INTO v_item
      FROM public.prescription_items pi
      WHERE pi.id = v_row.prescription_item_id
        AND pi.prescription_id = v_header_id
      FOR UPDATE;

      IF v_item.id IS NULL THEN
        RAISE EXCEPTION 'Prescription item % not found for this prescription', v_row.prescription_item_id;
      END IF;

      IF v_row.quantity > v_item.remaining_quantity THEN
        RAISE EXCEPTION
          'Over-dispense blocked for % (remaining: %, requested: %)',
          v_item.medicine_name, v_item.remaining_quantity, v_row.quantity;
      END IF;

      -- Determine explicit medicine ID if passed in payload or already stored on item
      v_target_med_id := coalesce(v_row.medicine_id, v_item.medicine_id);

      -- Resilient multi-tier inventory resolution:
      SELECT m.id, m.qty, m.expiry_date
      INTO v_medicine_id, v_medicine_qty, v_medicine_expiry
      FROM public.medicines m
      WHERE (
        (v_target_med_id IS NOT NULL AND m.id = v_target_med_id)
        OR lower(trim(m.name)) = lower(trim(v_item.medicine_name))
        OR (
          public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name)
          AND length(public.normalize_medicine_name(m.name)) >= 3
        )
        OR (
          length(trim(m.name)) >= 4
          AND (
            lower(trim(v_item.medicine_name)) LIKE ('%' || lower(trim(m.name)) || '%')
            OR lower(trim(m.name)) LIKE ('%' || lower(trim(v_item.medicine_name)) || '%')
          )
        )
      )
      AND m.archived_at IS NULL
      ORDER BY
        (CASE WHEN v_target_med_id IS NOT NULL AND m.id = v_target_med_id THEN 0 ELSE 1 END) ASC,
        (CASE WHEN lower(trim(m.name)) = lower(trim(v_item.medicine_name)) THEN 0 ELSE 1 END) ASC,
        (CASE WHEN public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name)
                   AND substring(m.name FROM '\d+') IS NOT NULL
                   AND substring(m.name FROM '\d+') = substring(v_item.medicine_name FROM '\d+')
              THEN 0 ELSE 1 END) ASC,
        (CASE WHEN public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name) THEN 0 ELSE 1 END) ASC,
        (CASE WHEN length(trim(m.name)) >= 4 AND (
                    lower(trim(v_item.medicine_name)) LIKE ('%' || lower(trim(m.name)) || '%')
                    OR lower(trim(m.name)) LIKE ('%' || lower(trim(v_item.medicine_name)) || '%')
                   ) THEN 0 ELSE 1 END) ASC,
        (CASE WHEN m.qty >= v_row.quantity THEN 0 ELSE 1 END) ASC,
        (CASE WHEN m.expiry_date IS NULL OR m.expiry_date >= current_date THEN 0 ELSE 1 END) ASC,
        m.id ASC
      LIMIT 1
      FOR UPDATE;

      IF v_medicine_id IS NULL THEN
        RAISE EXCEPTION 'Medicine not found in inventory: %', v_item.medicine_name;
      END IF;

      IF v_medicine_expiry IS NOT NULL AND v_medicine_expiry < current_date THEN
        RAISE EXCEPTION 'Safety block: Inventory batch for % expired on % and cannot be dispensed.',
          v_item.medicine_name, to_char(v_medicine_expiry, 'YYYY-MM-DD');
      END IF;

      IF v_medicine_qty < v_row.quantity THEN
        RAISE EXCEPTION
          'Insufficient stock for % (available: %, requested: %)',
          v_item.medicine_name, v_medicine_qty, v_row.quantity;
      END IF;

      -- Deduct inventory stock
      UPDATE public.medicines
      SET qty = qty - v_row.quantity
      WHERE id = v_medicine_id;

      -- Update item counters
      UPDATE public.prescription_items
      SET
        medicine_id = coalesce(v_item.medicine_id, v_medicine_id),
        dispensed_quantity = v_item.dispensed_quantity + v_row.quantity,
        remaining_quantity = v_item.remaining_quantity - v_row.quantity,
        is_dispensed = (v_item.remaining_quantity - v_row.quantity = 0),
        last_dispensed_at = now()
      WHERE id = v_item.id;

      -- Record dispense event
      INSERT INTO public.prescription_item_dispenses (
        prescription_id,
        prescription_item_id,
        medicine_id,
        dispensed_quantity,
        unit,
        note,
        dispensed_by_staff_id,
        dispensed_at
      ) VALUES (
        v_header_id,
        v_item.id,
        v_medicine_id,
        v_row.quantity,
        coalesce(v_item.unit, ''),
        nullif(trim(p_note), ''),
        v_staff_id,
        now()
      );
    END LOOP;

    -- Recalculate prescription header status
    SELECT
      count(*),
      count(*) FILTER (WHERE remaining_quantity = 0),
      count(*) FILTER (WHERE remaining_quantity > 0 AND dispensed_quantity > 0)
    INTO v_total_rows, v_medicine_qty, v_medicine_id
    FROM public.prescription_items
    WHERE prescription_id = v_header_id;

    IF v_total_rows = 0 THEN
      v_new_status := 'pending';
    ELSIF v_medicine_qty = v_total_rows THEN
      v_new_status := 'dispensed';
    ELSIF v_medicine_qty > 0 OR v_medicine_id > 0 THEN
      v_new_status := 'partial';
    ELSE
      v_new_status := 'pending';
    END IF;

    -- Update header: ensure dispensed_at is ALWAYS populated upon any dispense activity
    UPDATE public.prescription_headers
    SET
      dispensing_status = v_new_status,
      dispensed_by_staff_id = v_staff_id,
      dispensed_at = coalesce(dispensed_at, now())
    WHERE id = v_header_id;

    RETURN json_build_object(
      'ok', true,
      'prescription_code', upper(trim(p_prescription_code)),
      'dispensing_status', v_new_status
    );
  EXCEPTION
    WHEN OTHERS THEN
      RETURN json_build_object('error', sqlerrm);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.dispense_prescription_items(text, jsonb, text) TO authenticated;
