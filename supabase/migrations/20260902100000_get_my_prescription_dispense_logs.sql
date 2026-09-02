-- Expose prescription purchase / dispense event logs to authenticated citizens/patients.

create or replace function public.get_my_prescription_dispense_logs(
  p_prescription_id bigint default null,
  p_limit integer default 50
)
returns table (
  dispense_id           bigint,
  prescription_id       bigint,
  prescription_code     text,
  prescription_item_id  bigint,
  medicine_name         text,
  dosage                text,
  dispensed_quantity    integer,
  unit                  text,
  note                  text,
  pharmacist_name       text,
  dispensed_at          timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  select c.id into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid();

  if v_citizen_id is null then
    return;
  end if;

  return query
  select
    pid.id as dispense_id,
    ph.id as prescription_id,
    ph.prescription_code,
    pi.id as prescription_item_id,
    coalesce(m.name, pi.medicine_name) as medicine_name,
    coalesce(pi.dosage, '') as dosage,
    pid.dispensed_quantity,
    coalesce(pid.unit, pi.unit, '') as unit,
    coalesce(pid.note, '') as note,
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Pharmacist') as pharmacist_name,
    pid.dispensed_at
  from public.prescription_item_dispenses pid
  join public.prescription_headers ph on ph.id = pid.prescription_id
  join public.prescription_items pi on pi.id = pid.prescription_item_id
  left join public.medicines m on m.id = pid.medicine_id
  left join public.staff s on s.id = pid.dispensed_by_staff_id
  left join public.consultations con on con.id = ph.consultation_id
  where (
    con.patient_citizen_id = v_citizen_id
    or ph.patient_identifier = v_citizen_id::text
  )
  and (p_prescription_id is null or ph.id = p_prescription_id)
  order by pid.dispensed_at desc
  limit v_limit;
end;
$$;

revoke all on function public.get_my_prescription_dispense_logs(bigint, integer) from public;
grant execute on function public.get_my_prescription_dispense_logs(bigint, integer) to authenticated;
