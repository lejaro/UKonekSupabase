-- Update daily ticket limiter logic to only count served or currently serving tickets.
-- This ensures that "waiting" or "cancelled" tickets do not deduct from the daily limit.

CREATE OR REPLACE FUNCTION public.get_today_ticket_count()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT count(*)::integer
  FROM public.queue_tickets
  WHERE queue_date = public.get_manila_date()
    AND lower(trim(coalesce(status, ''))) IN ('serving', 'completed', 'on_call');
$$;

COMMENT ON FUNCTION public.get_today_ticket_count() IS 'Returns the number of tickets that have been served or are currently being served today. Waiting and cancelled tickets are excluded from the daily limit count.';
