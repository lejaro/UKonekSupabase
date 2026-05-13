-- Comprehensive Timezone Consistency Fix (Asia/Manila)
-- This migration ensures that all "Today" checks use Manila time (UTC+8) instead of UTC.
-- This prevents tickets and schedules from "disappearing" or being misdated between 12:00 AM and 8:00 AM local time.

-- 1. Helper function for consistent local date
CREATE OR REPLACE FUNCTION public.get_manila_date()
RETURNS date
LANGUAGE sql
STABLE
AS $$
  SELECT (now() AT TIME ZONE 'Asia/Manila')::date;
$$;

-- 2. Update queue_tickets table default
ALTER TABLE public.queue_tickets 
  ALTER COLUMN queue_date SET DEFAULT (now() AT TIME ZONE 'Asia/Manila')::date;

-- 3. Update create_queue_ticket (Citizen side)
CREATE OR REPLACE FUNCTION public.create_queue_ticket(
  p_service_key text,
  p_service_label text,
  p_citizen_type text,
  p_reason text DEFAULT NULL,
  p_symptoms text DEFAULT NULL
)
RETURNS TABLE (
  id bigint,
  queue_number integer,
  ticket_code text,
  service_key text,
  service_label text,
  citizen_type text,
  status text,
  estimated_wait_minutes integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen_id bigint;
  v_today date;
  v_next_number integer;
  v_ticket_code text;
  v_waiting_ahead integer;
BEGIN
  v_today := public.get_manila_date();

  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
  LIMIT 1;

  IF v_citizen_id IS NULL THEN
    RAISE EXCEPTION 'Citizen profile not found for current session.';
  END IF;

  -- Limiter check
  IF public.is_daily_ticket_limit_reached() THEN
    RAISE EXCEPTION 'Daily queue ticket limit reached. Please try again tomorrow.';
  END IF;

  SELECT coalesce(max(q.queue_number), 0) + 1
  INTO v_next_number
  FROM public.queue_tickets q
  WHERE q.queue_date = v_today
    AND q.service_key = lower(trim(p_service_key));

  v_ticket_code := format(
    'Q-%s-%s-%s',
    to_char(v_today, 'YYYYMMDD'),
    upper(substr(regexp_replace(lower(trim(p_service_key)), '[^a-z0-9]+', '', 'g'), 1, 4)),
    lpad(v_next_number::text, 3, '0')
  );

  INSERT INTO public.queue_tickets (
    queue_date, service_key, service_label, queue_number, ticket_code,
    citizen_id, citizen_type, reason, symptoms, status
  )
  VALUES (
    v_today, lower(trim(p_service_key)), trim(p_service_label), v_next_number, v_ticket_code,
    v_citizen_id, lower(trim(p_citizen_type)), nullif(trim(p_reason), ''), nullif(trim(p_symptoms), ''), 'waiting'
  )
  RETURNING
    queue_tickets.id, queue_tickets.queue_number, queue_tickets.ticket_code,
    queue_tickets.service_key, queue_tickets.service_label, queue_tickets.citizen_type, queue_tickets.status
  INTO id, queue_number, ticket_code, service_key, service_label, citizen_type, status;

  SELECT count(*)::integer INTO v_waiting_ahead
  FROM public.queue_tickets q
  WHERE q.queue_date = v_today
    AND q.service_key = service_key
    AND lower(trim(coalesce(q.status, ''))) IN ('waiting', 'serving')
    AND q.queue_number < v_next_number;

  estimated_wait_minutes := greatest(0, v_waiting_ahead) * 10;
  RETURN NEXT;
END;
$$;

-- 4. Update get_my_queue_dashboard (Citizen Mobile side)
CREATE OR REPLACE FUNCTION public.get_my_queue_dashboard()
RETURNS TABLE (
  queue_id bigint,
  service_key text,
  service_label text,
  ticket_code text,
  my_queue_number integer,
  currently_serving_queue_number integer,
  estimated_wait_minutes integer,
  status text,
  queue_date date,
  is_on_call boolean,
  waiting_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen_id bigint;
  v_today date;
  v_rec record;
BEGIN
  v_today := public.get_manila_date();

  SELECT c.id INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
  LIMIT 1;

  IF v_citizen_id IS NULL THEN RETURN; END IF;

  -- Get the most recent active ticket
  SELECT q.* INTO v_rec
  FROM public.queue_tickets q
  WHERE q.citizen_id = v_citizen_id
    AND lower(trim(coalesce(q.status, ''))) IN ('waiting', 'on_call', 'serving')
    -- No hard date filter here to ensure visibility if UTC shifted,
    -- but we prioritize "today" or "recent".
  ORDER BY q.created_at DESC
  LIMIT 1;

  IF v_rec.id IS NULL THEN RETURN; END IF;

  queue_id := v_rec.id;
  service_key := v_rec.service_key;
  service_label := v_rec.service_label;
  ticket_code := v_rec.ticket_code;
  my_queue_number := v_rec.queue_number;
  status := v_rec.status;
  queue_date := v_rec.queue_date;
  is_on_call := (lower(trim(v_rec.status)) = 'on_call');

  SELECT min(q.queue_number) INTO currently_serving_queue_number
  FROM public.queue_tickets q
  WHERE q.queue_date = v_rec.queue_date
    AND q.service_key = v_rec.service_key
    AND lower(trim(coalesce(q.status, ''))) = 'serving';

  SELECT count(*)::integer INTO waiting_count
  FROM public.queue_tickets q
  WHERE q.queue_date = v_rec.queue_date
    AND q.service_key = v_rec.service_key
    AND lower(trim(coalesce(q.status, ''))) = 'waiting'
    AND q.queue_number < my_queue_number;

  estimated_wait_minutes := (coalesce(waiting_count, 0) + CASE WHEN currently_serving_queue_number IS NOT NULL AND currently_serving_queue_number < my_queue_number THEN 1 ELSE 0 END) * 10;
  
  -- Recalculate total waiting in lane
  SELECT count(*)::integer INTO waiting_count
  FROM public.queue_tickets q
  WHERE q.queue_date = v_rec.queue_date
    AND q.service_key = v_rec.service_key
    AND lower(trim(coalesce(q.status, ''))) = 'waiting';

  RETURN NEXT;
END;
$$;

-- 5. Update list_available_queue_services
CREATE OR REPLACE FUNCTION public.list_available_queue_services(
  p_date date DEFAULT NULL
)
RETURNS TABLE (
  service_key text,
  service_label text,
  doctor_count integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH source AS (
    SELECT lower(trim(coalesce(s.doctor_specialization, ''))) as specialization
    FROM public.doctor_schedules ds
    JOIN public.staff s ON s.id = ds.doctor_staff_id
    WHERE ds.schedule_date = coalesce(p_date, public.get_manila_date())
      AND lower(trim(coalesce(s.status, ''))) = 'active'
      AND lower(trim(coalesce(s.role, ''))) = 'doctor'
  )
  SELECT
    CASE
      WHEN specialization LIKE '%dental%' THEN 'dental'
      WHEN specialization LIKE '%prenatal%' OR specialization LIKE '%maternal%' OR specialization LIKE '%ob%' THEN 'prenatal'
      ELSE 'general_consultation'
    END as service_key,
    CASE
      WHEN specialization LIKE '%dental%' THEN 'Dental'
      WHEN specialization LIKE '%prenatal%' OR specialization LIKE '%maternal%' OR specialization LIKE '%ob%' THEN 'Prenatal'
      ELSE 'General Consultation'
    END as service_label,
    count(*)::integer as doctor_count
  FROM source
  GROUP BY 1, 2
  ORDER BY 2;
$$;

-- 6. Update get_today_ticket_count (Limiter)
CREATE OR REPLACE FUNCTION public.get_today_ticket_count()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT count(*)::integer
  FROM public.queue_tickets
  WHERE queue_date = public.get_manila_date();
$$;

-- 7. Update purge_completed_queue_tickets
CREATE OR REPLACE FUNCTION public.purge_completed_queue_tickets(
  p_queue_date date DEFAULT NULL,
  p_service_key text DEFAULT NULL,
  p_grace_seconds integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_date date;
  v_deleted_count integer := 0;
BEGIN
  v_target_date := coalesce(p_queue_date, public.get_manila_date());
  
  DELETE FROM public.queue_tickets q
  WHERE q.queue_date = v_target_date
    AND lower(trim(coalesce(q.status, ''))) IN ('completed', 'cancelled')
    AND (p_service_key IS NULL OR lower(trim(q.service_key)) = lower(trim(p_service_key)))
    AND (q.completed_at IS NULL OR q.completed_at < (now() - (p_grace_seconds || ' seconds')::interval));

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'deleted_count', v_deleted_count);
END;
$$;
