-- Update queue listing RPCs to be more robust across timezones
-- They now show all active tickets regardless of date, while still allowing date filtering if explicitly requested.

-- 1. Update list_queue_tickets_for_staff
CREATE OR REPLACE FUNCTION public.list_queue_tickets_for_staff(
  p_date date DEFAULT NULL,
  p_limit integer DEFAULT 200
)
RETURNS TABLE (
  id bigint,
  queue_date date,
  service_key text,
  reason text,
  symptoms text,
  queue_number integer,
  ticket_code text,
  service_label text,
  citizen_type text,
  status text,
  created_at timestamptz,
  served_at timestamptz,
  completed_at timestamptz,
  citizen_id bigint,
  citizen_firstname text,
  citizen_surname text,
  citizen_email text,
  citizen_date_of_birth date,
  citizen_sex text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile json;
  v_limit integer;
BEGIN
  v_profile := public.get_staff_profile();
  IF v_profile IS NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: active staff account required';
  END IF;

  v_limit := greatest(1, least(coalesce(p_limit, 200), 500));

  RETURN QUERY
  SELECT
    q.id,
    q.queue_date,
    q.service_key,
    q.reason,
    q.symptoms,
    q.queue_number,
    q.ticket_code,
    q.service_label,
    q.citizen_type,
    q.status,
    q.created_at,
    q.served_at,
    q.completed_at,
    c.id,
    c.firstname,
    c.surname,
    c.email,
    c.date_of_birth,
    c.sex
  FROM public.queue_tickets q
  LEFT JOIN public.citizens c ON c.id = q.citizen_id
  WHERE lower(trim(coalesce(q.status, ''))) NOT IN ('cancelled', 'completed')
    -- If p_date is provided, filter by it. If NULL, show all active tickets.
    AND (p_date IS NULL OR q.queue_date = p_date)
  ORDER BY q.queue_date ASC, q.queue_number ASC
  LIMIT v_limit;
END;
$$;

-- 2. Update get_tv_queue_display
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
  -- Currently serving tickets (regardless of date if p_date is NULL)
  SELECT json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status,
      'served_at',     q.served_at
    )
    ORDER BY q.queue_date ASC, q.queue_number ASC
  )
  INTO v_serving
  FROM public.queue_tickets q
  WHERE lower(trim(q.status)) = 'serving'
    AND (p_date IS NULL OR q.queue_date = p_date);

  -- On-call tickets
  SELECT json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status
    )
    ORDER BY q.queue_date ASC, q.queue_number ASC
  )
  INTO v_on_call
  FROM public.queue_tickets q
  WHERE lower(trim(q.status)) = 'on_call'
    AND (p_date IS NULL OR q.queue_date = p_date);

  -- Waiting tickets
  SELECT json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status,
      'citizen_type',  q.citizen_type
    )
    ORDER BY q.queue_date ASC, q.queue_number ASC
  )
  INTO v_waiting
  FROM public.queue_tickets q
  WHERE lower(trim(q.status)) = 'waiting'
    AND (p_date IS NULL OR q.queue_date = p_date);

  RETURN json_build_object(
    'serving',  coalesce(v_serving, '[]'::json),
    'on_call',  coalesce(v_on_call, '[]'::json),
    'waiting',  coalesce(v_waiting, '[]'::json),
    'as_of',    now()
  );
END;
$$;
