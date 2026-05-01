-- Remove Doctor Schedules Feature

drop table if exists public.doctor_schedules cascade;

drop function if exists public.set_doctor_schedule_updated_at() cascade;
drop function if exists public.list_doctor_schedules() cascade;
drop function if exists public.upsert_doctor_schedule_admin(bigint, bigint, date, time, time, text) cascade;
drop function if exists public.delete_doctor_schedule_admin(bigint) cascade;
drop function if exists public.purge_expired_doctor_schedules() cascade;
drop function if exists public.list_available_doctor_schedules(bigint, date, date) cascade;
