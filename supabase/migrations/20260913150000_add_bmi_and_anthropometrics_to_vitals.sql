-- =============================================================================
-- Migration: Add Anthropometrics (Height, Weight) and BMI to Vital Signs
--
-- Purpose:
--   1. Adds height_cm, weight_kg, and bmi columns to public.vital_signs.
--   2. Updates upsert_vital_assessment RPC to accept anthropometric data and store them.
--   3. Updates get_vitals_for_ticket RPC to return height_cm, weight_kg, and bmi.
-- =============================================================================

-- 1. Add columns to vital_signs table
ALTER TABLE public.vital_signs
  ADD COLUMN IF NOT EXISTS height_cm NUMERIC(5,1) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS weight_kg NUMERIC(5,1) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS bmi NUMERIC(4,1) DEFAULT NULL;

-- 2. Drop old overloads of upsert_vital_assessment to ensure clean signature
DROP FUNCTION IF EXISTS public.upsert_vital_assessment(bigint, bigint, text, text, integer, numeric, integer, integer, text, text);
DROP FUNCTION IF EXISTS public.upsert_vital_assessment(bigint, bigint, text, text, integer, numeric, integer, integer, text, text, numeric, numeric, numeric);

-- 3. Create or replace upsert_vital_assessment with anthropometrics support
CREATE OR REPLACE FUNCTION public.upsert_vital_assessment(
  p_queue_ticket_id     BIGINT,
  p_citizen_id          BIGINT,
  p_chief_complaint     TEXT,
  p_blood_pressure      TEXT     DEFAULT NULL,
  p_heart_rate          INTEGER  DEFAULT NULL,
  p_temperature         NUMERIC  DEFAULT NULL,
  p_respiratory_rate    INTEGER  DEFAULT NULL,
  p_oxygen_saturation   INTEGER  DEFAULT NULL,
  p_current_medications TEXT     DEFAULT NULL,
  p_notes               TEXT     DEFAULT NULL,
  p_height_cm           NUMERIC  DEFAULT NULL,
  p_weight_kg           NUMERIC  DEFAULT NULL,
  p_bmi                 NUMERIC  DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nurse_id   BIGINT;
  v_result_id  UUID;
BEGIN
  -- Caller must be active staff
  SELECT s.id INTO v_nurse_id
  FROM   public.staff s
  WHERE  s.auth_user_id = auth.uid()
    AND  lower(coalesce(s.status, '')) = 'active'
  LIMIT 1;

  IF v_nurse_id IS NULL THEN
    RETURN json_build_object('error', 'Forbidden: active staff account required');
  END IF;

  IF p_citizen_id IS NULL OR p_chief_complaint IS NULL OR trim(p_chief_complaint) = '' THEN
    RETURN json_build_object('error', 'citizen_id and chief_complaint are required');
  END IF;

  INSERT INTO public.vital_signs (
    queue_ticket_id,
    citizen_id,
    nurse_id,
    chief_complaint,
    blood_pressure,
    heart_rate,
    temperature,
    respiratory_rate,
    oxygen_saturation,
    current_medications,
    notes,
    height_cm,
    weight_kg,
    bmi,
    created_at
  )
  VALUES (
    p_queue_ticket_id,
    p_citizen_id,
    v_nurse_id,
    trim(p_chief_complaint),
    nullif(trim(coalesce(p_blood_pressure, '')), ''),
    p_heart_rate,
    p_temperature,
    p_respiratory_rate,
    p_oxygen_saturation,
    nullif(trim(coalesce(p_current_medications, '')), ''),
    nullif(trim(coalesce(p_notes, '')), ''),
    p_height_cm,
    p_weight_kg,
    p_bmi,
    now()
  )
  ON CONFLICT (queue_ticket_id)
  DO UPDATE SET
    citizen_id          = excluded.citizen_id,
    nurse_id            = excluded.nurse_id,
    chief_complaint     = excluded.chief_complaint,
    blood_pressure      = excluded.blood_pressure,
    heart_rate          = excluded.heart_rate,
    temperature         = excluded.temperature,
    respiratory_rate    = excluded.respiratory_rate,
    oxygen_saturation   = excluded.oxygen_saturation,
    current_medications = excluded.current_medications,
    notes               = excluded.notes,
    height_cm           = excluded.height_cm,
    weight_kg           = excluded.weight_kg,
    bmi                 = excluded.bmi,
    created_at          = now()
  RETURNING id INTO v_result_id;

  RETURN json_build_object('ok', true, 'id', v_result_id);
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', coalesce(sqlerrm, 'Failed to save vital assessment'));
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_vital_assessment(BIGINT, BIGINT, TEXT, TEXT, INTEGER, NUMERIC, INTEGER, INTEGER, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

-- 4. Update get_vitals_for_ticket to return anthropometrics and BMI
DROP FUNCTION IF EXISTS public.get_vitals_for_ticket(BIGINT);

CREATE OR REPLACE FUNCTION public.get_vitals_for_ticket(p_queue_ticket_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_row  JSON;
BEGIN
  v_role := lower(coalesce(public.get_staff_role(), ''));
  IF v_role = '' THEN
    RAISE EXCEPTION 'Forbidden: active staff account required';
  END IF;

  SELECT row_to_json(t) INTO v_row
  FROM (
    SELECT
      vs.id,
      vs.queue_ticket_id,
      vs.citizen_id,
      vs.chief_complaint,
      vs.blood_pressure,
      vs.heart_rate,
      vs.temperature,
      vs.respiratory_rate,
      vs.oxygen_saturation,
      vs.current_medications,
      vs.notes,
      vs.height_cm,
      vs.weight_kg,
      vs.bmi,
      vs.created_at,
      coalesce(
        nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
        'Nurse'
      ) AS nurse_name
    FROM   public.vital_signs vs
    LEFT   JOIN public.staff s ON s.id = vs.nurse_id
    WHERE  vs.queue_ticket_id = p_queue_ticket_id
    ORDER  BY vs.created_at DESC
    LIMIT  1
  ) t;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_vitals_for_ticket(BIGINT) TO authenticated;
