-- Migration: Fix TV queue display date default to prevent stale/yesterday's tickets

DROP FUNCTION IF EXISTS public.get_tv_queue_display(date);

CREATE OR REPLACE FUNCTION public.get_tv_queue_display(
  p_date date DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_serving  json;
  v_on_call  json;
  v_waiting  json;
BEGIN
  -- Serving tickets
  SELECT json_agg(t) INTO v_serving
  FROM (
    SELECT q.id, q.queue_number, q.ticket_code, q.status, q.service_label, c.firstname as citizen_firstname
    FROM public.queue_tickets q
    LEFT JOIN public.citizens c ON c.id = q.citizen_id
    WHERE lower(trim(coalesce(q.status, ''))) = 'serving'
      AND q.queue_date = COALESCE(p_date, public.get_manila_date())
    ORDER BY q.queue_number ASC
  ) t;

  -- On-call tickets
  SELECT json_agg(t) INTO v_on_call
  FROM (
    SELECT q.id, q.queue_number, q.ticket_code, q.status, q.service_label, c.firstname as citizen_firstname
    FROM public.queue_tickets q
    LEFT JOIN public.citizens c ON c.id = q.citizen_id
    WHERE lower(trim(coalesce(q.status, ''))) = 'on_call'
      AND q.queue_date = COALESCE(p_date, public.get_manila_date())
    ORDER BY q.queue_number ASC
  ) t;

  -- Waiting tickets
  SELECT json_agg(t) INTO v_waiting
  FROM (
    SELECT q.id, q.queue_number, q.ticket_code, q.status, q.service_label, c.firstname as citizen_firstname
    FROM public.queue_tickets q
    LEFT JOIN public.citizens c ON c.id = q.citizen_id
    WHERE lower(trim(coalesce(q.status, ''))) = 'waiting'
      AND q.queue_date = COALESCE(p_date, public.get_manila_date())
    ORDER BY q.queue_number ASC
  ) t;

  RETURN json_build_object(
    'serving', COALESCE(v_serving, '[]'::json),
    'on_call', COALESCE(v_on_call, '[]'::json),
    'waiting', COALESCE(v_waiting, '[]'::json),
    'as_of',   now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_tv_queue_display(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tv_queue_display(date) TO anon;
