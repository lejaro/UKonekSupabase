-- ───────────────────────────────────────────────────────────────────────────
-- FIX REMAINING TIMEZONE DISCREPANCIES (ASIA/MANILA)
-- ───────────────────────────────────────────────────────────────────────────

-- 1. Update delete_old_pending_queue_tickets to use Manila Date
CREATE OR REPLACE FUNCTION public.delete_old_pending_queue_tickets()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delete queue tickets created before today (Manila Time)
  DELETE FROM public.queue_tickets
  WHERE status IN ('waiting', 'on_call')
    AND queue_date < public.get_manila_date();
  
  RAISE NOTICE 'Deleted old pending queue tickets from previous days at %', now() AT TIME ZONE 'Asia/Manila';
END;
$$;

-- 2. Update check_and_delete_old_queue_tickets (Trigger fallback)
CREATE OR REPLACE FUNCTION public.check_and_delete_old_queue_tickets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If there are old pending tickets (before Today Manila), delete them
  DELETE FROM public.queue_tickets
  WHERE status IN ('waiting', 'on_call')
    AND queue_date < public.get_manila_date();
    
  RETURN NEW;
END;
$$;

-- 3. Adjust cron schedule for midnight Manila time
-- 00:00 AM Manila = 04:00 PM UTC (of previous day)
-- Schedule: 0 16 * * *
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('delete-old-pending-queue-tickets');
    PERFORM cron.schedule(
      'delete-old-pending-queue-tickets',
      '0 16 * * *',
      'SELECT public.delete_old_pending_queue_tickets();'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not reschedule cron job: %', SQLERRM;
  END;
END;
$$;

-- 4. Update Medicine Schedule helper (if it exists)
-- Some migrations might have used now() for issued_at or similar.
-- We ensure future inserts into medicine_intake_logs default to Manila time in actual_time
-- if not provided, though we handle it in Dart now.
ALTER TABLE public.medicine_intake_logs 
  ALTER COLUMN actual_time SET DEFAULT now(); -- Keep as timestamptz

-- Ensure the Manila Date function is used in list_queue_tickets_for_staff
CREATE OR REPLACE FUNCTION public.list_queue_tickets_for_staff(
  p_date date DEFAULT NULL,
  p_limit integer DEFAULT 200
)
RETURNS TABLE (
  id bigint,
  queue_date date,
  service_key text,
  service_label text,
  queue_number integer,
  ticket_code text,
  status text,
  citizen_id bigint,
  citizen_firstname text,
  citizen_surname text,
  citizen_email text,
  citizen_date_of_birth date,
  citizen_sex text,
  created_at timestamptz,
  served_at timestamptz,
  completed_at timestamptz
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN QUERY
  SELECT 
    q.id,
    q.queue_date,
    q.service_key,
    q.service_label,
    q.queue_number,
    q.ticket_code,
    lower(trim(q.status)) as status,
    q.citizen_id,
    c.firstname as citizen_firstname,
    c.surname as citizen_surname,
    c.email as citizen_email,
    c.date_of_birth as citizen_date_of_birth,
    c.sex as citizen_sex,
    q.created_at,
    q.served_at,
    q.completed_at
  FROM public.queue_tickets q
  LEFT JOIN public.citizens c ON c.id = q.citizen_id
  WHERE 
    lower(trim(coalesce(q.status, ''))) NOT IN ('cancelled', 'completed')
    AND (p_date IS NULL OR q.queue_date = p_date)
  ORDER BY 
    CASE WHEN q.queue_date = public.get_manila_date() THEN 0 ELSE 1 END ASC,
    q.queue_number ASC
  LIMIT p_limit;
END;
$$;
