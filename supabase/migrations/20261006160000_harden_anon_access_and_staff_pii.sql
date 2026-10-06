-- Migration: 20261006160000_harden_anon_access_and_staff_pii.sql
-- Description: Revoke anonymous access to public.staff PII and public.system_config.
--              Provide dedicated, secure RPC for staff login identifier resolution.

-- ============================================================================
-- 1. SECURE STAFF LOGIN IDENTIFIER RESOLUTION RPC
-- ============================================================================
-- Replaces direct anonymous table querying on public.staff during login.
-- Prevents full table dumps of doctor/nurse PII (birthday, email, employee ID).
CREATE OR REPLACE FUNCTION public.resolve_staff_login_email(p_identifier text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_clean text;
BEGIN
  IF p_identifier IS NULL OR length(trim(p_identifier)) = 0 THEN
    RETURN NULL;
  END IF;

  v_clean := lower(trim(p_identifier));

  -- Look up email strictly by exact case-insensitive username or employee_id
  SELECT s.email INTO v_email
  FROM public.staff s
  WHERE lower(trim(s.username)) = v_clean
     OR lower(trim(s.employee_id)) = v_clean
  LIMIT 1;

  RETURN v_email;
END;
$$;

COMMENT ON FUNCTION public.resolve_staff_login_email(text) IS
  'Securely resolves a staff username or employee ID to their login email without exposing the staff table to anonymous users.';

-- Allow unauthenticated login screen as well as authenticated sessions to resolve login identifiers
GRANT EXECUTE ON FUNCTION public.resolve_staff_login_email(text) TO anon, authenticated;


-- ============================================================================
-- 2. HARDEN public.staff RLS (REMOVE ANONYMOUS ACCESS)
-- ============================================================================

-- Drop all existing select policies that granted anonymous access
DROP POLICY IF EXISTS staff_select_citizens_view_doctors ON public.staff;
DROP POLICY IF EXISTS staff_select_unified ON public.staff;

-- Recreate staff_select_unified strictly TO authenticated users
CREATE POLICY staff_select_unified
  ON public.staff FOR SELECT
  TO authenticated
  USING (
    -- A. Own profile
    auth_user_id = auth.uid()
    OR (auth.jwt()->>'email' IS NOT NULL AND lower(trim(email)) = lower(trim(auth.jwt()->>'email')))
    -- B. Active clinical staff (doctors & nurses) visible to authenticated citizens and staff
    OR (lower(coalesce(status, '')) = 'active' AND lower(coalesce(role, '')) IN ('doctor', 'nurse'))
    -- C. Admin check via JWT metadata or is_admin() function
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
    OR public.is_admin()
  );

COMMENT ON POLICY staff_select_unified ON public.staff IS
  'Restricts staff table access to authenticated users only. Blocks unauthorized anonymous scraping of personnel PII.';

-- Explicitly revoke direct SELECT on staff from the anon role
REVOKE SELECT ON TABLE public.staff FROM anon;


-- ============================================================================
-- 3. HARDEN public.system_config RLS (RESTRICT TO ADMINS)
-- ============================================================================

DROP POLICY IF EXISTS system_config_read_policy ON public.system_config;

-- Recreate policy strictly for authenticated administrators
CREATE POLICY system_config_read_policy
  ON public.system_config FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR ((auth.jwt()->'user_metadata'->>'role') = 'admin')
    OR ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  );

COMMENT ON POLICY system_config_read_policy ON public.system_config IS
  'Restricts direct system configuration table reads to authenticated administrators only.';

-- Explicitly revoke table privileges from anon role
REVOKE ALL ON TABLE public.system_config FROM anon;
