-- Update get_my_prescribed_medicines to include duration and fix instructions visibility
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
  unit                  text,
  dosage                text,
  frequency             text,
  duration              text,
  instructions          text,
  additional_info       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id   bigint;
  v_limit        integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  select c.id
  into   v_citizen_id
  from   public.citizens c
  where  c.auth_user_id = auth.uid();

  if v_citizen_id is null then
    return;
  end if;

  return query
  select
    ph.id                                                      as prescription_id,
    ph.prescription_code,
    ph.dispensing_status,
    ph.issued_at,
    ph.dispensed_at,
    coalesce(
      nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
      'Doctor'
    )                                                          as doctor_name,
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.unit,            '')                          as unit,
    coalesce(pi.dosage,          '')                          as dosage,
    coalesce(pi.frequency,       '')                          as frequency,
    coalesce(pi.duration,        '')                          as duration,
    coalesce(pi.instructions,    '')                          as instructions,
    coalesce(pi.additional_info, '')                          as additional_info
  from   public.prescription_items pi
  join   public.prescription_headers ph on ph.id = pi.prescription_id
  left   join public.consultations con on con.id = ph.consultation_id
  left   join public.staff s on s.id = ph.doctor_staff_id
  where  (
    -- Linked via consultation → citizen
    con.patient_citizen_id = v_citizen_id
    or
    -- Directly linked by patient_identifier = citizen's id
    ph.patient_identifier = v_citizen_id::text
  )
  order  by ph.issued_at desc, pi.id asc
  limit  v_limit;
end;
$$;

revoke all on function public.get_my_prescribed_medicines(integer) from public;
grant execute on function public.get_my_prescribed_medicines(integer) to authenticated;
