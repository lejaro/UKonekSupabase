-- Migration: 20261019153000_resolve_delete_feedback_postgrest_overload.sql
-- Description: Drop overloaded 2-parameter signature for delete_feedback to eliminate PostgREST PGRST203 ambiguity.

BEGIN;

DROP FUNCTION IF EXISTS public.delete_feedback(bigint, bigint);

-- Ensure public.delete_feedback(bigint) is the single canonical function
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

  -- Validate caller authorization: doctor, admin, active clinical staff, or service role
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

-- Alias delete_feedback_admin(p_id bigint)
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
GRANT EXECUTE ON FUNCTION public.delete_feedback_admin(bigint) TO authenticated, anon, service_role;

COMMIT;
