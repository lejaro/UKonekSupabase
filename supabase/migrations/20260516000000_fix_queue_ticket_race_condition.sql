-- ───────────────────────────────────────────────────────────────────────────
-- FIX: RACE CONDITION IN create_queue_ticket CAUSING DUPLICATE TICKET CODES
-- ───────────────────────────────────────────────────────────────────────────
-- Issue: When multiple users create tickets simultaneously, they can calculate
-- the same queue_number and ticket_code, causing duplicate key violations.
--
-- Solution: Use SELECT FOR UPDATE to lock the row during calculation, or use
-- a sequence-based approach with retry logic.
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
  v_cid bigint;
  v_next integer;
  v_wait integer;
  v_date date;
  v_retry_count integer := 0;
  v_max_retries integer := 5;
BEGIN
  -- Get citizen
  SELECT c.id INTO v_cid 
  FROM public.citizens c 
  WHERE c.auth_user_id = auth.uid() 
  LIMIT 1;
  
  IF v_cid IS NULL THEN 
    RAISE EXCEPTION 'Citizen profile not found.'; 
  END IF;

  -- Normalize inputs
  v_key := lower(trim(coalesce(p_service_key, '')));
  v_lbl := trim(coalesce(p_service_label, ''));
  v_type := lower(trim(coalesce(p_citizen_type, 'regular')));
  v_date := public.get_manila_date();

  -- Retry loop to handle race conditions
  <<retry_loop>>
  LOOP
    BEGIN
      -- Lock the queue for this service/date to prevent race conditions
      -- This ensures only one transaction can calculate the next number at a time
      PERFORM pg_advisory_xact_lock(
        hashtext(v_key || '::' || v_date::text)
      );

      -- Calculate next queue number with lock held
      SELECT coalesce(max(q.queue_number), 0) + 1 
      INTO v_next
      FROM public.queue_tickets q 
      WHERE q.queue_date = v_date 
        AND q.service_key = v_key;

      -- Generate unique ticket code
      v_code := format(
        'Q-%s-%s-%s', 
        to_char(v_date, 'YYYYMMDD'), 
        upper(substr(regexp_replace(v_key, '[^a-z0-9]+', '', 'g'), 1, 4)), 
        lpad(v_next::text, 3, '0')
      );

      -- Insert ticket
      INSERT INTO public.queue_tickets (
        queue_date, 
        service_key, 
        service_label, 
        queue_number, 
        ticket_code, 
        citizen_id, 
        citizen_type, 
        reason, 
        symptoms, 
        status
      )
      VALUES (
        v_date, 
        v_key, 
        v_lbl, 
        v_next, 
        v_code, 
        v_cid, 
        v_type, 
        nullif(trim(coalesce(p_reason, '')), ''), 
        nullif(trim(coalesce(p_symptoms, '')), ''), 
        'waiting'
      )
      RETURNING 
        public.queue_tickets.id, 
        public.queue_tickets.queue_number, 
        public.queue_tickets.ticket_code 
      INTO v_id, v_num, v_code;

      -- Success - exit retry loop
      EXIT retry_loop;

    EXCEPTION
      WHEN unique_violation THEN
        -- Duplicate key error - retry with new number
        v_retry_count := v_retry_count + 1;
        
        IF v_retry_count >= v_max_retries THEN
          RAISE EXCEPTION 'Failed to create queue ticket after % attempts. Please try again.', v_max_retries;
        END IF;
        
        -- Small delay before retry (10ms * retry_count)
        PERFORM pg_sleep(0.01 * v_retry_count);
        
        -- Loop will retry with advisory lock
        CONTINUE retry_loop;
    END;
  END LOOP retry_loop;

  -- Calculate estimated wait time
  SELECT count(*)::integer 
  INTO v_wait 
  FROM public.queue_tickets q 
  WHERE q.queue_date = v_date 
    AND q.service_key = v_key 
    AND q.status IN ('waiting', 'serving') 
    AND q.queue_number < v_num;

  -- Return the created ticket
  RETURN QUERY 
  SELECT 
    v_id, 
    v_num, 
    v_code, 
    v_key, 
    v_lbl, 
    v_type, 
    'waiting'::text, 
    (v_wait * 10);
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_queue_ticket(text, text, text, text, text) TO authenticated;

-- Add comment explaining the fix
COMMENT ON FUNCTION public.create_queue_ticket IS 
'Creates a queue ticket with race condition protection using advisory locks. 
Includes retry logic to handle concurrent ticket creation attempts.';
