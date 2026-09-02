-- Migration: allow_zero_quantity_dispensing
-- Description: Allow quantity 0 as a valid input when dispensing prescription items.
-- Items with quantity = 0 are safely bypassed (no inventory deducted, no audit row created).

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
  v_new_status text;
  v_total_rows integer;
begin
  -- Resolve caller.
  select s.id, s.role
  into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = auth.uid()
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
    -- Lock target prescription.
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

    -- Disallow duplicate item IDs in a single request.
    if exists (
      select 1
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
      group by r.prescription_item_id
      having count(*) > 1
    ) then
      raise exception 'Duplicate prescription_item_id in request payload';
    end if;

    -- Process all requested partials atomically. Any error rolls back all updates.
    for v_row in
      select r.prescription_item_id, r.quantity
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
    loop
      if v_row.prescription_item_id is null then
        raise exception 'prescription_item_id is required for every item';
      end if;

      if v_row.quantity is null or v_row.quantity < 0 then
        raise exception 'Dispense quantity cannot be negative for item %', v_row.prescription_item_id;
      end if;

      -- Quantity 0 is valid: represents a line item not being dispensed in this transaction.
      if v_row.quantity = 0 then
        continue;
      end if;

      select
        pi.id,
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

      select m.id, m.qty
      into v_medicine_id, v_medicine_qty
      from public.medicines m
      where lower(trim(m.name)) = lower(trim(v_item.medicine_name))
        and m.archived_at is null
      order by m.id asc
      limit 1
      for update;

      if v_medicine_id is null then
        raise exception 'Medicine not found in inventory: %', v_item.medicine_name;
      end if;

      if v_medicine_qty < v_row.quantity then
        raise exception
          'Insufficient stock for % (available: %, requested: %)',
          v_item.medicine_name, v_medicine_qty, v_row.quantity;
      end if;

      update public.medicines
      set qty = qty - v_row.quantity
      where id = v_medicine_id;

      update public.prescription_items
      set
        dispensed_quantity = coalesce(dispensed_quantity, 0) + v_row.quantity,
        last_dispensed_at = now()
      where id = v_item.id;

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
        p_note,
        v_staff_id,
        now()
      );
    end loop;

    select count(*)::integer
    into v_total_rows
    from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer);

    v_new_status := public.refresh_prescription_header_dispensing_status(v_header_id);

    return json_build_object(
      'ok', true,
      'prescription_id', v_header_id,
      'dispensing_status', v_new_status,
      'items_processed', coalesce(v_total_rows, 0)
    );
  exception
    when others then
      return json_build_object('error', SQLERRM);
  end;
end;
$$;

grant execute on function public.dispense_prescription_items(text, jsonb, text) to authenticated;
