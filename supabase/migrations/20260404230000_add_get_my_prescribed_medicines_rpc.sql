-- Allow citizens to read their own prescribed medicines for mobile dashboard.

create or replace function public.get_my_prescribed_medicines(
  p_limit integer default 10
)
returns table (
  medicine_name text,
  quantity integer,
  unit text,
  doctor_name text,
  issued_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_limit integer := greatest(1, least(coalesce(p_limit, 10), 50));
begin
  select c.id
  into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid();

  if v_citizen_id is null then
    return;
  end if;

  return query
  select
    pi.medicine_name,
    pi.quantity,
    coalesce(pi.unit, ''),
    coalesce(nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''), 'Doctor') as doctor_name,
    ph.issued_at
  from public.prescription_items pi
  join public.prescription_headers ph on ph.id = pi.prescription_id
  left join public.consultations c on c.id = ph.consultation_id
  left join public.staff s on s.id = ph.doctor_staff_id
  where c.patient_citizen_id = v_citizen_id
  order by ph.issued_at desc, pi.id desc
  limit v_limit;
end;
$$;

revoke all on function public.get_my_prescribed_medicines(integer) from public;
grant execute on function public.get_my_prescribed_medicines(integer) to authenticated;
