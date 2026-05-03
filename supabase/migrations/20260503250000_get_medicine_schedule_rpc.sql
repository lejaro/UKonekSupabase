-- get_my_medicine_schedule: returns all active (dispensed) prescription items
-- for the logged-in citizen, including computed daily dose times derived from
-- the frequency field. Used by the mobile medicine scheduler.
-- "Active" = dispensed prescriptions (pharmacist confirmed delivery).

create or replace function public.get_my_medicine_schedule()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_result     json;
begin
  select c.id
  into   v_citizen_id
  from   public.citizens c
  where  c.auth_user_id = auth.uid();

  if v_citizen_id is null then
    return '[]'::json;
  end if;

  select json_agg(row_to_json(t) order by t.issued_at desc, t.prescription_item_id asc)
  into   v_result
  from (
    select
      pi.id                                                         as prescription_item_id,
      ph.id                                                         as prescription_id,
      ph.prescription_code,
      ph.dispensing_status,
      ph.issued_at,
      ph.dispensed_at,
      coalesce(
        nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
        'Doctor'
      )                                                             as doctor_name,
      pi.medicine_name,
      pi.quantity,
      coalesce(pi.unit,            '')                             as unit,
      coalesce(pi.dosage,          '')                             as dosage,
      coalesce(pi.frequency,       '')                             as frequency,
      coalesce(pi.instructions,    '')                             as instructions,
      coalesce(pi.additional_info, '')                             as additional_info
    from   public.prescription_items pi
    join   public.prescription_headers ph on ph.id = pi.prescription_id
    left   join public.staff s on s.id = ph.doctor_staff_id
    where  ph.dispensing_status = 'dispensed'
      and  (
        exists (
          select 1
          from   public.consultations con
          where  con.id = ph.consultation_id
            and  con.patient_citizen_id = v_citizen_id
        )
        or ph.patient_identifier = v_citizen_id::text
      )
  ) t;

  return coalesce(v_result, '[]'::json);
end;
$$;

revoke all on function public.get_my_medicine_schedule() from public;
grant execute on function public.get_my_medicine_schedule() to authenticated;
