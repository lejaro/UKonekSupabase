-- Fix: Include 'on_call' status in mobile queue dashboard to prevent ticket from disappearing
-- when patient is being assessed for vitals.

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
  -- Get active citizen ID
  SELECT c.id INTO v_cid FROM public.citizens c WHERE c.auth_user_id = auth.uid() LIMIT 1;
  IF v_cid IS NULL THEN RETURN; END IF;

  -- Find the latest active ticket for today (Waiting, On Call, or Serving)
  SELECT q.id, q.service_key, q.service_label, q.ticket_code, q.queue_number, q.status, q.queue_date
  INTO v_qid, v_key, v_lbl, v_code, v_num, v_stat, v_date
  FROM public.queue_tickets q 
  WHERE q.citizen_id = v_cid 
    AND q.queue_date = public.get_manila_date() 
    AND q.status IN ('waiting', 'on_call', 'serving')
  ORDER BY q.created_at DESC LIMIT 1;

  IF v_qid IS NULL THEN RETURN; END IF;

  -- Get the current number being served for this service
  -- (Min queue number in 'serving' or 'on_call' status)
  SELECT min(q.queue_number) INTO v_srv 
  FROM public.queue_tickets q 
  WHERE q.queue_date = v_date 
    AND q.service_key = v_key 
    AND q.status IN ('serving', 'on_call');

  -- Count tickets in 'waiting' that are ahead of this patient
  SELECT count(*)::integer INTO v_wait 
  FROM public.queue_tickets q 
  WHERE q.queue_date = v_date 
    AND q.service_key = v_key 
    AND q.status = 'waiting' 
    AND q.queue_number < v_num;

  -- Return query results
  RETURN QUERY SELECT 
    v_qid, 
    v_key, 
    v_lbl, 
    v_code, 
    v_num, 
    v_srv, 
    (coalesce(v_wait, 0) + CASE WHEN v_srv IS NOT NULL AND v_srv < v_num THEN 1 ELSE 0 END) * 10, 
    v_stat, 
    v_date;
END;
$$;

-- Also update create_queue_ticket to be consistent if needed, 
-- though it only returns the initial 'waiting' state.
