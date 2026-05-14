-- ───────────────────────────────────────────────────────────────────────────
-- REMOVE DATABASE LEVEL QUEUE BLOCKING
-- ───────────────────────────────────────────────────────────────────────────
-- Rationale: The "No Doctors Available" check should be enforced at the UI level
-- to guide users, but the database should allow creation (e.g., for back-office
-- entries or pre-registration).
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_queue_ticket(text, text, text, text, text);

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

  -- Note: The doctor availability check (is_any_doctor_available) 
  -- is now handled by the frontend via get_queue_limiter_status.
  -- We no longer raise an exception here to allow more flexibility.

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

GRANT EXECUTE ON FUNCTION public.create_queue_ticket(text, text, text, text, text) TO authenticated;
