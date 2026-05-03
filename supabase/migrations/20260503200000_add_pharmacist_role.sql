-- Add pharmacist role support.
-- Pharmacists can: SELECT, INSERT, UPDATE medicines (stock + expiry).
-- They cannot access patients, queue, consultations, prescriptions, schedules, or staff data.

begin;

-- Allow pharmacist to select medicines
drop policy if exists medicines_select_pharmacist on public.medicines;
create policy medicines_select_pharmacist
  on public.medicines
  for select
  using (
    exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

-- Allow pharmacist to insert medicines
drop policy if exists medicines_insert_pharmacist on public.medicines;
create policy medicines_insert_pharmacist
  on public.medicines
  for insert
  with check (
    exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

-- Allow pharmacist to update medicines (stock + expiry only enforced via application)
drop policy if exists medicines_update_pharmacist on public.medicines;
create policy medicines_update_pharmacist
  on public.medicines
  for update
  using (
    exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  )
  with check (
    qty >= 0
    and exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = 'pharmacist'
    )
  );

-- Add expiry_date column to medicines if not already present
alter table public.medicines
  add column if not exists expiry_date date,
  add column if not exists description text;

-- RPC: pharmacist_get_medicines — returns all medicines with computed status
create or replace function public.pharmacist_get_medicines()
returns table (
  id bigint,
  name text,
  description text,
  qty integer,
  unit text,
  expiry_date date,
  stock_status text,
  expiry_status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only pharmacists and doctors/nurses may call this
  if not exists (
    select 1 from public.staff s
    where s.auth_user_id = auth.uid()
      and lower(trim(coalesce(s.status, ''))) = 'active'
      and lower(trim(coalesce(s.role, ''))) in ('pharmacist', 'doctor', 'nurse', 'specialist')
  ) then
    raise exception 'Forbidden';
  end if;

  return query
  select
    m.id,
    m.name,
    m.description,
    m.qty,
    m.unit,
    m.expiry_date,
    case
      when m.qty = 0 then 'Out of Stock'
      when m.qty <= 10 then 'Low Stock'
      else 'In Stock'
    end as stock_status,
    case
      when m.expiry_date is null then 'No Expiry Set'
      when m.expiry_date < current_date then 'Expired'
      when m.expiry_date <= current_date + interval '30 days' then 'Expiring Soon'
      else 'Valid'
    end as expiry_status,
    m.created_at,
    m.updated_at
  from public.medicines m
  where m.archived_at is null
  order by m.name asc;
end;
$$;

grant execute on function public.pharmacist_get_medicines() to authenticated;

-- RPC: pharmacist_upsert_medicine
create or replace function public.pharmacist_upsert_medicine(
  p_id bigint default null,
  p_name text default null,
  p_description text default null,
  p_qty integer default 0,
  p_unit text default null,
  p_expiry_date date default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id bigint;
  v_role text;
  v_result json;
  v_medicine_id bigint;
begin
  select s.id, lower(trim(coalesce(s.role, '')))
    into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = auth.uid()
    and lower(trim(coalesce(s.status, ''))) = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Authentication required');
  end if;

  if v_role not in ('pharmacist', 'doctor', 'nurse') then
    return json_build_object('error', 'Forbidden: insufficient role');
  end if;

  if p_qty < 0 then
    return json_build_object('error', 'Stock quantity cannot be negative');
  end if;

  if p_id is null then
    -- INSERT
    if trim(coalesce(p_name, '')) = '' then
      return json_build_object('error', 'Medicine name is required');
    end if;

    insert into public.medicines (name, description, qty, unit, expiry_date, created_by_staff_id)
    values (
      trim(p_name),
      nullif(trim(coalesce(p_description, '')), ''),
      coalesce(p_qty, 0),
      nullif(trim(coalesce(p_unit, '')), ''),
      p_expiry_date,
      v_staff_id
    )
    returning id into v_medicine_id;

    return json_build_object('ok', true, 'id', v_medicine_id, 'action', 'inserted');
  else
    -- UPDATE (stock + expiry + description only; name is protected)
    update public.medicines
    set
      qty = coalesce(p_qty, qty),
      expiry_date = coalesce(p_expiry_date, expiry_date),
      description = coalesce(nullif(trim(coalesce(p_description, '')), ''), description)
    where id = p_id
      and archived_at is null;

    if not found then
      return json_build_object('error', 'Medicine not found or archived');
    end if;

    return json_build_object('ok', true, 'id', p_id, 'action', 'updated');
  end if;
end;
$$;

grant execute on function public.pharmacist_upsert_medicine(bigint, text, text, integer, text, date) to authenticated;

commit;
