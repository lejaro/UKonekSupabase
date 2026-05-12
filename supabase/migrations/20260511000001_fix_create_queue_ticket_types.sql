-- Fix create_queue_ticket function to use correct data types
-- citizen_id should be BIGINT not UUID

DROP FUNCTION IF EXISTS create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_queue_ticket(
    p_service_key TEXT,
    p_service_label TEXT,
    p_citizen_type TEXT,
    p_reason TEXT,
    p_symptoms TEXT
)
RETURNS TABLE (
    id BIGINT,
    citizen_id BIGINT,
    queue_number INTEGER,
    ticket_code TEXT,
    service_key TEXT,
    service_label TEXT,
    citizen_type TEXT,
    reason TEXT,
    symptoms TEXT,
    status TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_citizen_id BIGINT;
    v_queue_number INTEGER;
    v_ticket_code TEXT;
    v_new_ticket_id BIGINT;
    v_limit_reached BOOLEAN;
BEGIN
    -- Get the authenticated user's citizen_id (BIGINT, not UUID)
    SELECT c.id INTO v_citizen_id
    FROM public.citizens c
    WHERE c.auth_user_id = auth.uid();

    IF v_citizen_id IS NULL THEN
        RAISE EXCEPTION 'Citizen profile not found for the authenticated user.';
    END IF;

    -- Check if citizen already has an active queue ticket today
    IF EXISTS (
        SELECT 1
        FROM public.queue_tickets qt
        WHERE qt.citizen_id = v_citizen_id
          AND qt.status IN ('waiting', 'on_call', 'serving')
          AND DATE(qt.created_at) = CURRENT_DATE
    ) THEN
        RAISE EXCEPTION 'You already have an active queue ticket for today.';
    END IF;

    -- Check if daily ticket limit is reached
    v_limit_reached := is_daily_ticket_limit_reached();
    
    IF v_limit_reached THEN
        RAISE EXCEPTION 'Daily queue ticket limit reached. Consultations for today are full. Please try again tomorrow or contact the clinic for assistance.';
    END IF;

    -- Generate the next queue number for today
    SELECT COALESCE(MAX(queue_number), 0) + 1
    INTO v_queue_number
    FROM public.queue_tickets
    WHERE DATE(created_at) = CURRENT_DATE;

    -- Generate a unique ticket code
    v_ticket_code := 'TKT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_queue_number::TEXT, 3, '0');

    -- Insert the new queue ticket
    INSERT INTO public.queue_tickets (
        citizen_id,
        queue_number,
        ticket_code,
        service_key,
        service_label,
        citizen_type,
        reason,
        symptoms,
        status
    )
    VALUES (
        v_citizen_id,
        v_queue_number,
        v_ticket_code,
        p_service_key,
        p_service_label,
        p_citizen_type,
        p_reason,
        p_symptoms,
        'waiting'
    )
    RETURNING queue_tickets.id INTO v_new_ticket_id;

    -- Return the newly created ticket
    RETURN QUERY
    SELECT
        qt.id,
        qt.citizen_id,
        qt.queue_number,
        qt.ticket_code,
        qt.service_key,
        qt.service_label,
        qt.citizen_type,
        qt.reason,
        qt.symptoms,
        qt.status,
        qt.created_at
    FROM public.queue_tickets qt
    WHERE qt.id = v_new_ticket_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Add comment
COMMENT ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Creates a new queue ticket with daily limit check. Uses BIGINT for citizen_id to match table structure.';
