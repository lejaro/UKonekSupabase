-- Harden staff/schedule RPC role resolution and avoid false negatives.

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
    s.created_at,
    s.auth_user_id
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
  order by s.id desc;
end;
$$;

create or replace function public.list_doctor_schedules()
returns setof public.doctor_schedules
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select ds.*
  from public.doctor_schedules ds
  order by ds.schedule_date asc, ds.start_time asc;
end;
$$;

create or replace function public.upsert_doctor_schedule_admin(
  p_id bigint default null,
  p_doctor_staff_id bigint default null,
  p_schedule_date date default null,
  p_start_time time default null,
  p_end_time time default null,
  p_notes text default null
)
returns public.doctor_schedules
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_actor_staff_id bigint;
  v_user_email text;
  v_schedule public.doctor_schedules;
begin
  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  update public.staff
  set auth_user_id = auth.uid()
  where auth.uid() is not null
    and auth_user_id is null
    and lower(email) = v_user_email
    and lower(coalesce(status, '')) = 'active';

  select lower(coalesce(s.role, '')), s.id
    into v_role, v_actor_staff_id
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
    and (
      (auth.uid() is not null and s.auth_user_id = auth.uid())
      or (v_user_email <> '' and lower(s.email) = v_user_email)
    )
  order by case when lower(coalesce(s.role, '')) = 'admin' then 0 else 1 end, s.id asc
  limit 1;

  if v_role <> 'admin' then
    raise exception 'Forbidden: admin role required';
  end if;

  if p_id is null then
    insert into public.doctor_schedules (
      doctor_staff_id,
      doctor_name,
      schedule_date,
      start_time,
      end_time,
      notes,
      created_by_staff_id
    )
    select
      p_doctor_staff_id,
      trim(concat(coalesce(d.first_name, ''), ' ', coalesce(d.last_name, ''))),
      p_schedule_date,
      p_start_time,
      p_end_time,
      nullif(trim(coalesce(p_notes, '')), ''),
      v_actor_staff_id
    from public.staff d
    where d.id = p_doctor_staff_id
    returning * into v_schedule;
  else
    update public.doctor_schedules ds
    set
      doctor_staff_id = p_doctor_staff_id,
      doctor_name = trim(concat(coalesce(d.first_name, ''), ' ', coalesce(d.last_name, ''))),
      schedule_date = p_schedule_date,
      start_time = p_start_time,
      end_time = p_end_time,
      notes = nullif(trim(coalesce(p_notes, '')), '')
    from public.staff d
    where ds.id = p_id
      and d.id = p_doctor_staff_id
    returning ds.* into v_schedule;
  end if;

  if v_schedule.id is null then
    raise exception 'Failed to save schedule';
  end if;

  return v_schedule;
end;
$$;

create or replace function public.delete_doctor_schedule_admin(p_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_user_email text;
begin
  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  update public.staff
  set auth_user_id = auth.uid()
  where auth.uid() is not null
    and auth_user_id is null
    and lower(email) = v_user_email
    and lower(coalesce(status, '')) = 'active';

  select lower(coalesce(s.role, '')) into v_role
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
    and (
      (auth.uid() is not null and s.auth_user_id = auth.uid())
      or (v_user_email <> '' and lower(s.email) = v_user_email)
    )
  order by case when lower(coalesce(s.role, '')) = 'admin' then 0 else 1 end, s.id asc
  limit 1;

  if v_role <> 'admin' then
    raise exception 'Forbidden: admin role required';
  end if;

  delete from public.doctor_schedules where id = p_id;
  return true;
end;
$$;
