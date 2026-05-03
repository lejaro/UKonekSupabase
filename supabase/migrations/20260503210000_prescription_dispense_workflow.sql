-- Prescription dispense workflow
-- Adds: prescription_code (unique human-readable ID), dispensing_status,
--       dispensed_by_staff_id, dispensed_at to prescription_headers.
-- Adds: dispense_prescription() RPC callable only by pharmacists.
-- Removes automatic stock deduction from the doctor's prescription path.

-- ── 1. Extend prescription_headers ──────────────────────────────────────────

alter table public.prescription_headers
  add column if not exists prescription_code text unique,
  add column if not exists dispensing_status text not null default 'pending',
  add column if not exists dispensed_by_staff_id bigint references public.staff(id) on delete set null,
  add column if not exists dispensed_at timestamptz;

-- Constraint: only valid statuses allowed
alter table public.prescription_headers
  drop constraint if exists chk_dispensing_status;
alter table public.prescription_headers
  add constraint chk_dispensing_status
  check (dispensing_status in ('pending', 'dispensed', 'cancelled'));

-- Index for fast lookup by prescription code
create index if not exists idx_prescription_headers_code
  on public.prescription_headers(prescription_code)
  where prescription_code is not null;

create index if not exists idx_prescription_headers_status
  on public.prescription_headers(dispensing_status);

-- ── 2. Back-fill existing rows with a generated code ────────────────────────

update public.prescription_headers
set prescription_code = 'RX-' || lpad(id::text, 6, '0')
where prescription_code is null;

-- ── 3. Trigger: auto-generate prescription_code on INSERT if not supplied ───

create or replace function public.generate_prescription_code()
returns trigger
language plpgsql
as $$
begin
  if new.prescription_code is null or trim(new.prescription_code) = '' then
    new.prescription_code := 'RX-' || lpad(new.id::text, 6, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generate_prescription_code on public.prescription_headers;
create trigger trg_generate_prescription_code
before insert on public.prescription_headers
for each row execute function public.generate_prescription_code();

-- ── 4. RLS: pharmacist can SELECT prescriptions and items ────────────────────

drop policy if exists prescription_headers_select_pharmacist on public.prescription_headers;
create policy prescription_headers_select_pharmacist
  on public.prescription_headers
  for select
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

drop policy if exists prescription_headers_update_pharmacist on public.prescription_headers;
create policy prescription_headers_update_pharmacist
  on public.prescription_headers
  for update
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  )
  with check (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

grant update on public.prescription_headers to authenticated;

-- ── 5. RPC: dispense_prescription ───────────────────────────────────────────
-- Called by pharmacist after handing medicine to patient.
-- Atomically: marks prescription as dispensed + deducts stock for each item.
-- Prevents duplicate dispensing via status check.

create or replace function public.dispense_prescription(p_prescription_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id    bigint;
  v_role        text;
  v_header_id   bigint;
  v_status      text;
  v_item        record;
  v_current_qty integer;
begin
  -- Auth: resolve calling staff
  select s.id, lower(trim(coalesce(s.role, '')))
  into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = auth.uid()
    and lower(trim(coalesce(s.status, ''))) = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Not authenticated as active staff');
  end if;

  if v_role <> 'pharmacist' then
    return json_build_object('error', 'Forbidden: only pharmacists can dispense prescriptions');
  end if;

  -- Lookup prescription
  select id, dispensing_status
  into v_header_id, v_status
  from public.prescription_headers
  where trim(upper(prescription_code)) = trim(upper(coalesce(p_prescription_code, '')))
  limit 1;

  if v_header_id is null then
    return json_build_object('error', 'Prescription not found');
  end if;

  if v_status = 'dispensed' then
    return json_build_object('error', 'Prescription has already been dispensed');
  end if;

  if v_status = 'cancelled' then
    return json_build_object('error', 'Prescription has been cancelled and cannot be dispensed');
  end if;

  -- Deduct stock for each item (in a single transaction)
  for v_item in
    select pi.medicine_name, pi.quantity
    from public.prescription_items pi
    where pi.prescription_id = v_header_id
  loop
    select qty into v_current_qty
    from public.medicines
    where lower(trim(name)) = lower(trim(v_item.medicine_name))
      and archived_at is null
    limit 1;

    if v_current_qty is null then
      return json_build_object(
        'error', 'Medicine not found in inventory: ' || v_item.medicine_name
      );
    end if;

    if v_current_qty < v_item.quantity then
      return json_build_object(
        'error', 'Insufficient stock for ' || v_item.medicine_name ||
                 ' (available: ' || v_current_qty || ', required: ' || v_item.quantity || ')'
      );
    end if;

    update public.medicines
    set qty = qty - v_item.quantity
    where lower(trim(name)) = lower(trim(v_item.medicine_name))
      and archived_at is null;
  end loop;

  -- Mark as dispensed
  update public.prescription_headers
  set
    dispensing_status    = 'dispensed',
    dispensed_by_staff_id = v_staff_id,
    dispensed_at         = now()
  where id = v_header_id;

  return json_build_object('ok', true, 'prescription_id', v_header_id);
end;
$$;

grant execute on function public.dispense_prescription(text) to authenticated;

-- ── 6. RPC: lookup_prescription_by_code ─────────────────────────────────────
-- Returns prescription details for the pharmacist to preview before dispensing.

create or replace function public.lookup_prescription_by_code(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id  bigint;
  v_role      text;
  v_header    record;
  v_items     json;
  v_doctor    text;
begin
  select s.id, lower(trim(coalesce(s.role, '')))
  into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = auth.uid()
    and lower(trim(coalesce(s.status, ''))) = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Not authenticated');
  end if;

  if v_role <> 'pharmacist' then
    return json_build_object('error', 'Forbidden');
  end if;

  select ph.*
  into v_header
  from public.prescription_headers ph
  where trim(upper(ph.prescription_code)) = trim(upper(coalesce(p_code, '')))
  limit 1;

  if v_header.id is null then
    return json_build_object('error', 'Prescription not found');
  end if;

  -- Doctor name
  select trim(coalesce(s.first_name, '') || ' ' || coalesce(s.last_name, ''))
  into v_doctor
  from public.staff s
  where s.id = v_header.doctor_staff_id
  limit 1;

  select json_agg(json_build_object(
    'medicine_name', pi.medicine_name,
    'quantity',      pi.quantity,
    'unit',          pi.unit,
    'dosage',        pi.dosage,
    'frequency',     pi.frequency,
    'instructions',  pi.instructions
  ))
  into v_items
  from public.prescription_items pi
  where pi.prescription_id = v_header.id;

  return json_build_object(
    'id',                 v_header.id,
    'prescription_code',  v_header.prescription_code,
    'patient_identifier', v_header.patient_identifier,
    'doctor_name',        coalesce(v_doctor, 'Unknown'),
    'issued_at',          v_header.issued_at,
    'dispensing_status',  v_header.dispensing_status,
    'dispensed_at',       v_header.dispensed_at,
    'items',              coalesce(v_items, '[]'::json)
  );
end;
$$;

grant execute on function public.lookup_prescription_by_code(text) to authenticated;
