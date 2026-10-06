-- Decommission legacy booking and appointments system.
-- The clinic operates exclusively via Live Queueing (queue_tickets) and Follow-ups.
-- This migration cleanly drops the orphaned appointments table and its associated RPC functions.

-- 1. Drop legacy appointment RPC functions
DROP FUNCTION IF EXISTS public.book_appointment(bigint, bigint, date, time, text);
DROP FUNCTION IF EXISTS public.get_available_doctor_slots(bigint, date, date);
DROP FUNCTION IF EXISTS public.list_my_appointments();
DROP FUNCTION IF EXISTS public.list_doctor_appointments(varchar, date, date);
DROP FUNCTION IF EXISTS public.list_all_appointments(varchar, date, date, bigint);

-- 2. Drop legacy appointments table, cascade indexes and RLS policies
DROP TABLE IF EXISTS public.appointments CASCADE;
