-- Migration: Allow citizens to update their own profile row

DROP POLICY IF EXISTS citizens_update_own ON public.citizens;

CREATE POLICY citizens_update_own
  ON public.citizens FOR UPDATE
  USING ( auth_user_id = auth.uid() )
  WITH CHECK ( auth_user_id = auth.uid() );
