-- Remove Appointments Feature

drop table if exists public.appointments cascade;

drop function if exists public.get_available_doctor_slots(bigint, date, date);
drop function if exists public.book_appointment(bigint, bigint, date, time, text);
drop function if exists public.list_my_appointments();
drop function if exists public.list_doctor_appointments(varchar, date, date);
drop function if exists public.list_all_appointments(varchar, date, date, bigint);
