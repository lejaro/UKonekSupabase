-- Final fix for queue visibility and timezone mismatch.
-- This migration simplifies the RPCs to ensure they always return active tickets when p_date is null.

-- 1. Update Staff Queue RPC (Table format is best for staff dashboard)
DROP FUNCTION IF EXISTS public.list_queue_tickets_for_staff(date, integer);

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
  -- Basic auth check
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
    q.status,
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
  ORDER BY q.queue_date ASC, q.queue_number ASC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_queue_tickets_for_staff(date, integer) TO authenticated;

-- 2. Update TV View RPC (JSON Bucket format is best for TV Display JS)
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
      AND (p_date IS NULL OR q.queue_date = p_date)
    ORDER BY q.queue_number ASC
  ) t;

  -- On-call tickets
  SELECT json_agg(t) INTO v_on_call
  FROM (
    SELECT q.id, q.queue_number, q.ticket_code, q.status, q.service_label, c.firstname as citizen_firstname
    FROM public.queue_tickets q
    LEFT JOIN public.citizens c ON c.id = q.citizen_id
    WHERE lower(trim(coalesce(q.status, ''))) = 'on_call'
      AND (p_date IS NULL OR q.queue_date = p_date)
    ORDER BY q.queue_number ASC
  ) t;

  -- Waiting tickets
  SELECT json_agg(t) INTO v_waiting
  FROM (
    SELECT q.id, q.queue_number, q.ticket_code, q.status, q.service_label, c.firstname as citizen_firstname
    FROM public.queue_tickets q
    LEFT JOIN public.citizens c ON c.id = q.citizen_id
    WHERE lower(trim(coalesce(q.status, ''))) = 'waiting'
      AND (p_date IS NULL OR q.queue_date = p_date)
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
