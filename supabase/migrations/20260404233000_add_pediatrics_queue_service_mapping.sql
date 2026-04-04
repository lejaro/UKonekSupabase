-- Add pediatrics service mapping for queue service discovery.

create or replace function public.list_available_queue_services(
  p_date date default current_date
)
returns table (
  service_key text,
  service_label text,
  doctor_count integer
)
language sql
security definer
set search_path = public
as $$
  with source as (
    select
      lower(trim(coalesce(s.doctor_specialization, ''))) as specialization
    from public.doctor_schedules ds
    join public.staff s on s.id = ds.doctor_staff_id
    where ds.schedule_date = coalesce(p_date, current_date)
      and lower(trim(coalesce(s.status, ''))) = 'active'
      and lower(trim(coalesce(s.role, ''))) = 'doctor'
  )
  select
    case
      when specialization like '%dental%' then 'dental'
      when specialization like '%prenatal%' or specialization like '%maternal%' or specialization like '%ob%' then 'prenatal'
      when specialization like '%pedia%' or specialization like '%pediatric%' or specialization like '%child%' then 'pediatrics'
      else 'general_consultation'
    end as service_key,
    case
      when specialization like '%dental%' then 'Dental'
      when specialization like '%prenatal%' or specialization like '%maternal%' or specialization like '%ob%' then 'Prenatal'
      when specialization like '%pedia%' or specialization like '%pediatric%' or specialization like '%child%' then 'Pediatrics'
      else 'General Consultation'
    end as service_label,
    count(*)::integer as doctor_count
  from source
  group by 1, 2
  order by 2;
$$;

grant execute on function public.list_available_queue_services(date) to authenticated;
