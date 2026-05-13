-- ═══════════════════════════════════════════════════════════════════════════
-- COMPREHENSIVE INPUT VALIDATION SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════
-- Purpose: Enforce strict input validation across all user inputs
-- Features:
--   - Trim whitespace from all text inputs
--   - Reject empty or whitespace-only values
--   - Normalize multiple consecutive spaces
--   - Apply validation at database level for security
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Utility Functions for Input Validation
-- ───────────────────────────────────────────────────────────────────────────

-- Function to validate and sanitize text input
CREATE OR REPLACE FUNCTION validate_text_input(input_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Return NULL if input is NULL
    IF input_text IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Trim leading and trailing whitespace
    input_text := TRIM(input_text);
    
    -- Return NULL if empty after trimming
    IF input_text = '' THEN
        RETURN NULL;
    END IF;
    
    -- Normalize multiple consecutive spaces to single space
    input_text := REGEXP_REPLACE(input_text, '\s+', ' ', 'g');
    
    RETURN input_text;
END;
$$;

-- Function to validate required text field (throws error if invalid)
CREATE OR REPLACE FUNCTION validate_required_text(
    input_text TEXT,
    field_name TEXT DEFAULT 'Field'
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    sanitized_text TEXT;
BEGIN
    sanitized_text := validate_text_input(input_text);
    
    IF sanitized_text IS NULL THEN
        RAISE EXCEPTION '% cannot be empty or contain only spaces', field_name;
    END IF;
    
    RETURN sanitized_text;
END;
$$;

-- Function to validate email format
CREATE OR REPLACE FUNCTION validate_email(email_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    sanitized_email TEXT;
BEGIN
    -- Sanitize input
    sanitized_email := validate_text_input(email_text);
    
    IF sanitized_email IS NULL THEN
        RAISE EXCEPTION 'Email cannot be empty';
    END IF;
    
    -- Convert to lowercase
    sanitized_email := LOWER(sanitized_email);
    
    -- Basic email format validation
    IF NOT sanitized_email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
        RAISE EXCEPTION 'Invalid email format';
    END IF;
    
    RETURN sanitized_email;
END;
$$;

-- Function to validate phone number (Philippine format)
CREATE OR REPLACE FUNCTION validate_phone_number(phone_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    sanitized_phone TEXT;
BEGIN
    -- Sanitize input
    sanitized_phone := validate_text_input(phone_text);
    
    IF sanitized_phone IS NULL THEN
        RAISE EXCEPTION 'Phone number cannot be empty';
    END IF;
    
    -- Remove all non-digit characters
    sanitized_phone := REGEXP_REPLACE(sanitized_phone, '[^0-9]', '', 'g');
    
    -- Validate Philippine phone format (10 digits after +63)
    IF LENGTH(sanitized_phone) != 10 THEN
        RAISE EXCEPTION 'Phone number must be 10 digits';
    END IF;
    
    -- Add +63 prefix
    RETURN '+63' || sanitized_phone;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Trigger Function to Auto-Sanitize Text Columns
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION sanitize_text_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    column_name TEXT;
    column_value TEXT;
BEGIN
    -- Loop through all text columns and sanitize them
    FOR column_name IN
        SELECT attname
        FROM pg_attribute
        WHERE attrelid = TG_RELID
          AND atttypid IN ('text'::regtype, 'varchar'::regtype, 'character varying'::regtype)
          AND attnum > 0
          AND NOT attisdropped
    LOOP
        -- Get the column value
        EXECUTE format('SELECT ($1).%I', column_name) USING NEW INTO column_value;
        
        -- Sanitize if not null
        IF column_value IS NOT NULL THEN
            column_value := validate_text_input(column_value);
            NEW := jsonb_populate_record(NEW, jsonb_build_object(column_name, column_value));
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Apply Validation Triggers to Existing Tables
-- ───────────────────────────────────────────────────────────────────────────

-- Citizens table
DROP TRIGGER IF EXISTS sanitize_citizens_input ON public.citizens;
CREATE TRIGGER sanitize_citizens_input
    BEFORE INSERT OR UPDATE ON public.citizens
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_text_columns();

-- Staff table
DROP TRIGGER IF EXISTS sanitize_staff_input ON public.staff;
CREATE TRIGGER sanitize_staff_input
    BEFORE INSERT OR UPDATE ON public.staff
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_text_columns();

-- Queue tickets table
DROP TRIGGER IF EXISTS sanitize_queue_tickets_input ON public.queue_tickets;
CREATE TRIGGER sanitize_queue_tickets_input
    BEFORE INSERT OR UPDATE ON public.queue_tickets
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_text_columns();

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Add Check Constraints for Required Fields
-- ───────────────────────────────────────────────────────────────────────────

-- Citizens table constraints
ALTER TABLE public.citizens DROP CONSTRAINT IF EXISTS citizens_firstname_not_empty;
ALTER TABLE public.citizens ADD CONSTRAINT citizens_firstname_not_empty 
    CHECK (LENGTH(TRIM(firstname)) > 0);

ALTER TABLE public.citizens DROP CONSTRAINT IF EXISTS citizens_surname_not_empty;
ALTER TABLE public.citizens ADD CONSTRAINT citizens_surname_not_empty 
    CHECK (LENGTH(TRIM(surname)) > 0);

ALTER TABLE public.citizens DROP CONSTRAINT IF EXISTS citizens_email_not_empty;
ALTER TABLE public.citizens ADD CONSTRAINT citizens_email_not_empty 
    CHECK (LENGTH(TRIM(email)) > 0 AND email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Staff table constraints
ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_first_name_not_empty;
ALTER TABLE public.staff ADD CONSTRAINT staff_first_name_not_empty 
    CHECK (first_name IS NULL OR LENGTH(TRIM(first_name)) > 0);

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_last_name_not_empty;
ALTER TABLE public.staff ADD CONSTRAINT staff_last_name_not_empty 
    CHECK (last_name IS NULL OR LENGTH(TRIM(last_name)) > 0);

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_username_not_empty;
ALTER TABLE public.staff ADD CONSTRAINT staff_username_not_empty 
    CHECK (LENGTH(TRIM(username)) > 0);

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_email_not_empty;
ALTER TABLE public.staff ADD CONSTRAINT staff_email_not_empty 
    CHECK (email IS NULL OR (LENGTH(TRIM(email)) > 0 AND email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'));

-- Queue tickets constraints
ALTER TABLE public.queue_tickets DROP CONSTRAINT IF EXISTS queue_tickets_service_label_not_whitespace;
ALTER TABLE public.queue_tickets ADD CONSTRAINT queue_tickets_service_label_not_whitespace 
    CHECK (LENGTH(TRIM(service_label)) > 0);

ALTER TABLE public.queue_tickets DROP CONSTRAINT IF EXISTS queue_tickets_citizen_type_not_whitespace;
ALTER TABLE public.queue_tickets ADD CONSTRAINT queue_tickets_citizen_type_not_whitespace 
    CHECK (LENGTH(TRIM(citizen_type)) > 0);

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Update Existing Functions to Use Validation
-- ───────────────────────────────────────────────────────────────────────────

-- Update create_queue_ticket to validate inputs
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
    v_service_key TEXT;
    v_service_label TEXT;
    v_citizen_type TEXT;
    v_reason TEXT;
    v_symptoms TEXT;
BEGIN
    -- Validate and sanitize all inputs
    v_service_key := validate_required_text(p_service_key, 'Service key');
    v_service_label := validate_required_text(p_service_label, 'Service label');
    v_citizen_type := validate_required_text(p_citizen_type, 'Citizen type');
    v_reason := validate_text_input(p_reason);
    v_symptoms := validate_text_input(p_symptoms);

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
        v_service_key,
        v_service_label,
        v_citizen_type,
        v_reason,
        v_symptoms,
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

GRANT EXECUTE ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Grant Permissions
-- ───────────────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION validate_text_input(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION validate_required_text(TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION validate_email(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION validate_phone_number(TEXT) TO authenticated, anon;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Documentation
-- ───────────────────────────────────────────────────────────────────────────

COMMENT ON FUNCTION validate_text_input(TEXT) IS 'Trims whitespace and normalizes spaces. Returns NULL if empty.';
COMMENT ON FUNCTION validate_required_text(TEXT, TEXT) IS 'Validates required text field. Throws error if empty or whitespace-only.';
COMMENT ON FUNCTION validate_email(TEXT) IS 'Validates and sanitizes email address format.';
COMMENT ON FUNCTION validate_phone_number(TEXT) IS 'Validates and formats Philippine phone numbers (+63 format).';
COMMENT ON FUNCTION sanitize_text_columns() IS 'Trigger function that auto-sanitizes all text columns on insert/update.';

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MIGRATION
-- ═══════════════════════════════════════════════════════════════════════════
