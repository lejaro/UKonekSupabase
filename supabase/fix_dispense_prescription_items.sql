-- ==============================================================================
-- FIX: supabase/fix_dispense_prescription_items.sql
-- Description: Fixes the following database error when dispensing prescriptions:
--   "null value in column "prescription_id" of relation "prescription_item_dispenses"
--    violates not-null constraint"
--
-- How to apply:
--   1. Open your Supabase Project Dashboard (https://supabase.com/dashboard)
--   2. Go to the SQL Editor tab
--   3. Paste this entire script and click "Run"
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.dispense_prescription_items(
  p_prescription_code text,
  p_items jsonb,
  p_note text DEFAULT null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id bigint;
  v_role text;
  v_header_id bigint;
  v_header_status text;
  v_row record;
  v_item record;
  v_medicine_id bigint;
  v_medicine_qty integer;
  v_medicine_expiry date;
  v_new_status text;
  v_total_rows integer;
BEGIN
  -- 1. Resolve caller staff credentials
  SELECT s.id, s.role
  INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = (SELECT auth.uid())
    AND s.status = 'active'
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated as active staff');
  END IF;

  IF v_role <> 'pharmacist' THEN
    RETURN json_build_object('error', 'Forbidden: only pharmacists can dispense prescriptions');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN json_build_object('error', 'No dispense items provided');
  END IF;

  BEGIN
    -- 2. Lock target prescription header
    SELECT ph.id, ph.dispensing_status
    INTO v_header_id, v_header_status
    FROM public.prescription_headers ph
    WHERE UPPER(TRIM(ph.prescription_code)) = UPPER(TRIM(COALESCE(p_prescription_code, '')))
    LIMIT 1
    FOR UPDATE;

    IF v_header_id IS NULL THEN
      RAISE EXCEPTION 'Prescription not found';
    END IF;

    IF v_header_status = 'cancelled' THEN
      RAISE EXCEPTION 'Prescription has been cancelled and cannot be dispensed';
    END IF;

    IF v_header_status = 'expired' THEN
      RAISE EXCEPTION 'Prescription has expired and can no longer be dispensed';
    END IF;

    IF v_header_status = 'dispensed' THEN
      RAISE EXCEPTION 'Prescription is already fully dispensed';
    END IF;

    -- 3. Disallow duplicate item IDs in request payload
    IF EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer)
      GROUP BY r.prescription_item_id
      HAVING count(*) > 1
    ) THEN
      RAISE EXCEPTION 'Duplicate prescription_item_id in request payload';
    END IF;

    -- 4. Process items in deterministic ascending order (prevents deadlocks)
    FOR v_row IN
      SELECT r.prescription_item_id, r.quantity
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer)
      ORDER BY r.prescription_item_id ASC
    LOOP
      IF v_row.prescription_item_id IS NULL THEN
        RAISE EXCEPTION 'prescription_item_id is required for every item';
      END IF;

      IF v_row.quantity IS NULL OR v_row.quantity < 0 THEN
        RAISE EXCEPTION 'Dispense quantity cannot be negative for item %', v_row.prescription_item_id;
      END IF;

      IF v_row.quantity = 0 THEN
        CONTINUE;
      END IF;

      SELECT
        pi.id,
        pi.medicine_id,
        pi.medicine_name,
        pi.unit,
        pi.quantity,
        coalesce(pi.dispensed_quantity, 0) AS dispensed_quantity,
        coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) AS remaining_quantity
      INTO v_item
      FROM public.prescription_items pi
      WHERE pi.id = v_row.prescription_item_id
        AND pi.prescription_id = v_header_id
      FOR UPDATE;

      IF v_item.id IS NULL THEN
        RAISE EXCEPTION 'Prescription item % not found for this prescription', v_row.prescription_item_id;
      END IF;

      IF v_row.quantity > v_item.remaining_quantity THEN
        RAISE EXCEPTION
          'Over-dispense blocked for % (remaining: %, requested: %)',
          v_item.medicine_name, v_item.remaining_quantity, v_row.quantity;
      END IF;

      -- Smart match: match by medicine_id first, then fallback to name
      SELECT m.id, m.qty, m.expiry_date
      INTO v_medicine_id, v_medicine_qty, v_medicine_expiry
      FROM public.medicines m
      WHERE (
        (v_item.medicine_id IS NOT NULL AND m.id = v_item.medicine_id)
        OR LOWER(TRIM(m.name)) = LOWER(TRIM(v_item.medicine_name))
      )
      AND m.archived_at IS NULL
      ORDER BY (CASE WHEN v_item.medicine_id IS NOT NULL AND m.id = v_item.medicine_id THEN 0 ELSE 1 END) ASC, m.id ASC
      LIMIT 1
      FOR UPDATE;

      IF v_medicine_id IS NULL THEN
        RAISE EXCEPTION 'Medicine not found in inventory: %', v_item.medicine_name;
      END IF;

      -- Safety Guard: Block dispensing of expired batch
      IF v_medicine_expiry IS NOT NULL AND v_medicine_expiry < CURRENT_DATE THEN
        RAISE EXCEPTION 'Safety block: Inventory batch for % expired on % and cannot be dispensed.',
          v_item.medicine_name, to_char(v_medicine_expiry, 'YYYY-MM-DD');
      END IF;

      IF v_medicine_qty < v_row.quantity THEN
        RAISE EXCEPTION
          'Insufficient stock for % (available: %, requested: %)',
          v_item.medicine_name, v_medicine_qty, v_row.quantity;
      END IF;

      -- Deduct inventory stock
      UPDATE public.medicines
      SET qty = qty - v_row.quantity
      WHERE id = v_medicine_id;

      -- Update item dispensed & remaining counters
      UPDATE public.prescription_items
      SET
        medicine_id = coalesce(v_item.medicine_id, v_medicine_id),
        dispensed_quantity = v_item.dispensed_quantity + v_row.quantity,
        remaining_quantity = v_item.remaining_quantity - v_row.quantity,
        is_dispensed = (v_item.remaining_quantity - v_row.quantity = 0)
      WHERE id = v_item.id;

      -- Record dispense event with required prescription_id NOT NULL column
      INSERT INTO public.prescription_item_dispenses (
        prescription_id,
        prescription_item_id,
        medicine_id,
        dispensed_quantity,
        unit,
        note,
        dispensed_by_staff_id,
        dispensed_at
      ) VALUES (
        v_header_id,
        v_item.id,
        v_medicine_id,
        v_row.quantity,
        coalesce(v_item.unit, ''),
        nullif(trim(p_note), ''),
        v_staff_id,
        now()
      );
    END LOOP;

    -- 5. Recalculate prescription header status
    SELECT
      count(*),
      count(*) FILTER (WHERE remaining_quantity = 0),
      count(*) FILTER (WHERE remaining_quantity > 0 AND dispensed_quantity > 0)
    INTO v_total_rows, v_medicine_qty, v_medicine_id
    FROM public.prescription_items
    WHERE prescription_id = v_header_id;

    IF v_total_rows = 0 THEN
      v_new_status := 'pending';
    ELSIF v_medicine_qty = v_total_rows THEN
      v_new_status := 'dispensed';
    ELSIF v_medicine_qty > 0 OR v_medicine_id > 0 THEN
      v_new_status := 'partial';
    ELSE
      v_new_status := 'pending';
    END IF;

    UPDATE public.prescription_headers
    SET
      dispensing_status = v_new_status,
      dispensed_by_staff_id = v_staff_id,
      dispensed_at = CASE WHEN v_new_status = 'dispensed' THEN now() ELSE dispensed_at END
    WHERE id = v_header_id;

    RETURN json_build_object(
      'ok', true,
      'prescription_code', upper(trim(p_prescription_code)),
      'dispensing_status', v_new_status
    );
  EXCEPTION
    WHEN others THEN
      RETURN json_build_object('error', sqlerrm);
  END;
END;
$$;

-- Alias RPC for backwards compatibility
CREATE OR REPLACE FUNCTION public.dispense_prescription(
  p_prescription_code text,
  p_items jsonb,
  p_note text DEFAULT null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.dispense_prescription_items(p_prescription_code, p_items, p_note);
END;
$$;

GRANT EXECUTE ON FUNCTION public.dispense_prescription_items(text, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispense_prescription(text, jsonb, text) TO authenticated;
