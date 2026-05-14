-- ───────────────────────────────────────────────────────────────────────────
-- WIPE QUEUE TICKETS (FOR CLEAN SYSTEM RESET)
-- ───────────────────────────────────────────────────────────────────────────

-- 1. Wipe all queue tickets
DELETE FROM public.queue_tickets;

-- 2. Reset the sequence
ALTER SEQUENCE IF EXISTS public.queue_tickets_id_seq RESTART WITH 1;

DO $$ BEGIN
  RAISE NOTICE 'All queue tickets have been wiped.';
END $$;
