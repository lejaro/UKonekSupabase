-- Final robustness fix for staff queue listing.
-- This ensures status is always trimmed and lowercase for frontend compatibility.

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
    -- Force status to be trimmed and lowercase for frontend matching
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
    -- Exclude finalized tickets
    lower(trim(coalesce(q.status, ''))) NOT IN ('cancelled', 'completed')
    -- If p_date is null, we show ALL active tickets (to fix UTC/Local mismatch)
    AND (p_date IS NULL OR q.queue_date = p_date)
  ORDER BY 
    -- Priority: Today's tickets first (Manila time), then by number
    CASE WHEN q.queue_date = public.get_manila_date() THEN 0 ELSE 1 END ASC,
    q.queue_number ASC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_queue_tickets_for_staff(date, integer) TO authenticated;
