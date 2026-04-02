-- Remove room from doctor schedules as requested.

alter table if exists public.doctor_schedules
  drop column if exists room;