-- Fix cancel_my_queue_ticket to reliably cancel active waiting/on_call tickets regardless of timezone date boundaries.
CREATE OR REPLACE FUNCTION public.cancel_my_queue_ticket()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_citizen_id bigint;
BEGIN
  -- 1. Identify active citizen
  SELECT c.id
  INTO v_citizen_id
  FROM public.citizens c
  WHERE c.auth_user_id = auth.uid()
  LIMIT 1;

  IF v_citizen_id IS NULL THEN
    RETURN false;
  END IF;

  -- 2. Update all active waiting or on_call queue tickets for this citizen to cancelled
  UPDATE public.queue_tickets
  SET status = 'cancelled',
      updated_at = now()
  WHERE citizen_id = v_citizen_id
    AND lower(trim(both FROM coalesce(status, ''))) IN ('waiting', 'on_call');

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_my_queue_ticket() TO authenticated;
