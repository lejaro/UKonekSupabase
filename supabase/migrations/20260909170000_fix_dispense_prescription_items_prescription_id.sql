-- ==============================================================================
-- Migration: 20260909170000_fix_dispense_prescription_items_prescription_id.sql
-- Description: Fix NOT NULL constraint violation on prescription_item_dispenses.prescription_id
--              when dispensing prescriptions. Also standardizes partial status to 'partial'
--              and provides both dispense_prescription_items and dispense_prescription RPCs.
-- ==============================================================================

create or replace function public.dispense_prescription_items(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
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
begin
  -- Resolve caller
  select s.id, s.role
  into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = (select auth.uid())
    and s.status = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Not authenticated as active staff');
  end if;

  if v_role <> 'pharmacist' then
    return json_build_object('error', 'Forbidden: only pharmacists can dispense prescriptions');
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return json_build_object('error', 'No dispense items provided');
  end if;

  begin
    -- Lock target prescription
    select ph.id, ph.dispensing_status
    into v_header_id, v_header_status
    from public.prescription_headers ph
    where upper(trim(ph.prescription_code)) = upper(trim(coalesce(p_prescription_code, '')))
    limit 1
    for update;

    if v_header_id is null then
      raise exception 'Prescription not found';
    end if;

    if v_header_status = 'cancelled' then
      raise exception 'Prescription has been cancelled and cannot be dispensed';
    end if;

    if v_header_status = 'expired' then
      raise exception 'Prescription has expired and can no longer be dispensed';
    end if;

    if v_header_status = 'dispensed' then
      raise exception 'Prescription is already fully dispensed';
    end if;

    -- Disallow duplicate item IDs in request payload
    if exists (
      select 1
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
      group by r.prescription_item_id
      having count(*) > 1
    ) then
      raise exception 'Duplicate prescription_item_id in request payload';
    end if;

    -- Process items in deterministic ascending order to prevent deadlocks
    for v_row in
      select r.prescription_item_id, r.quantity
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
      order by r.prescription_item_id asc
    loop
      if v_row.prescription_item_id is null then
        raise exception 'prescription_item_id is required for every item';
      end if;

      if v_row.quantity is null or v_row.quantity < 0 then
        raise exception 'Dispense quantity cannot be negative for item %', v_row.prescription_item_id;
      end if;

      if v_row.quantity = 0 then
        continue;
      end if;

      select
        pi.id,
        pi.medicine_id,
        pi.medicine_name,
        pi.unit,
        pi.quantity,
        coalesce(pi.dispensed_quantity, 0) as dispensed_quantity,
        coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) as remaining_quantity
      into v_item
      from public.prescription_items pi
      where pi.id = v_row.prescription_item_id
        and pi.prescription_id = v_header_id
      for update;

      if v_item.id is null then
        raise exception 'Prescription item % not found for this prescription', v_row.prescription_item_id;
      end if;

      if v_row.quantity > v_item.remaining_quantity then
        raise exception
          'Over-dispense blocked for % (remaining: %, requested: %)',
          v_item.medicine_name, v_item.remaining_quantity, v_row.quantity;
      end if;

      -- Smart match: match by medicine_id first, then fallback to name
      select m.id, m.qty, m.expiry_date
      into v_medicine_id, v_medicine_qty, v_medicine_expiry
      from public.medicines m
      where (
        (v_item.medicine_id is not null and m.id = v_item.medicine_id)
        or lower(trim(m.name)) = lower(trim(v_item.medicine_name))
      )
      and m.archived_at is null
      order by (case when v_item.medicine_id is not null and m.id = v_item.medicine_id then 0 else 1 end) asc, m.id asc
      limit 1
      for update;

      if v_medicine_id is null then
        raise exception 'Medicine not found in inventory: %', v_item.medicine_name;
      end if;

      -- Safety Guard: Block dispensing of expired batch
      if v_medicine_expiry is not null and v_medicine_expiry < current_date then
        raise exception 'Safety block: Inventory batch for % expired on % and cannot be dispensed.',
          v_item.medicine_name, to_char(v_medicine_expiry, 'YYYY-MM-DD');
      end if;

      if v_medicine_qty < v_row.quantity then
        raise exception
          'Insufficient stock for % (available: %, requested: %)',
          v_item.medicine_name, v_medicine_qty, v_row.quantity;
      end if;

      -- Deduct inventory stock
      update public.medicines
      set qty = qty - v_row.quantity
      where id = v_medicine_id;

      -- Update item dispensed & remaining counters
      update public.prescription_items
      set
        medicine_id = coalesce(v_item.medicine_id, v_medicine_id),
        dispensed_quantity = v_item.dispensed_quantity + v_row.quantity,
        remaining_quantity = v_item.remaining_quantity - v_row.quantity,
        is_dispensed = (v_item.remaining_quantity - v_row.quantity = 0)
      where id = v_item.id;

      -- Record dispense event with required prescription_id NOT NULL column
      insert into public.prescription_item_dispenses (
        prescription_id,
        prescription_item_id,
        medicine_id,
        dispensed_quantity,
        unit,
        note,
        dispensed_by_staff_id,
        dispensed_at
      ) values (
        v_header_id,
        v_item.id,
        v_medicine_id,
        v_row.quantity,
        coalesce(v_item.unit, ''),
        nullif(trim(p_note), ''),
        v_staff_id,
        now()
      );
    end loop;

    -- Recalculate prescription header status
    select
      count(*),
      count(*) filter (where remaining_quantity = 0),
      count(*) filter (where remaining_quantity > 0 and dispensed_quantity > 0)
    into v_total_rows, v_medicine_qty, v_medicine_id
    from public.prescription_items
    where prescription_id = v_header_id;

    if v_total_rows = 0 then
      v_new_status := 'pending';
    elsif v_medicine_qty = v_total_rows then
      v_new_status := 'dispensed';
    elsif v_medicine_qty > 0 or v_medicine_id > 0 then
      v_new_status := 'partial';
    else
      v_new_status := 'pending';
    end if;

    update public.prescription_headers
    set
      dispensing_status = v_new_status,
      dispensed_by_staff_id = v_staff_id,
      dispensed_at = case when v_new_status = 'dispensed' then now() else dispensed_at end
    where id = v_header_id;

    return json_build_object(
      'ok', true,
      'prescription_code', upper(trim(p_prescription_code)),
      'dispensing_status', v_new_status
    );
  exception
    when others then
      return json_build_object('error', sqlerrm);
  end;
end;
$$;

-- Alias RPC for backwards compatibility
create or replace function public.dispense_prescription(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.dispense_prescription_items(p_prescription_code, p_items, p_note);
end;
$$;

grant execute on function public.dispense_prescription_items(text, jsonb, text) to authenticated;
grant execute on function public.dispense_prescription(text, jsonb, text) to authenticated;
