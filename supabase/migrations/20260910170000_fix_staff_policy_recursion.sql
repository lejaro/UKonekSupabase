-- ==============================================================================
-- Migration: 20260910170000_fix_staff_policy_recursion.sql
-- Description: Fix PostgreSQL 42P17 "infinite recursion detected in policy for relation 'staff'"
--              by making is_active_staff() and is_admin() bypass row_security locally
--              when verifying staff credentials, and cleaning up self-referencing policies.
-- ==============================================================================

-- 1. Redefine is_active_staff() with row_security = off to eliminate recursion
CREATE OR REPLACE FUNCTION public.is_active_staff()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_staff boolean;
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
  ) INTO v_is_staff;
  RETURN coalesce(v_is_staff, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_active_staff() TO authenticated, anon;

-- 2. Redefine is_admin() with row_security = off to eliminate recursion
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
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
    AND lower(trim(coalesce(role, ''))) = 'admin'
    AND lower(trim(coalesce(status, ''))) = 'active'
  ) INTO v_is_admin;
  RETURN coalesce(v_is_admin, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon;

-- 3. Clean up and set non-recursive policies on public.staff
DROP POLICY IF EXISTS staff_select_active_staff ON public.staff;
DROP POLICY IF EXISTS staff_select_own ON public.staff;
DROP POLICY IF EXISTS staff_select_policy ON public.staff;

CREATE POLICY staff_select_policy
  ON public.staff FOR SELECT
  USING (
    auth_user_id = auth.uid()
    OR (
      auth.jwt()->>'email' IS NOT NULL
      AND lower(trim(email)) = lower(trim(auth.jwt()->>'email'))
    )
    OR public.is_active_staff()
  );

-- 4. Clean up and set non-recursive policies on public.citizens
DROP POLICY IF EXISTS citizens_select_active_staff ON public.citizens;

CREATE POLICY citizens_select_active_staff
  ON public.citizens FOR SELECT
  USING (
    public.is_active_staff()
  );
