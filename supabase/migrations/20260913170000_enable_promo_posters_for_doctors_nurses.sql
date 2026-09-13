-- Migration: 20260913170000_enable_promo_posters_for_doctors_nurses.sql
-- Description: Allow doctors and nurses to create promo posters with photos / image URLs,
--              create the 'promo-banners' storage bucket, and expose image_url for mobile app.

BEGIN;

-- 1. Add image_url column to announcements table
ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS image_url text;

-- 2. Helper function to check if caller is clinical staff (doctor, nurse, or admin)
CREATE OR REPLACE FUNCTION public.is_clinical_staff()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.auth_user_id = auth.uid()
      AND lower(coalesce(s.status, '')) = 'active'
      AND lower(coalesce(s.role, '')) IN ('doctor', 'nurse', 'admin')
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_clinical_staff() TO authenticated, anon;

-- 3. Update announcements RLS policies
-- Allow doctors, nurses, and admin to insert announcements/promo posters
DROP POLICY IF EXISTS announcements_insert_admin ON public.announcements;
DROP POLICY IF EXISTS announcements_insert_clinical_staff ON public.announcements;
CREATE POLICY announcements_insert_clinical_staff
  ON public.announcements
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_clinical_staff() OR public.is_admin()
  );

-- Allow doctors, nurses, and admin to update announcements/promo posters
DROP POLICY IF EXISTS announcements_update_admin ON public.announcements;
DROP POLICY IF EXISTS announcements_update_clinical_staff ON public.announcements;
CREATE POLICY announcements_update_clinical_staff
  ON public.announcements
  FOR UPDATE
  TO authenticated
  USING (
    public.is_clinical_staff() OR public.is_admin()
  )
  WITH CHECK (
    public.is_clinical_staff() OR public.is_admin()
  );

-- Allow doctors, nurses, and admin to delete announcements/promo posters
DROP POLICY IF EXISTS announcements_delete_admin ON public.announcements;
DROP POLICY IF EXISTS announcements_delete_clinical_staff ON public.announcements;
CREATE POLICY announcements_delete_clinical_staff
  ON public.announcements
  FOR DELETE
  TO authenticated
  USING (
    public.is_clinical_staff() OR public.is_admin()
  );

-- Ensure citizens and public authenticated users can view announcements
DROP POLICY IF EXISTS announcements_select_citizen ON public.announcements;
CREATE POLICY announcements_select_citizen
  ON public.announcements
  FOR SELECT
  TO authenticated, anon
  USING (
    visibility IS NULL
    OR lower(visibility) IN ('all', 'citizen', 'citizens')
    OR public.is_clinical_staff()
    OR public.is_admin()
  );

-- 4. Set up 'promo-banners' storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'promo-banners',
  'promo-banners',
  true,
  10485760, -- 10MB limit
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif'];

-- Storage RLS Policies for promo-banners bucket
DROP POLICY IF EXISTS "promo_banners_public_select" ON storage.objects;
CREATE POLICY "promo_banners_public_select"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'promo-banners');

DROP POLICY IF EXISTS "promo_banners_staff_insert" ON storage.objects;
CREATE POLICY "promo_banners_staff_insert"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'promo-banners'
    AND (public.is_clinical_staff() OR public.is_admin())
  );

DROP POLICY IF EXISTS "promo_banners_staff_update" ON storage.objects;
CREATE POLICY "promo_banners_staff_update"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'promo-banners'
    AND (public.is_clinical_staff() OR public.is_admin())
  );

DROP POLICY IF EXISTS "promo_banners_staff_delete" ON storage.objects;
CREATE POLICY "promo_banners_staff_delete"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'promo-banners'
    AND (public.is_clinical_staff() OR public.is_admin())
  );

COMMIT;
