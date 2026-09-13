-- =============================================================================
-- Migration: Restrict Medicine Registration to Pharmacist Only
--
-- Purpose:
--   1. Drops medicines_insert_admin_or_doctor so doctors/admins cannot insert medicines.
--   2. Enforces medicines_insert_pharmacist as the sole INSERT policy on public.medicines.
--   3. Updates pharmacist_upsert_medicine RPC so that creating new medicines (p_id IS NULL)
--      strictly requires role = 'pharmacist'.
-- =============================================================================

BEGIN;

-- 1. Drop doctor/admin insert policy on medicines
DROP POLICY IF EXISTS medicines_insert_admin_or_doctor ON public.medicines;

-- 2. Ensure only active pharmacist staff can insert into medicines
DROP POLICY IF EXISTS medicines_insert_pharmacist ON public.medicines;

CREATE POLICY medicines_insert_pharmacist
  ON public.medicines
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND lower(trim(coalesce(s.status, ''))) = 'active'
        AND lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

-- 3. Update pharmacist_upsert_medicine RPC to enforce pharmacist-only registration
CREATE OR REPLACE FUNCTION public.pharmacist_upsert_medicine(
  p_id bigint DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_qty integer DEFAULT 0,
  p_unit text DEFAULT NULL,
  p_expiry_date date DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id bigint;
  v_role text;
  v_medicine_id bigint;
BEGIN
  SELECT s.id, lower(trim(coalesce(s.role, '')))
    INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = auth.uid()
    AND lower(trim(coalesce(s.status, ''))) = 'active'
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RETURN json_build_object('error', 'Authentication required');
  END IF;

  -- Only pharmacists can register new medicines
  IF p_id IS NULL AND v_role != 'pharmacist' THEN
    RETURN json_build_object('error', 'Forbidden: only pharmacists can register new medicines');
  END IF;

  -- For updates, role must be pharmacist, doctor, or nurse
  IF v_role NOT IN ('pharmacist', 'doctor', 'nurse') THEN
    RETURN json_build_object('error', 'Forbidden: insufficient role');
  END IF;

  IF p_qty < 0 THEN
    RETURN json_build_object('error', 'Stock quantity cannot be negative');
  END IF;

  IF p_id IS NULL THEN
    -- INSERT (Pharmacist Only)
    IF trim(coalesce(p_name, '')) = '' THEN
      RETURN json_build_object('error', 'Medicine name is required');
    END IF;

    INSERT INTO public.medicines (name, description, qty, unit, expiry_date, created_by_staff_id)
    VALUES (
      trim(p_name),
      nullif(trim(coalesce(p_description, '')), ''),
      coalesce(p_qty, 0),
      nullif(trim(coalesce(p_unit, '')), ''),
      p_expiry_date,
      v_staff_id
    )
    RETURNING id INTO v_medicine_id;

    RETURN json_build_object('ok', true, 'id', v_medicine_id, 'action', 'inserted');
  ELSE
    -- UPDATE (stock + expiry + description only; name is protected)
    UPDATE public.medicines
    SET
      qty = coalesce(p_qty, qty),
      expiry_date = coalesce(p_expiry_date, expiry_date),
      description = coalesce(nullif(trim(coalesce(p_description, '')), ''), description)
    WHERE id = p_id
      AND archived_at IS NULL;

    IF NOT FOUND THEN
      RETURN json_build_object('error', 'Medicine not found or archived');
    END IF;

    RETURN json_build_object('ok', true, 'id', p_id, 'action', 'updated');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pharmacist_upsert_medicine(bigint, text, text, integer, text, date) TO authenticated;

COMMIT;
