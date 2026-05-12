-- Fix sanitize_text_columns to avoid invalid := assignment in dynamic SQL.

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

COMMENT ON FUNCTION sanitize_text_columns() IS
  'Sanitizes text/varchar columns using validate_text_input without dynamic := assignment.';
