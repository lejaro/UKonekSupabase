-- =============================================================================
-- P0: Harden vital_signs & lab_orders RLS
--
-- Problem:
--   Both tables have USING(true) policies, allowing any authenticated user
--   (including citizens) to read, insert, update, and delete all records.
--
-- Fix:
--   Replace with role-specific policies using normalized column equality
--   (staff.status / staff.role are guaranteed lowercase by the normalization
--   trigger from migration 20260816000000).
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- VITAL SIGNS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop overly-permissive policies
DROP POLICY IF EXISTS "Allow staff to insert vital signs" ON public.vital_signs;
DROP POLICY IF EXISTS "Allow staff to view vital signs" ON public.vital_signs;

-- SELECT: active doctors and nurses can view all vital signs
CREATE POLICY vital_signs_select_staff
  ON public.vital_signs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  );

-- SELECT: citizens can view their own vital signs
CREATE POLICY vital_signs_select_own_citizen
  ON public.vital_signs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.citizens c
      WHERE c.auth_user_id = auth.uid()
        AND c.id = vital_signs.citizen_id
    )
  );

-- INSERT: only active nurses and doctors can record vital signs
CREATE POLICY vital_signs_insert_staff
  ON public.vital_signs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  );

-- UPDATE: only active nurses and doctors can update vital signs
CREATE POLICY vital_signs_update_staff
  ON public.vital_signs FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════════
-- LAB ORDERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop overly-permissive policies
DROP POLICY IF EXISTS "Allow staff to view lab orders" ON public.lab_orders;
DROP POLICY IF EXISTS "Allow staff to manage lab orders" ON public.lab_orders;

-- SELECT: any active staff can view lab orders
CREATE POLICY lab_orders_select_staff
  ON public.lab_orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
    )
  );

-- INSERT: only doctors can create lab orders
CREATE POLICY lab_orders_insert_doctor
  ON public.lab_orders FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role = 'doctor'
    )
  );

-- UPDATE: active doctors and nurses can update lab orders (status, results)
CREATE POLICY lab_orders_update_staff
  ON public.lab_orders FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'nurse')
    )
  );

-- DELETE: admin only (doctors and nurses with admin access)
CREATE POLICY lab_orders_delete_admin
  ON public.lab_orders FOR DELETE
  USING (public.is_admin());
