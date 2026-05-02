-- Update list_available_queue_services to return 5 placeholder services regardless of doctor schedules.
-- This ensures that citizens can always see available services in the mobile app.

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
  -- Hardcoded placeholder services as requested
  select 'general_consultation' as service_key, 'General Consultation' as service_label, 1 as doctor_count
  union all
  select 'pediatrics' as service_key, 'Pediatrics' as service_label, 1 as doctor_count
  union all
  select 'dental' as service_key, 'Dental' as service_label, 1 as doctor_count
  union all
  select 'prenatal' as service_key, 'Prenatal' as service_label, 1 as doctor_count
  union all
  select 'lab_xray' as service_key, 'Laboratory & X-Ray' as service_label, 1 as doctor_count
  order by service_label;
$$;

grant execute on function public.list_available_queue_services(date) to authenticated;
