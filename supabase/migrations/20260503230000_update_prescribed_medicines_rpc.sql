-- Drop old function signature before recreating with new return type
drop function if exists public.get_my_prescribed_medicines(integer);

-- Update get_my_prescribed_medicines RPC to:
-- 1. Return full prescription item details (dosage, frequency, instructions,
--    additional_info, unit, prescription_code, dispensing_status)
-- 2. Match by patient_citizen_id OR patient_identifier (citizen's own ticket code)
--    so prescriptions not linked to a consultation are still visible

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
  instructions          text,
  additional_info       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id   bigint;
  v_identifier   text;
  v_limit        integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  -- Resolve citizen from session
  select c.id,
         c.id::text
  into   v_citizen_id, v_identifier
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
    coalesce(pi.unit,             '')                         as unit,
    coalesce(pi.dosage,           '')                         as dosage,
    coalesce(pi.frequency,        '')                         as frequency,
    coalesce(pi.instructions,     '')                         as instructions,
    coalesce(pi.additional_info,  '')                         as additional_info
  from   public.prescription_items pi
  join   public.prescription_headers ph on ph.id = pi.prescription_id
  left   join public.staff s on s.id = ph.doctor_staff_id
  where  (
    -- Linked through consultation
    exists (
      select 1
      from   public.consultations con
      where  con.id = ph.consultation_id
        and  con.patient_citizen_id = v_citizen_id
    )
    or
    -- Linked by patient_identifier matching citizen's id or ticket_code
    ph.patient_identifier = v_citizen_id::text
    or
    ph.patient_identifier = v_identifier
  )
  order  by ph.issued_at desc, pi.id asc
  limit  v_limit;
end;
$$;

revoke all on function public.get_my_prescribed_medicines(integer) from public;
grant execute on function public.get_my_prescribed_medicines(integer) to authenticated;
