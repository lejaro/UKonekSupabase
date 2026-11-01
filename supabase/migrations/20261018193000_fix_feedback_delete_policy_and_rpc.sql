-- Migration: 20261018193000_fix_feedback_delete_policy_and_rpc.sql
-- Description: Enable doctors and clinical administrators to delete patient reviews / feedback,
--              grant DELETE privilege on public.feedbacks to authenticated users,
--              and create the delete_feedback RPC function with security definer.

BEGIN;

-- 1. Ensure helper functions are robust and bypass row_security to prevent recursion
CREATE OR REPLACE FUNCTION public.is_clinical_staff()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_clinical boolean;
BEGIN
  PERFORM set_config('row_security', 'off', true);
  SELECT EXISTS (
    SELECT 1 FROM public.staff
    WHERE (
      auth_user_id = auth.uid()
      OR (
        auth.jwt()->>'email' IS NOT NULL
        AND lower(trim(email)) = lower(trim(auth.jwt()->>'email'))
      )
    )
    AND lower(trim(coalesce(status, ''))) = 'active'
    AND lower(trim(coalesce(role, ''))) IN ('doctor', 'nurse', 'admin')
  ) INTO v_is_clinical;
  RETURN coalesce(v_is_clinical, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_clinical_staff() TO authenticated, anon;

-- Helper to check if caller is specifically a doctor or administrator
CREATE OR REPLACE FUNCTION public.is_doctor_or_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_doctor_or_admin boolean;
BEGIN
  PERFORM set_config('row_security', 'off', true);
  SELECT EXISTS (
    SELECT 1 FROM public.staff
    WHERE (
      auth_user_id = auth.uid()
      OR (
        auth.jwt()->>'email' IS NOT NULL
        AND lower(trim(email)) = lower(trim(auth.jwt()->>'email'))
      )
    )
    AND lower(trim(coalesce(status, ''))) = 'active'
    AND lower(trim(coalesce(role, ''))) IN ('doctor', 'admin')
  ) INTO v_is_doctor_or_admin;
  RETURN coalesce(v_is_doctor_or_admin, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_doctor_or_admin() TO authenticated, anon;

-- 2. Grant table privileges: Ensure authenticated role can delete and manage feedbacks
GRANT SELECT, INSERT, UPDATE, DELETE ON public.feedbacks TO authenticated;
GRANT ALL ON public.feedbacks TO service_role;

-- 3. Update RLS policies on public.feedbacks for DELETE
DROP POLICY IF EXISTS feedbacks_delete_staff ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_delete_clinical_staff ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_delete_doctor_staff ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_delete_doctor_or_admin ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_manage_admin ON public.feedbacks;

-- Allow doctors, clinical staff, and admins to delete feedback / reviews
CREATE POLICY feedbacks_delete_doctor_or_admin
  ON public.feedbacks
  FOR DELETE
  TO authenticated
  USING (
    public.is_doctor_or_admin()
    OR public.is_clinical_staff()
    OR public.is_active_staff()
    OR public.is_admin()
  );

-- Retain admin manage policy for all actions
CREATE POLICY feedbacks_manage_admin
  ON public.feedbacks
  FOR ALL
  TO authenticated
  USING (
    public.is_admin()
  )
  WITH CHECK (
    public.is_admin()
  );

-- 4. Create secure delete_feedback RPC function (single parameter signature)
CREATE OR REPLACE FUNCTION public.delete_feedback(p_feedback_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_deleted_count int;
  v_is_authorized boolean := false;
  v_role text;
BEGIN
  PERFORM set_config('row_security', 'off', true);

  -- Validate caller authorization: doctor, admin, active staff, or service role
  IF public.is_doctor_or_admin()
    OR public.is_clinical_staff()
    OR public.is_active_staff()
    OR public.is_admin()
  THEN
    v_is_authorized := true;
  END IF;

  IF NOT v_is_authorized THEN
    SELECT role INTO v_role
    FROM public.staff
    WHERE (
      auth_user_id = auth.uid()
      OR (
        auth.jwt()->>'email' IS NOT NULL
        AND lower(trim(email)) = lower(trim(auth.jwt()->>'email'))
      )
    )
    AND lower(trim(coalesce(status, ''))) = 'active'
    LIMIT 1;

    IF lower(trim(coalesce(v_role, ''))) IN ('doctor', 'admin', 'nurse', 'staff') THEN
      v_is_authorized := true;
    END IF;
  END IF;

  IF NOT v_is_authorized AND (auth.role() = 'service_role' OR current_user = 'postgres') THEN
    v_is_authorized := true;
  END IF;

  IF NOT v_is_authorized THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Forbidden: Doctor or administrator privileges required to delete reviews'
    );
  END IF;

  IF p_feedback_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid feedback ID provided'
    );
  END IF;

  DELETE FROM public.feedbacks
  WHERE id = p_feedback_id;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  IF v_deleted_count = 0 THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Feedback record not found or already deleted'
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Patient review / feedback record successfully deleted',
    'id', p_feedback_id
  );
END;
$$;

-- Overload for two optional parameters: (p_feedback_id bigint, p_id bigint)
CREATE OR REPLACE FUNCTION public.delete_feedback(
  p_feedback_id bigint DEFAULT NULL,
  p_id bigint DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  RETURN public.delete_feedback(p_feedback_id => coalesce(p_feedback_id, p_id));
END;
$$;

-- Overload alias for backward compatibility or direct p_id calls
CREATE OR REPLACE FUNCTION public.delete_feedback_admin(p_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  RETURN public.delete_feedback(p_feedback_id => p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_feedback(bigint) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_feedback(bigint, bigint) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_feedback_admin(bigint) TO authenticated, anon, service_role;

COMMIT;
