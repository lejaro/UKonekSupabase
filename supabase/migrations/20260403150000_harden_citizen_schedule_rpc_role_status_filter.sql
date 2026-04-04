-- Harden citizen doctor schedule RPC to tolerate role/status casing and whitespace.

create or replace function public.list_available_doctor_schedules(
  p_date_from date default current_date,
  p_date_to date default (current_date + interval '30 days')::date
)
returns table (
  id bigint,
  doctor_staff_id bigint,
  doctor_name varchar,
  specialization text,
  schedule_date date,
  start_time time,
  end_time time,
  notes text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Forbidden: authentication required';
  end if;

  return query
  select
    ds.id,
    ds.doctor_staff_id,
    coalesce(
      nullif(trim(ds.doctor_name), ''),
      trim(concat(coalesce(s.first_name, ''), ' ', coalesce(s.last_name, '')))
    )::varchar as doctor_name,
    coalesce(s.doctor_specialization, '')::text as specialization,
    ds.schedule_date,
    ds.start_time,
    ds.end_time,
    ds.notes
  from public.doctor_schedules ds
  join public.staff s
    on s.id = ds.doctor_staff_id
  where lower(trim(coalesce(s.role, ''))) = 'doctor'
    and lower(trim(coalesce(s.status, ''))) = 'active'
    and ds.schedule_date >= p_date_from
    and ds.schedule_date <= p_date_to
  order by ds.schedule_date asc, ds.start_time asc;
end;
$$;

grant execute on function public.list_available_doctor_schedules(date, date) to authenticated;
