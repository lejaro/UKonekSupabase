-- Add staff-safe queue ticket listing RPC to avoid client RLS issues.

CREATE OR REPLACE FUNCTION public.list_queue_tickets_for_staff(
  p_date date DEFAULT current_date,
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
    AND (p_date IS NULL OR q.queue_date = p_date)
  ORDER BY q.queue_number ASC
  LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_queue_tickets_for_staff(date, integer) TO authenticated;

COMMENT ON FUNCTION public.list_queue_tickets_for_staff(date, integer) IS
  'Returns active queue tickets with citizen info for staff dashboard use.';
