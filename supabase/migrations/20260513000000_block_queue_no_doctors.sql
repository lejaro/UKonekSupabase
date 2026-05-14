-- ───────────────────────────────────────────────────────────────────────────
-- 1. Function to check if any doctor is active (Available or On Break)
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_any_doctor_available()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Check if any doctor or admin is active and available/on_break
    RETURN EXISTS (
        SELECT 1 FROM public.staff
        WHERE lower(trim(coalesce(role, ''))) IN ('doctor', 'admin')
          AND lower(trim(coalesce(status, ''))) = 'active'
          AND lower(trim(coalesce(availability_status, 'available'))) IN ('available', 'on_break')
    );
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Update get_queue_limiter_status to include doctor availability
DROP FUNCTION IF EXISTS public.get_queue_limiter_status();

-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_queue_limiter_status()
RETURNS TABLE (
    enabled BOOLEAN,
    daily_limit INTEGER,
    today_count INTEGER,
    limit_reached BOOLEAN,
    remaining_slots INTEGER,
    doctors_available BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_enabled BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
    v_reached BOOLEAN;
    v_remaining INTEGER;
    v_docs_avail BOOLEAN;
BEGIN
    v_enabled := is_queue_limiter_enabled();
    v_limit := get_daily_ticket_limit();
    v_count := get_today_ticket_count();
    v_reached := is_daily_ticket_limit_reached();
    v_remaining := GREATEST(0, v_limit - v_count);
    v_docs_avail := is_any_doctor_available();
    
    RETURN QUERY SELECT v_enabled, v_limit, v_count, v_reached, v_remaining, v_docs_avail;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Update create_queue_ticket to block if no doctors are available
DROP FUNCTION IF EXISTS public.create_queue_ticket(text, text, text, text, text);

-- ───────────────────────────────────────────────────────────────────────────

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
  v_docs_avail boolean;
BEGIN
  v_today := public.get_manila_date();

  -- Check if any doctor is available or on break
  v_docs_avail := public.is_any_doctor_available();
  IF NOT v_docs_avail THEN
    RAISE EXCEPTION 'No doctors are currently available. Please try again later when clinic staff are online.';
  END IF;

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

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Re-grant permissions
-- ───────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.is_any_doctor_available() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_queue_limiter_status() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.create_queue_ticket(text, text, text, text, text) TO authenticated;
