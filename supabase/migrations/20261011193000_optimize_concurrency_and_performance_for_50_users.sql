-- =============================================================================
-- Migration: 20261011193000_optimize_concurrency_and_performance_for_50_users.sql
-- Description: System-wide performance, indexing, and concurrency optimization
--              specifically designed for 50+ simultaneous active users.
--
-- Key Optimizations:
-- 1. Data Backfill: Permanently link unlinked consultations & prescriptions to patient_citizen_id.
-- 2. Index Hardening:
--    - pg_trgm GIN trigram indexes on citizens(firstname || ' ' || surname) & contact_number
--    - Expression index on prescription_headers(upper(trim(prescription_code)))
--    - Composite indexes on (patient_citizen_id, consulted_at DESC / issued_at DESC)
-- 3. Core Patient RPC Optimization (Eliminate 100% CPU regex & wildcard table scan traps):
--    - get_my_consultations
--    - get_my_prescribed_medicines
--    - get_my_medicine_schedule
-- 4. Single-Roundtrip Executive System Reports RPC (Eliminates 17-query parallel burst):
--    - get_system_reports_summary
-- 5. Hot Queue Path Decoupling:
--    - Remove statement trigger check_and_delete_old_queue_tickets from public.queue_tickets
--    - Introduce dedicated purge_expired_queue_tickets RPC
-- =============================================================================

-- =============================================================================
-- 1. EXTENSIONS & HIGH-PERFORMANCE INDEXES
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN Trigram indexes on citizens to turn keystroke searches into fast index lookups
CREATE INDEX IF NOT EXISTS idx_citizens_name_trgm 
  ON public.citizens USING gin ((firstname || ' ' || surname) gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_citizens_contact_trgm 
  ON public.citizens USING gin (contact_number gin_trgm_ops);

-- Expression index for pharmacy code lookup (matches upper(trim(prescription_code)))
CREATE INDEX IF NOT EXISTS idx_prescription_headers_upper_code 
  ON public.prescription_headers (upper(trim(prescription_code)));

-- Composite indexes on consultations & prescription_headers for patient dashboards
CREATE INDEX IF NOT EXISTS idx_consultations_patient_date 
  ON public.consultations (patient_citizen_id, consulted_at DESC);

CREATE INDEX IF NOT EXISTS idx_consultations_patient_ident 
  ON public.consultations (patient_identifier);

CREATE INDEX IF NOT EXISTS idx_prescription_headers_patient_date 
  ON public.prescription_headers (patient_citizen_id, issued_at DESC);

CREATE INDEX IF NOT EXISTS idx_prescription_headers_patient_ident 
  ON public.prescription_headers (patient_identifier);

CREATE INDEX IF NOT EXISTS idx_prescription_items_dispensed 
  ON public.prescription_items (prescription_id, is_dispensed);

CREATE INDEX IF NOT EXISTS idx_prescription_items_med_id 
  ON public.prescription_items (medicine_id);


-- =============================================================================
-- 2. RETROACTIVE LINKING / DATA BACKFILL
-- =============================================================================

-- Link any orphan consultations where patient_citizen_id is null
UPDATE public.consultations c
SET patient_citizen_id = ct.id
FROM public.citizens ct
WHERE c.patient_citizen_id IS NULL
  AND (
    c.patient_identifier = ct.id::text
    OR c.patient_identifier = ('CIT-' || ct.id::text)
    OR (
      c.patient_identifier ~ '^\D*\d+\D*$' 
      AND regexp_replace(c.patient_identifier, '\D', '', 'g') = ct.id::text
    )
  );

-- Link any orphan prescription headers where patient_citizen_id is null
UPDATE public.prescription_headers ph
SET patient_citizen_id = ct.id
FROM public.citizens ct
WHERE ph.patient_citizen_id IS NULL
  AND (
    ph.patient_identifier = ct.id::text
    OR ph.patient_identifier = ('CIT-' || ct.id::text)
    OR (
      ph.patient_identifier ~ '^\D*\d+\D*$' 
      AND regexp_replace(ph.patient_identifier, '\D', '', 'g') = ct.id::text
    )
  );


-- =============================================================================
-- 3. OPTIMIZE get_my_consultations (REPLACE REGEX SCANS WITH INDEXED LOOKUPS)
-- =============================================================================

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
  -- Check if caller is active staff
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
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

  -- Index-friendly exact key lookups (no regex, no correlated subqueries, no wildcard scans)
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
    OR c.patient_identifier = ('CIT-' || v_citizen.id::text)
  )
  ORDER BY c.consulted_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_consultations(integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_consultations(integer, bigint) TO authenticated;


-- =============================================================================
-- 4. OPTIMIZE get_my_prescribed_medicines
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_prescribed_medicines(
  p_limit integer DEFAULT 50,
  p_citizen_id bigint DEFAULT NULL
)
RETURNS TABLE (
  prescription_id bigint,
  prescription_item_id bigint,
  prescription_code text,
  dispensing_status text,
  issued_at timestamptz,
  dispensed_at timestamptz,
  doctor_name text,
  medicine_name text,
  quantity integer,
  dispensed_quantity integer,
  remaining_quantity integer,
  unit text,
  dosage text,
  frequency text,
  duration text,
  instructions text,
  additional_info text,
  is_dispensed boolean
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
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
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

  -- Index-friendly exact key lookups
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
    OR ph.patient_identifier = ('CIT-' || v_citizen.id::text)
  )
  ORDER BY ph.issued_at DESC, pi.id ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_prescribed_medicines(integer, bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_prescribed_medicines(integer, bigint) TO authenticated;


-- =============================================================================
-- 5. OPTIMIZE get_my_medicine_schedule
-- =============================================================================

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
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(trim(coalesce(s.status, ''))) = 'active'
  ) INTO v_is_staff;

  IF p_citizen_id IS NOT NULL THEN
    SELECT * INTO v_citizen
    FROM public.citizens c
    WHERE c.id = p_citizen_id
      AND (v_is_staff OR c.auth_user_id = auth.uid())
    LIMIT 1;
  ELSE
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
      pi.is_dispensed = true
      OR coalesce(pi.dispensed_quantity, 0) > 0
      OR (ph.dispensing_status = 'dispensed' AND coalesce(pi.remaining_quantity, 0) <= 0)
    )
    AND (
      ph.patient_citizen_id = v_citizen.id
      OR con.patient_citizen_id = v_citizen.id
      OR ph.patient_identifier = v_citizen.id::text
      OR ph.patient_identifier = ('CIT-' || v_citizen.id::text)
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


-- =============================================================================
-- 6. CONSOLIDATED EXECUTIVE SYSTEM REPORTS SUMMARY RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_system_reports_summary(
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date;
  v_end date;
BEGIN
  IF p_start_date IS NOT NULL THEN
    v_start := (p_start_date AT TIME ZONE 'Asia/Manila')::date;
  END IF;
  IF p_end_date IS NOT NULL THEN
    v_end := (p_end_date AT TIME ZONE 'Asia/Manila')::date;
  END IF;

  RETURN json_build_object(
    'consultations_count', (
      SELECT count(*) FROM public.consultations
      WHERE (p_start_date IS NULL OR consulted_at >= p_start_date)
        AND (p_end_date IS NULL OR consulted_at <= p_end_date)
    ),
    'vitals_count', (
      SELECT count(*) FROM public.vital_signs
      WHERE (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    ),
    'queue_tickets_count', (
      SELECT count(*) FROM public.queue_tickets
      WHERE (v_start IS NULL OR queue_date >= v_start)
        AND (v_end IS NULL OR queue_date <= v_end)
    ),
    'completed_tickets_count', (
      SELECT count(*) FROM public.queue_tickets
      WHERE status = 'completed'
        AND (v_start IS NULL OR queue_date >= v_start)
        AND (v_end IS NULL OR queue_date <= v_end)
    ),
    'cancelled_tickets_count', (
      SELECT count(*) FROM public.queue_tickets
      WHERE status = 'cancelled'
        AND (v_start IS NULL OR queue_date >= v_start)
        AND (v_end IS NULL OR queue_date <= v_end)
    ),
    'prescriptions_count', (
      SELECT count(*) FROM public.prescription_headers
      WHERE (p_start_date IS NULL OR issued_at >= p_start_date)
        AND (p_end_date IS NULL OR issued_at <= p_end_date)
    ),
    'dispensed_prescriptions_count', (
      SELECT count(*) FROM public.prescription_headers
      WHERE dispensing_status = 'dispensed'
        AND (p_start_date IS NULL OR issued_at >= p_start_date)
        AND (p_end_date IS NULL OR issued_at <= p_end_date)
    ),
    'lab_orders_count', (
      SELECT count(*) FROM public.lab_orders
      WHERE (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    ),
    'completed_labs_count', (
      SELECT count(*) FROM public.lab_orders
      WHERE status = 'completed'
        AND (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    ),
    'total_citizens_count', (
      SELECT count(*) FROM public.citizens
    ),
    'new_citizens_count', (
      SELECT count(*) FROM public.citizens
      WHERE (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    ),
    'active_medicines_count', (
      SELECT count(*) FROM public.medicines WHERE archived_at IS NULL
    ),
    'low_stock_medicines_count', (
      SELECT count(*) FROM public.medicines WHERE archived_at IS NULL AND qty <= 10
    ),
    'staff_logins_count', (
      SELECT count(*) FROM public.staff_login_logs
      WHERE action = 'login'
        AND (p_start_date IS NULL OR logged_at >= p_start_date)
        AND (p_end_date IS NULL OR logged_at <= p_end_date)
    ),
    'feedbacks_count', (
      SELECT count(*) FROM public.feedbacks
      WHERE (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    ),
    'announcements_count', (
      SELECT count(*) FROM public.announcements
      WHERE (p_start_date IS NULL OR created_at >= p_start_date)
        AND (p_end_date IS NULL OR created_at <= p_end_date)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_system_reports_summary(timestamptz, timestamptz) TO authenticated, service_role;


-- =============================================================================
-- 7. HOT QUEUE PATH DECOUPLING (REMOVE STATEMENT TRIGGER FROM TICKET INSERT)
-- =============================================================================

-- Remove synchronous blocking delete trigger from hot ticket insertion path
DROP TRIGGER IF EXISTS trigger_cleanup_old_queue_tickets ON public.queue_tickets;

-- Dedicated maintenance purge function (can be invoked off-peak or periodically)
CREATE OR REPLACE FUNCTION public.purge_expired_queue_tickets(p_days_to_keep integer DEFAULT 7)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff date;
  v_deleted integer := 0;
BEGIN
  v_cutoff := public.get_manila_date() - greatest(1, p_days_to_keep);

  DELETE FROM public.queue_tickets
  WHERE queue_date < v_cutoff
    AND status IN ('completed', 'cancelled');

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.purge_expired_queue_tickets(integer) TO authenticated, service_role;
