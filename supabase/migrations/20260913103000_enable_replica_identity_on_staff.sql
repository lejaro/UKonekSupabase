-- Ensure staff table has REPLICA IDENTITY FULL for Supabase Realtime updates
ALTER TABLE public.staff REPLICA IDENTITY FULL;
