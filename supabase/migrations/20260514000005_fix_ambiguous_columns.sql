-- ───────────────────────────────────────────────────────────────────────────
-- FIX: AMBIGUOUS COLUMN REFERENCES IN QUEUE FUNCTIONS
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.create_queue_ticket(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.get_my_queue_dashboard();

-- 1. Fix create_queue_ticket
CREATE OR REPLACE FUNCTION public.create_queue_ticket(
  p_service_key text,
  p_service_label text,
  p_citizen_type text,
  p_reason text DEFAULT NULL,
  p_symptoms text DEFAULT NULL
)
RETURNS TABLE (
  r_id bigint,
  r_queue_number integer,
  r_ticket_code text,
  r_service_key text,
  r_service_label text,
  r_citizen_type text,
  r_status text,
  r_estimated_wait_minutes integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id bigint;
  v_num integer;
  v_code text;
  v_key text;
  v_lbl text;
  v_type text;
  v_stat text;
  v_cid bigint;
  v_next integer;
  v_wait integer;
BEGIN
  -- Get citizen
  SELECT c.id INTO v_cid FROM public.citizens c WHERE c.auth_user_id = auth.uid() LIMIT 1;
  IF v_cid IS NULL THEN RAISE EXCEPTION 'Citizen profile not found.'; END IF;

  v_key := lower(trim(coalesce(p_service_key, '')));
  v_lbl := trim(coalesce(p_service_label, ''));
  v_type := lower(trim(coalesce(p_citizen_type, 'regular')));

  -- Calculate next
  SELECT coalesce(max(q.queue_number), 0) + 1 INTO v_next
  FROM public.queue_tickets q WHERE q.queue_date = public.get_manila_date() AND q.service_key = v_key;

  v_code := format('Q-%s-%s-%s', to_char(public.get_manila_date(), 'YYYYMMDD'), upper(substr(regexp_replace(v_key, '[^a-z0-9]+', '', 'g'), 1, 4)), lpad(v_next::text, 3, '0'));

  -- Insert
  INSERT INTO public.queue_tickets (queue_date, service_key, service_label, queue_number, ticket_code, citizen_id, citizen_type, reason, symptoms, status)
  VALUES (public.get_manila_date(), v_key, v_lbl, v_next, v_code, v_cid, v_type, nullif(trim(coalesce(p_reason, '')), ''), nullif(trim(coalesce(p_symptoms, '')), ''), 'waiting')
  RETURNING public.queue_tickets.id, public.queue_tickets.queue_number, public.queue_tickets.ticket_code INTO v_id, v_num, v_code;

  -- Calculate wait
  SELECT count(*)::integer INTO v_wait FROM public.queue_tickets q WHERE q.queue_date = public.get_manila_date() AND q.service_key = v_key AND q.status IN ('waiting', 'serving') AND q.queue_number < v_id;

  RETURN QUERY SELECT v_id, v_num, v_code, v_key, v_lbl, v_type, 'waiting'::text, (v_wait * 10);
END;
$$;

-- 2. Fix get_my_queue_dashboard
CREATE OR REPLACE FUNCTION public.get_my_queue_dashboard()
RETURNS TABLE (
  r_queue_id bigint,
  r_service_key text,
  r_service_label text,
  r_ticket_code text,
  r_my_queue_number integer,
  r_currently_serving_queue_number integer,
  r_estimated_wait_minutes integer,
  r_status text,
  r_queue_date date
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cid bigint;
  v_qid bigint;
  v_key text;
  v_lbl text;
  v_code text;
  v_num integer;
  v_stat text;
  v_srv integer;
  v_wait integer;
  v_date date;
BEGIN
  SELECT c.id INTO v_cid FROM public.citizens c WHERE c.auth_user_id = auth.uid() LIMIT 1;
  IF v_cid IS NULL THEN RETURN; END IF;

  SELECT q.id, q.service_key, q.service_label, q.ticket_code, q.queue_number, q.status, q.queue_date
  INTO v_qid, v_key, v_lbl, v_code, v_num, v_stat, v_date
  FROM public.queue_tickets q WHERE q.citizen_id = v_cid AND q.queue_date = public.get_manila_date() AND q.status IN ('waiting', 'serving')
  ORDER BY q.created_at DESC LIMIT 1;

  IF v_qid IS NULL THEN RETURN; END IF;

  SELECT min(q.queue_number) INTO v_srv FROM public.queue_tickets q WHERE q.queue_date = v_date AND q.service_key = v_key AND q.status = 'serving';
  SELECT count(*)::integer INTO v_wait FROM public.queue_tickets q WHERE q.queue_date = v_date AND q.service_key = v_key AND q.status = 'waiting' AND q.queue_number < v_num;

  RETURN QUERY SELECT v_qid, v_key, v_lbl, v_code, v_num, v_srv, (coalesce(v_wait, 0) + CASE WHEN v_srv IS NOT NULL AND v_srv < v_num THEN 1 ELSE 0 END) * 10, v_stat, v_date;
END;
$$;
