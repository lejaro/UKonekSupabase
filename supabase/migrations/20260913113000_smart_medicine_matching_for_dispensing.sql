-- Migration: 20260913113000_smart_medicine_matching_for_dispensing.sql
-- Description: Implement resilient, multi-tier medicine matching in dispense and restock RPCs.
-- Prevents "Medicine not found in inventory" errors caused by dosage, form, or whitespace differences (e.g. Amoxicillin 500mg vs Amoxicillin 500 mg Capsule vs Amoxicillin).

-- 1. Helper function: normalize medicine name by stripping dosages and common dosage forms
CREATE OR REPLACE FUNCTION public.normalize_medicine_name(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          coalesce(p_name, ''),
          '(\d+(\.\d+)?\s*(mg|g|mcg|ml|iu|%|meq)(\s*/\s*\d+\s*(ml|l))?)',
          '',
          'gi'
        ),
        '\b(capsule|tablet|cap|tab|suspension|susp|syrup|syr|drops|solution|ointment|cream|injection|inj|ampoule|vial)\b',
        '',
        'gi'
      ),
      '[^a-zA-Z0-9]+',
      ' ',
      'g'
    )
  ));
$$;

GRANT EXECUTE ON FUNCTION public.normalize_medicine_name(text) TO authenticated, anon;

-- 2. Update dispense_prescription_items with resilient multi-tier matching
CREATE OR REPLACE FUNCTION public.dispense_prescription_items(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
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
  v_target_med_id bigint;
BEGIN
  -- Resolve caller
  SELECT s.id, lower(trim(coalesce(s.role, '')))
  INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = (SELECT auth.uid())
    AND lower(trim(coalesce(s.status, ''))) = 'active'
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
    -- Lock target prescription header
    SELECT ph.id, ph.dispensing_status
    INTO v_header_id, v_header_status
    FROM public.prescription_headers ph
    WHERE upper(trim(ph.prescription_code)) = upper(trim(coalesce(p_prescription_code, '')))
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

    -- Disallow duplicate item IDs in request payload
    IF EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer)
      GROUP BY r.prescription_item_id
      HAVING count(*) > 1
    ) THEN
      RAISE EXCEPTION 'Duplicate prescription_item_id in request payload';
    END IF;

    -- Process items in deterministic ascending order to prevent deadlocks
    FOR v_row IN
      SELECT r.prescription_item_id, r.quantity, r.medicine_id
      FROM jsonb_to_recordset(p_items) AS r(prescription_item_id bigint, quantity integer, medicine_id bigint)
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

      -- Determine explicit medicine ID if passed in payload or already stored on item
      v_target_med_id := coalesce(v_row.medicine_id, v_item.medicine_id);

      -- Resilient multi-tier inventory resolution:
      -- 1. Exact medicine ID
      -- 2. Exact case-insensitive name match
      -- 3. Normalized generic name with matching strength/dosage number (e.g. 500 in both)
      -- 4. Normalized generic name match (strips 500mg, capsule, etc.)
      -- 5. Substring containment match
      SELECT m.id, m.qty, m.expiry_date
      INTO v_medicine_id, v_medicine_qty, v_medicine_expiry
      FROM public.medicines m
      WHERE (
        (v_target_med_id IS NOT NULL AND m.id = v_target_med_id)
        OR lower(trim(m.name)) = lower(trim(v_item.medicine_name))
        OR (
          public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name)
          AND length(public.normalize_medicine_name(m.name)) >= 3
        )
        OR (
          length(trim(m.name)) >= 4
          AND (
            lower(trim(v_item.medicine_name)) LIKE ('%' || lower(trim(m.name)) || '%')
            OR lower(trim(m.name)) LIKE ('%' || lower(trim(v_item.medicine_name)) || '%')
          )
        )
      )
      AND m.archived_at IS NULL
      ORDER BY
        -- Priority 0: Explicit ID match
        (CASE WHEN v_target_med_id IS NOT NULL AND m.id = v_target_med_id THEN 0 ELSE 1 END) ASC,
        -- Priority 1: Exact string match
        (CASE WHEN lower(trim(m.name)) = lower(trim(v_item.medicine_name)) THEN 0 ELSE 1 END) ASC,
        -- Priority 2: Normalized name + matching dosage number
        (CASE WHEN public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name)
                   AND substring(m.name FROM '\d+') IS NOT NULL
                   AND substring(m.name FROM '\d+') = substring(v_item.medicine_name FROM '\d+')
              THEN 0 ELSE 1 END) ASC,
        -- Priority 3: Normalized name match
        (CASE WHEN public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name) THEN 0 ELSE 1 END) ASC,
        -- Priority 4: Substring match
        (CASE WHEN length(trim(m.name)) >= 4 AND (
                    lower(trim(v_item.medicine_name)) LIKE ('%' || lower(trim(m.name)) || '%')
                    OR lower(trim(m.name)) LIKE ('%' || lower(trim(v_item.medicine_name)) || '%')
                   ) THEN 0 ELSE 1 END) ASC,
        -- Tie-breaker: Sufficient stock first
        (CASE WHEN m.qty >= v_row.quantity THEN 0 ELSE 1 END) ASC,
        -- Tie-breaker: Unexpired first
        (CASE WHEN m.expiry_date IS NULL OR m.expiry_date >= current_date THEN 0 ELSE 1 END) ASC,
        m.id ASC
      LIMIT 1
      FOR UPDATE;

      IF v_medicine_id IS NULL THEN
        RAISE EXCEPTION 'Medicine not found in inventory: %', v_item.medicine_name;
      END IF;

      -- Safety Guard: Block dispensing of expired batch
      IF v_medicine_expiry IS NOT NULL AND v_medicine_expiry < current_date THEN
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

      -- Update item dispensed & remaining counters and permanently link medicine_id
      UPDATE public.prescription_items
      SET
        medicine_id = coalesce(v_item.medicine_id, v_medicine_id),
        dispensed_quantity = v_item.dispensed_quantity + v_row.quantity,
        remaining_quantity = v_item.remaining_quantity - v_row.quantity,
        is_dispensed = (v_item.remaining_quantity - v_row.quantity = 0)
      WHERE id = v_item.id;

      -- Record dispense event
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

    -- Recalculate prescription header status
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
    WHEN OTHERS THEN
      RETURN json_build_object('error', sqlerrm);
  END;
END;
$$;

-- 3. Update restock_prescription_item with same smart matching
CREATE OR REPLACE FUNCTION public.restock_prescription_item(
  p_prescription_item_id bigint,
  p_quantity integer,
  p_reason text default null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_id bigint;
  v_role text;
  v_item record;
  v_med_id bigint;
  v_active_dispensed integer;
  v_target_med_id bigint;
BEGIN
  -- Authorize caller
  SELECT s.id, lower(trim(coalesce(s.role, '')))
  INTO v_staff_id, v_role
  FROM public.staff s
  WHERE s.auth_user_id = auth.uid()
    AND lower(trim(coalesce(s.status, ''))) = 'active'
  LIMIT 1;

  IF v_staff_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated as active staff.');
  END IF;

  IF v_role <> 'pharmacist' THEN
    RETURN json_build_object('error', 'Forbidden: only pharmacists can restock returned items.');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN json_build_object('error', 'Restock quantity must be greater than zero.');
  END IF;

  -- Lock item
  SELECT
    pi.id,
    pi.prescription_id,
    pi.medicine_id,
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.dispensed_quantity, 0) AS dispensed_quantity,
    coalesce(pi.remaining_quantity, 0) AS remaining_quantity,
    coalesce(pi.returned_quantity, 0) AS returned_quantity
  INTO v_item
  FROM public.prescription_items pi
  WHERE pi.id = p_prescription_item_id
  FOR UPDATE;

  IF v_item.id IS NULL THEN
    RETURN json_build_object('error', 'Prescription item not found.');
  END IF;

  v_active_dispensed := v_item.dispensed_quantity - coalesce(v_item.returned_quantity, 0);

  IF p_quantity > v_active_dispensed THEN
    RETURN json_build_object('error', format('Cannot return %s units; only %s units are currently dispensed.', p_quantity, v_active_dispensed));
  END IF;

  v_target_med_id := v_item.medicine_id;

  -- Resilient medicine matching for restocking
  SELECT m.id INTO v_med_id
  FROM public.medicines m
  WHERE (
    (v_target_med_id IS NOT NULL AND m.id = v_target_med_id)
    OR lower(trim(m.name)) = lower(trim(v_item.medicine_name))
    OR (
      public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name)
      AND length(public.normalize_medicine_name(m.name)) >= 3
    )
    OR (
      length(trim(m.name)) >= 4
      AND (
        lower(trim(v_item.medicine_name)) LIKE ('%' || lower(trim(m.name)) || '%')
        OR lower(trim(m.name)) LIKE ('%' || lower(trim(v_item.medicine_name)) || '%')
      )
    )
  )
  AND m.archived_at IS NULL
  ORDER BY
    (CASE WHEN v_target_med_id IS NOT NULL AND m.id = v_target_med_id THEN 0 ELSE 1 END) ASC,
    (CASE WHEN lower(trim(m.name)) = lower(trim(v_item.medicine_name)) THEN 0 ELSE 1 END) ASC,
    (CASE WHEN public.normalize_medicine_name(m.name) = public.normalize_medicine_name(v_item.medicine_name) THEN 0 ELSE 1 END) ASC,
    m.id ASC
  LIMIT 1
  FOR UPDATE;

  IF v_med_id IS NULL THEN
    RETURN json_build_object('error', format('Medicine %s not found in inventory for restocking.', v_item.medicine_name));
  END IF;

  -- Restock inventory
  UPDATE public.medicines
  SET qty = qty + p_quantity
  WHERE id = v_med_id;

  -- Update prescription item counters
  UPDATE public.prescription_items
  SET
    returned_quantity = coalesce(returned_quantity, 0) + p_quantity,
    remaining_quantity = remaining_quantity + p_quantity,
    is_dispensed = false,
    medicine_id = coalesce(v_item.medicine_id, v_med_id)
  WHERE id = v_item.id;

  -- Record audit log
  INSERT INTO public.medicine_return_logs (
    prescription_item_id,
    medicine_id,
    returned_quantity,
    reason,
    returned_by_staff_id,
    returned_at
  ) VALUES (
    v_item.id,
    v_med_id,
    p_quantity,
    nullif(trim(p_reason), ''),
    v_staff_id,
    now()
  );

  -- Re-evaluate header status
  UPDATE public.prescription_headers
  SET dispensing_status = 'partial'
  WHERE id = v_item.prescription_id
    AND dispensing_status = 'dispensed';

  RETURN json_build_object(
    'ok', true,
    'message', format('Restocked %s units of %s.', p_quantity, v_item.medicine_name),
    'returned_quantity', v_item.returned_quantity + p_quantity,
    'remaining_quantity', v_item.remaining_quantity + p_quantity
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.dispense_prescription_items(text, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispense_prescription(text, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restock_prescription_item(bigint, integer, text) TO authenticated;
