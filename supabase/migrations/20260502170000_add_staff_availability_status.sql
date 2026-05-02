-- Add staff availability status tracking and automation.

alter table public.staff
  add column if not exists availability_status text not null default 'available';

update public.staff
set availability_status = 'available'
where availability_status is null or trim(availability_status) = '';

alter table public.staff
  drop constraint if exists staff_availability_status_valid;

alter table public.staff
  add constraint staff_availability_status_valid
  check (lower(trim(availability_status)) in ('available', 'on_break', 'unavailable'));

drop function if exists public.get_staff_profile();
create or replace function public.get_staff_profile()
returns json
language plpgsql
volatile
security definer
as $$
declare
  v_user_email text;
  v_profile json;
begin
  v_user_email := auth.jwt()->>'email';

  if v_user_email is null then
    return null;
  end if;

  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status, availability_status
    from public.staff
    where auth_user_id = auth.uid()
      and lower(coalesce(status, '')) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    return v_profile;
  end if;

  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status, availability_status
    from public.staff
    where lower(email) = lower(v_user_email)
      and lower(coalesce(status, '')) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    update public.staff
    set auth_user_id = auth.uid()
    where lower(email) = lower(v_user_email)
      and auth_user_id is null;

    return v_profile;
  end if;

  return null;
end;
$$;

drop function if exists public.list_staff_accounts();
create or replace function public.list_staff_accounts()
returns table (
  id bigint,
  first_name varchar,
  middle_name varchar,
  last_name varchar,
  birthday date,
  gender varchar,
  username varchar,
  employee_id varchar,
  email varchar,
  role varchar,
  status varchar,
  doctor_specialization text,
  is_online boolean,
  last_seen timestamptz,
  availability_status text,
  created_at timestamptz,
  auth_user_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    s.id,
    s.first_name,
    s.middle_name,
    s.last_name,
    s.birthday,
    s.gender,
    s.username,
    s.employee_id,
    s.email,
    s.role,
    s.status,
    s.doctor_specialization,
    s.is_online,
    s.last_seen,
    s.availability_status,
    s.created_at,
    s.auth_user_id
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
  order by s.id desc;
end;
$$;

drop function if exists public.list_available_doctor_schedules(date, date);
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
  notes text,
  availability_status text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Forbidden: authentication required';
  end if;

  perform public.purge_expired_doctor_schedules();

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
    ds.notes,
    s.availability_status as availability_status
  from public.doctor_schedules ds
  join public.staff s
    on s.id = ds.doctor_staff_id
  where lower(trim(coalesce(s.role, ''))) = 'doctor'
    and lower(trim(coalesce(s.status, ''))) = 'active'
    and lower(trim(coalesce(s.availability_status, 'available'))) in ('available', 'on_break')
    and ds.schedule_date >= p_date_from
    and ds.schedule_date <= p_date_to
  order by ds.schedule_date asc, ds.start_time asc;
end;
$$;

grant execute on function public.list_available_doctor_schedules(date, date) to authenticated;

drop function if exists public.set_staff_availability(bigint, text);
create or replace function public.set_staff_availability(
  p_target_staff_id bigint default null,
  p_status text default 'available'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_email text;
  v_actor_staff_id bigint;
  v_actor_role text;
  v_target_staff_id bigint;
  v_status text;
begin
  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  if auth.uid() is null and v_user_email = '' then
    raise exception 'Forbidden: authentication required';
  end if;

  update public.staff
  set auth_user_id = auth.uid()
  where auth.uid() is not null
    and auth_user_id is null
    and lower(email) = v_user_email
    and lower(coalesce(status, '')) = 'active';

  select s.id, lower(coalesce(s.role, ''))
    into v_actor_staff_id, v_actor_role
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
    and (
      (auth.uid() is not null and s.auth_user_id = auth.uid())
      or (v_user_email <> '' and lower(s.email) = v_user_email)
    )
  order by case when lower(coalesce(s.role, '')) = 'doctor' then 0 else 1 end, s.id asc
  limit 1;

  if v_actor_staff_id is null then
    raise exception 'Active staff account required';
  end if;

  if v_actor_role <> 'doctor' then
    raise exception 'Forbidden: doctor role required';
  end if;

  v_target_staff_id := coalesce(p_target_staff_id, v_actor_staff_id);
  v_status := lower(trim(coalesce(p_status, 'available')));
  if v_status = 'on break' then
    v_status := 'on_break';
  end if;

  if v_status not in ('available', 'on_break', 'unavailable') then
    raise exception 'Invalid availability status';
  end if;

  update public.staff
  set availability_status = v_status
  where id = v_target_staff_id
    and lower(trim(coalesce(role, ''))) in ('doctor', 'nurse')
    and lower(coalesce(status, '')) = 'active';

  if not found then
    raise exception 'Unable to update staff availability';
  end if;

  return json_build_object('staff_id', v_target_staff_id, 'availability_status', v_status);
end;
$$;

grant execute on function public.set_staff_availability(bigint, text) to authenticated;

drop function if exists public.set_staff_unavailable_after_hours();
create or replace function public.set_staff_unavailable_after_hours()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_local timestamptz;
  v_local_hour int;
  v_updated integer := 0;
begin
  v_local := timezone('Asia/Manila', v_now);
  v_local_hour := extract(hour from v_local);

  if v_local_hour <> 17 then
    return 0;
  end if;

  update public.staff
  set availability_status = 'unavailable'
  where lower(trim(coalesce(role, ''))) in ('doctor', 'nurse')
    and lower(coalesce(status, '')) = 'active'
    and lower(trim(coalesce(availability_status, ''))) <> 'unavailable';

  get diagnostics v_updated = row_count;
  return coalesce(v_updated, 0);
end;
$$;

create extension if not exists pg_cron;

-- Run hourly; function enforces 5:00 PM Asia/Manila.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'staff_unavailable_5pm_manila') then
    perform cron.unschedule('staff_unavailable_5pm_manila');
  end if;

  perform cron.schedule(
    'staff_unavailable_5pm_manila',
    '0 * * * *',
    $cmd$ select public.set_staff_unavailable_after_hours(); $cmd$
  );
end;
$$;

-- Ensure staff availability updates broadcast via Realtime.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'staff'
  ) then
    alter publication supabase_realtime add table public.staff;
  end if;
end;
$$;
