-- Fix pharmacist prescription lookup to use the staff schema's first_name/last_name columns.
-- The previous version referenced citizen-style firstname/surname columns that do not exist on staff.

create or replace function public.lookup_prescription_by_code(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id bigint;
  v_role text;
  v_header record;
  v_items json;
  v_doctor text;
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

  select trim(concat_ws(' ', s.first_name, s.last_name))
  into v_doctor
  from public.staff s
  where s.id = v_header.doctor_staff_id
  limit 1;

  select json_agg(json_build_object(
    'id',                 pi.id,
    'medicine_name',      pi.medicine_name,
    'quantity',           pi.quantity,
    'dispensed_quantity', coalesce(pi.dispensed_quantity, 0),
    'remaining_quantity', coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)),
    'is_dispensed',       coalesce(pi.is_dispensed, false),
    'last_dispensed_at',  pi.last_dispensed_at,
    'unit',               pi.unit,
    'dosage',             pi.dosage,
    'frequency',          pi.frequency,
    'instructions',       pi.instructions
  ) order by pi.id)
  into v_items
  from public.prescription_items pi
  where pi.prescription_id = v_header.id;

  return json_build_object(
    'id',                   v_header.id,
    'prescription_code',    v_header.prescription_code,
    'patient_identifier',   v_header.patient_identifier,
    'doctor_name',          coalesce(nullif(v_doctor, ''), 'Unknown'),
    'issued_at',            v_header.issued_at,
    'dispensing_status',    v_header.dispensing_status,
    'dispensed_at',         v_header.dispensed_at,
    'first_dispensed_at',   v_header.first_dispensed_at,
    'last_dispensed_at',    v_header.last_dispensed_at,
    'items',                coalesce(v_items, '[]'::json)
  );
end;
$$;

grant execute on function public.lookup_prescription_by_code(text) to authenticated;
