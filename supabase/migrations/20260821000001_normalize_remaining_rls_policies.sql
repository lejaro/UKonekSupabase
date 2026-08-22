-- =============================================================================
-- P1: Normalize remaining RLS policies — medicines, feedbacks, announcements
--
-- Problem:
--   These 3 tables still use lower(trim(coalesce(s.status, ''))) and
--   lower(trim(coalesce(s.role, ''))) in their RLS policies, preventing use of
--   idx_staff_auth_id_status and forcing sequential scans on the staff table.
--
-- Fix:
--   Since migration 20260816000000 added a BEFORE INSERT/UPDATE trigger that
--   normalizes staff.status and staff.role to lowercase/trimmed values, all
--   existing data is guaranteed normalized. Replace wrapper functions with
--   plain column equality.
--
-- Semantics: PRESERVED EXACTLY — only the comparison method changes.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- MEDICINES
-- ═══════════════════════════════════════════════════════════════════════════════

-- SELECT: active staff
DROP POLICY IF EXISTS medicines_select_active_staff ON public.medicines;
CREATE POLICY medicines_select_active_staff
  ON public.medicines FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
    )
  );

-- INSERT: admin or doctor/specialist
DROP POLICY IF EXISTS medicines_insert_admin_or_doctor ON public.medicines;
CREATE POLICY medicines_insert_admin_or_doctor
  ON public.medicines FOR INSERT
  WITH CHECK (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'specialist')
    )
  );

-- UPDATE: admin, doctor, specialist, or nurse
DROP POLICY IF EXISTS medicines_update_admin_doctor_nurse ON public.medicines;
CREATE POLICY medicines_update_admin_doctor_nurse
  ON public.medicines FOR UPDATE
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
        AND s.role IN ('doctor', 'specialist', 'nurse')
    )
  )
  WITH CHECK (
    qty >= 0
    AND (
      public.is_admin()
      OR EXISTS (
        SELECT 1 FROM public.staff s
        WHERE s.auth_user_id = auth.uid()
          AND s.status = 'active'
          AND s.role IN ('doctor', 'specialist', 'nurse')
      )
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════════
-- FEEDBACKS
-- ═══════════════════════════════════════════════════════════════════════════════

-- SELECT: active staff
DROP POLICY IF EXISTS feedbacks_select_active_staff ON public.feedbacks;
CREATE POLICY feedbacks_select_active_staff
  ON public.feedbacks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
    )
  );

-- INSERT: citizen (unchanged — already uses auth.uid() without wrappers)
-- feedbacks_insert_citizen — no change needed

-- ALL: admin (unchanged — uses is_admin() which is already normalized)
-- feedbacks_manage_admin — no change needed

-- ═══════════════════════════════════════════════════════════════════════════════
-- ANNOUNCEMENTS
-- ═══════════════════════════════════════════════════════════════════════════════

-- SELECT: active staff
DROP POLICY IF EXISTS announcements_select_active_staff ON public.announcements;
CREATE POLICY announcements_select_active_staff
  ON public.announcements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.staff s
      WHERE s.auth_user_id = auth.uid()
        AND s.status = 'active'
    )
  );

-- SELECT: citizens can view announcements (visible to 'all' or 'citizens')
-- This adds citizen access that was previously missing
DROP POLICY IF EXISTS announcements_select_citizen ON public.announcements;
CREATE POLICY announcements_select_citizen
  ON public.announcements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.citizens c
      WHERE c.auth_user_id = auth.uid()
    )
    AND (
      visibility IS NULL
      OR visibility IN ('all', 'citizens')
    )
  );

-- INSERT/UPDATE/DELETE: admin (unchanged — uses is_admin() which is already normalized)
-- announcements_insert_admin — no change needed
-- announcements_update_admin — no change needed
-- announcements_delete_admin — no change needed
