-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: Staff Status Case Sensitivity Issue
-- ═══════════════════════════════════════════════════════════════════════════
-- Problem: list_staff_accounts() filters by lowercase 'active' but data may be 'Active'
-- Solution: Normalize existing data and update function to be case-insensitive
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Normalize existing staff status values to lowercase
-- ───────────────────────────────────────────────────────────────────────────

-- Ensure sanitize_text_columns does not use invalid := assignment before updates run
CREATE OR REPLACE FUNCTION sanitize_text_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  column_name TEXT;
  column_value TEXT;
BEGIN
  FOR column_name IN
    SELECT attname
    FROM pg_attribute
    WHERE attrelid = TG_RELID
      AND atttypid IN ('text'::regtype, 'varchar'::regtype, 'character varying'::regtype)
      AND attnum > 0
      AND NOT attisdropped
  LOOP
    EXECUTE format('SELECT ($1).%I', column_name) USING NEW INTO column_value;

    IF column_value IS NOT NULL THEN
      column_value := validate_text_input(column_value);
      NEW := jsonb_populate_record(NEW, jsonb_build_object(column_name, column_value));
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

UPDATE public.staff
SET status = LOWER(TRIM(COALESCE(status, 'active')))
WHERE status IS NOT NULL;

-- Set default for NULL values
UPDATE public.staff
SET status = 'active'
WHERE status IS NULL OR TRIM(status) = '';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Add constraint to enforce lowercase status values
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_status_lowercase;
ALTER TABLE public.staff ADD CONSTRAINT staff_status_lowercase 
    CHECK (status = LOWER(status));

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Update list_staff_accounts to be more robust
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.list_staff_accounts();

CREATE OR REPLACE FUNCTION public.list_staff_accounts()
RETURNS TABLE (
  id BIGINT,
  first_name VARCHAR,
  middle_name VARCHAR,
  last_name VARCHAR,
  birthday DATE,
  gender VARCHAR,
  username VARCHAR,
  employee_id VARCHAR,
  email VARCHAR,
  role VARCHAR,
  status VARCHAR,
  doctor_specialization TEXT,
  is_online BOOLEAN,
  last_seen TIMESTAMPTZ,
  availability_status TEXT,
  created_at TIMESTAMPTZ,
  auth_user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.first_name,
    s.middle_name,
    s.last_name,
    s.birthday,
    s.gender,
    s.username,
    s.employee_id,
    s.email,
    s.role,
    s.status,
    s.doctor_specialization,
    s.is_online,
    s.last_seen,
    s.availability_status,
    s.created_at,
    s.auth_user_id
  FROM public.staff s
  WHERE LOWER(TRIM(COALESCE(s.status, ''))) = 'active'
  ORDER BY s.id DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_staff_accounts() TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Update get_staff_profile to be case-insensitive
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_staff_profile();

CREATE OR REPLACE FUNCTION public.get_staff_profile()
RETURNS JSON
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
AS $$
DECLARE
  v_user_email TEXT;
  v_profile JSON;
BEGIN
  SELECT auth.jwt()->>'email' INTO v_user_email;

  IF v_user_email IS NULL THEN
    RETURN NULL;
  END IF;

  -- Try to find by auth_user_id first
  SELECT row_to_json(t) INTO v_profile
  FROM (
    SELECT id, first_name, middle_name, last_name, username, role, email, status, availability_status
    FROM public.staff
    WHERE auth_user_id = auth.uid()
      AND LOWER(TRIM(COALESCE(status, ''))) = 'active'
    LIMIT 1
  ) t;

  IF v_profile IS NOT NULL THEN
    RETURN v_profile;
  END IF;

  -- Try to find by email
  SELECT row_to_json(t) INTO v_profile
  FROM (
    SELECT id, first_name, middle_name, last_name, username, role, email, status, availability_status
    FROM public.staff
    WHERE LOWER(email) = LOWER(v_user_email)
      AND LOWER(TRIM(COALESCE(status, ''))) = 'active'
    LIMIT 1
  ) t;

  IF v_profile IS NOT NULL THEN
    -- Link auth_user_id if not already linked
    UPDATE public.staff
    SET auth_user_id = auth.uid()
    WHERE LOWER(email) = LOWER(v_user_email)
      AND auth_user_id IS NULL;

    RETURN v_profile;
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_profile() TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Documentation
-- ───────────────────────────────────────────────────────────────────────────

COMMENT ON FUNCTION public.list_staff_accounts() IS 
  'Lists all active staff accounts. Case-insensitive status filtering.';

COMMENT ON FUNCTION public.get_staff_profile() IS 
  'Gets the authenticated staff profile. Case-insensitive status filtering.';

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MIGRATION
-- ═══════════════════════════════════════════════════════════════════════════
