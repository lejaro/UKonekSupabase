-- Migration: 20261018193000_fix_feedback_delete_policy_and_rpc.sql
-- Description: Enable active clinical staff and administrators to delete citizen feedback / reviews,
--              grant DELETE privilege on public.feedbacks to authenticated users,
--              and create the delete_feedback RPC function with security definer.

BEGIN;

-- 1. Grant table privileges: Ensure authenticated role can delete and manage feedbacks
GRANT SELECT, INSERT, UPDATE, DELETE ON public.feedbacks TO authenticated;
GRANT ALL ON public.feedbacks TO service_role;

-- 2. Update RLS policies on public.feedbacks for DELETE
DROP POLICY IF EXISTS feedbacks_delete_staff ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_delete_clinical_staff ON public.feedbacks;
DROP POLICY IF EXISTS feedbacks_manage_admin ON public.feedbacks;

-- Allow active staff (doctors, nurses, admins) to delete feedback
CREATE POLICY feedbacks_delete_staff
  ON public.feedbacks
  FOR DELETE
  TO authenticated
  USING (
    public.is_active_staff()
    OR public.is_clinical_staff()
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

-- 3. Create secure delete_feedback RPC function
CREATE OR REPLACE FUNCTION public.delete_feedback(
  p_feedback_id bigint DEFAULT NULL,
  p_id bigint DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_target_id bigint := coalesce(p_feedback_id, p_id);
  v_deleted_count int;
BEGIN
  -- Validate caller authorization
  IF NOT (
    public.is_active_staff()
    OR public.is_clinical_staff()
    OR public.is_admin()
    OR auth.role() = 'service_role'
    OR current_user = 'postgres'
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Forbidden: active staff or administrator privileges required'
    );
  END IF;

  IF v_target_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid feedback ID provided'
    );
  END IF;

  DELETE FROM public.feedbacks
  WHERE id = v_target_id;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  IF v_deleted_count = 0 THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Feedback record not found or already deleted'
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Citizen feedback record successfully deleted',
    'id', v_target_id
  );
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
  RETURN public.delete_feedback(p_id => p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_feedback(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_feedback_admin(bigint) TO authenticated;

COMMIT;
