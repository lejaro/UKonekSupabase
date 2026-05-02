-- Replace placeholder services with actual services from AFM Roquero Medical Clinic.

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
  -- Actual services from the clinic flyer
  select 'medical_consultation' as service_key, 'Medical Consultation' as service_label, 1 as doctor_count
  union all
  select 'animal_bite_center' as service_key, 'Animal Bite Center' as service_label, 1 as doctor_count
  union all
  select 'family_preventive_care' as service_key, 'Family Preventive Care & Wellness' as service_label, 1 as doctor_count
  union all
  select 'family_counselling' as service_key, 'Family Counselling' as service_label, 1 as doctor_count
  union all
  select 'prenatal_gyne' as service_key, 'Pre Natal and Gyne Consult' as service_label, 1 as doctor_count
  union all
  select 'pediatric_illness' as service_key, 'Pediatric Illness and Wellness' as service_label, 1 as doctor_count
  union all
  select 'therapeutic_lifestyle' as service_key, 'Intensive Therapeutic Lifestyle Change' as service_label, 1 as doctor_count
  union all
  select 'lifestyle_health_check' as service_key, 'Lifestyle Health Check' as service_label, 1 as doctor_count
  union all
  select 'geriatric_care' as service_key, 'Geriatric & Palliative Care' as service_label, 1 as doctor_count
  union all
  select 'iv_hydration' as service_key, 'IV Hydration' as service_label, 1 as doctor_count
  union all
  select 'onsite_ape' as service_key, 'On site APE' as service_label, 1 as doctor_count
  union all
  select 'pre_employment_exam' as service_key, 'Pre- Employment Exam' as service_label, 1 as doctor_count
  union all
  select 'minor_surgery' as service_key, 'Minor Surgery' as service_label, 1 as doctor_count
  union all
  select 'cauterization' as service_key, 'Cauterization' as service_label, 1 as doctor_count
  union all
  select 'ecg' as service_key, 'ECG' as service_label, 1 as doctor_count
  union all
  select 'lab_test' as service_key, 'Clinical Laboratory test' as service_label, 1 as doctor_count
  union all
  select 'immunization' as service_key, 'Immunization' as service_label, 1 as doctor_count
  order by service_label;
$$;

grant execute on function public.list_available_queue_services(date) to authenticated;
