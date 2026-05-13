-- ═══════════════════════════════════════════════════════════════════════════
-- QUEUE TICKET DAILY LIMITER SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════
-- Purpose: Limit queue tickets to a maximum per day (default: 20)
-- Features:
--   - Configurable daily limit
--   - Automatic daily reset
--   - Check function for ticket creation
--   - Admin configuration table
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Create system configuration table
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.system_config (
    config_key TEXT PRIMARY KEY,
    config_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id)
);

-- Enable RLS
ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can read config
CREATE POLICY "Anyone can read system config"
    ON public.system_config
    FOR SELECT
    USING (true);

-- Policy: Only authenticated users can update (admins should be enforced at app level)
CREATE POLICY "Authenticated users can update system config"
    ON public.system_config
    FOR UPDATE
    USING (auth.uid() IS NOT NULL)
    WITH CHECK (auth.uid() IS NOT NULL);

-- Insert default configuration
INSERT INTO public.system_config (config_key, config_value, description)
VALUES 
    ('daily_queue_ticket_limit', '20', 'Maximum number of queue tickets allowed per day'),
    ('queue_limiter_enabled', 'true', 'Enable or disable the daily queue ticket limiter')
ON CONFLICT (config_key) DO NOTHING;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Function to get daily ticket limit
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_daily_ticket_limit()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_limit INTEGER;
BEGIN
    SELECT COALESCE(config_value::INTEGER, 20)
    INTO v_limit
    FROM public.system_config
    WHERE config_key = 'daily_queue_ticket_limit';
    
    RETURN COALESCE(v_limit, 20);
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Function to check if limiter is enabled
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION is_queue_limiter_enabled()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_enabled BOOLEAN;
BEGIN
    SELECT COALESCE(config_value::BOOLEAN, true)
    INTO v_enabled
    FROM public.system_config
    WHERE config_key = 'queue_limiter_enabled';
    
    RETURN COALESCE(v_enabled, true);
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Function to get today's ticket count
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_today_ticket_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER;
    v_today_start TIMESTAMPTZ;
    v_today_end TIMESTAMPTZ;
BEGIN
    -- Get today's date range in local timezone
    v_today_start := DATE_TRUNC('day', NOW());
    v_today_end := v_today_start + INTERVAL '1 day';
    
    -- Count tickets created today
    SELECT COUNT(*)
    INTO v_count
    FROM public.queue_tickets
    WHERE created_at >= v_today_start
      AND created_at < v_today_end;
    
    RETURN COALESCE(v_count, 0);
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Function to check if daily limit is reached
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION is_daily_ticket_limit_reached()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_enabled BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
BEGIN
    -- Check if limiter is enabled
    v_enabled := is_queue_limiter_enabled();
    
    IF NOT v_enabled THEN
        RETURN false;
    END IF;
    
    -- Get limit and current count
    v_limit := get_daily_ticket_limit();
    v_count := get_today_ticket_count();
    
    -- Return true if limit is reached or exceeded
    RETURN v_count >= v_limit;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Function to get queue limiter status (for UI display)
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_queue_limiter_status()
RETURNS TABLE (
    enabled BOOLEAN,
    daily_limit INTEGER,
    today_count INTEGER,
    limit_reached BOOLEAN,
    remaining_slots INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_enabled BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
    v_reached BOOLEAN;
    v_remaining INTEGER;
BEGIN
    v_enabled := is_queue_limiter_enabled();
    v_limit := get_daily_ticket_limit();
    v_count := get_today_ticket_count();
    v_reached := is_daily_ticket_limit_reached();
    v_remaining := GREATEST(0, v_limit - v_count);
    
    RETURN QUERY SELECT v_enabled, v_limit, v_count, v_reached, v_remaining;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Update create_queue_ticket function to check limit
-- ───────────────────────────────────────────────────────────────────────────

-- Drop existing function if it exists
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
    citizen_id UUID,
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
    v_citizen_id UUID;
    v_queue_number INTEGER;
    v_ticket_code TEXT;
    v_new_ticket_id BIGINT;
    v_limit_reached BOOLEAN;
BEGIN
    -- Get the authenticated user's citizen_id
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

    -- *** NEW: Check if daily ticket limit is reached ***
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

-- ───────────────────────────────────────────────────────────────────────────
-- 8. Grant permissions
-- ───────────────────────────────────────────────────────────────────────────

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION get_daily_ticket_limit() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION is_queue_limiter_enabled() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_today_ticket_count() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION is_daily_ticket_limit_reached() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_queue_limiter_status() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 9. Create index for performance
-- ───────────────────────────────────────────────────────────────────────────

-- Index for counting today's tickets efficiently
-- Using created_at directly since queries use range comparisons (>= and <)
CREATE INDEX IF NOT EXISTS idx_queue_tickets_created_at 
    ON public.queue_tickets (created_at);

-- ───────────────────────────────────────────────────────────────────────────
-- 10. Add comments for documentation
-- ───────────────────────────────────────────────────────────────────────────

COMMENT ON TABLE public.system_config IS 'System-wide configuration settings';
COMMENT ON FUNCTION get_daily_ticket_limit() IS 'Returns the configured daily queue ticket limit';
COMMENT ON FUNCTION is_queue_limiter_enabled() IS 'Returns whether the queue limiter is enabled';
COMMENT ON FUNCTION get_today_ticket_count() IS 'Returns the number of tickets created today';
COMMENT ON FUNCTION is_daily_ticket_limit_reached() IS 'Returns true if daily ticket limit is reached';
COMMENT ON FUNCTION get_queue_limiter_status() IS 'Returns complete status of queue limiter for UI display';
COMMENT ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Creates a new queue ticket with daily limit check';

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MIGRATION
-- ═══════════════════════════════════════════════════════════════════════════
