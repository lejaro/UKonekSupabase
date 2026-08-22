-- Expose prescription item balances to patient clients after partial dispensing.

drop function if exists public.get_my_prescribed_medicines(integer);

create or replace function public.get_my_prescribed_medicines(
  p_limit integer default 50
)
returns table (
  prescription_id       bigint,
  prescription_code     text,
  dispensing_status     text,
  issued_at             timestamptz,
  dispensed_at          timestamptz,
  doctor_name           text,
  medicine_name         text,
  quantity              integer,
  dispensed_quantity    integer,
  remaining_quantity    integer,
  unit                  text,
  dosage                text,
  frequency             text,
  duration              text,
  instructions          text,
  additional_info       text,
  is_dispensed          boolean
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
    ph.id,
    ph.prescription_code,
    ph.dispensing_status,
    ph.issued_at,
    ph.dispensed_at,
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor'),
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.dispensed_quantity, 0),
    coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)),
    coalesce(pi.unit, ''),
    coalesce(pi.dosage, ''),
    coalesce(pi.frequency, ''),
    coalesce(pi.duration, ''),
    coalesce(pi.instructions, ''),
    coalesce(pi.additional_info, ''),
    coalesce(pi.is_dispensed, false)
  from public.prescription_items pi
  join public.prescription_headers ph on ph.id = pi.prescription_id
  left join public.consultations con on con.id = ph.consultation_id
  left join public.staff s on s.id = ph.doctor_staff_id
  where con.patient_citizen_id = v_citizen_id
     or ph.patient_identifier = v_citizen_id::text
  order by ph.issued_at desc, pi.id asc
  limit v_limit;
end;
$$;

revoke all on function public.get_my_prescribed_medicines(integer) from public;
grant execute on function public.get_my_prescribed_medicines(integer) to authenticated;

-- Schedule only the quantity actually dispensed, including partial prescriptions.
create or replace function public.get_my_medicine_schedule()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_result json;
begin
  select c.id into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid();

  if v_citizen_id is null then
    return '[]'::json;
  end if;

  select json_agg(row_to_json(t) order by t.issued_at desc, t.prescription_item_id asc)
  into v_result
  from (
    select
      pi.id as prescription_item_id,
      ph.id as prescription_id,
      ph.prescription_code,
      ph.dispensing_status,
      ph.issued_at,
      ph.dispensed_at,
      coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') as doctor_name,
      pi.medicine_name,
      coalesce(pi.dispensed_quantity, 0) as quantity,
      coalesce(pi.quantity, 0) as prescribed_quantity,
      coalesce(pi.dispensed_quantity, 0) as dispensed_quantity,
      coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) as remaining_quantity,
      coalesce(pi.unit, '') as unit,
      coalesce(pi.dosage, '') as dosage,
      coalesce(pi.frequency, '') as frequency,
      coalesce(pi.duration, '') as duration,
      coalesce(pi.instructions, '') as instructions,
      coalesce(pi.additional_info, '') as additional_info
    from public.prescription_items pi
    join public.prescription_headers ph on ph.id = pi.prescription_id
    left join public.staff s on s.id = ph.doctor_staff_id
    where coalesce(pi.dispensed_quantity, 0) > 0
      and ph.dispensing_status in ('partial', 'dispensed')
      and (
        exists (
          select 1 from public.consultations con
          where con.id = ph.consultation_id
            and con.patient_citizen_id = v_citizen_id
        )
        or ph.patient_identifier = v_citizen_id::text
      )
  ) t;

  return coalesce(v_result, '[]'::json);
end;
$$;
