-- Reliable staff/schedule RPCs to avoid brittle client-side RLS edge cases.

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
declare
  v_role text;
begin
  v_role := lower(coalesce(public.get_staff_role(), ''));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

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

grant execute on function public.list_staff_accounts() to authenticated;

create or replace function public.list_doctor_schedules()
returns setof public.doctor_schedules
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  v_role := lower(coalesce(public.get_staff_role(), ''));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

  return query
  select ds.*
  from public.doctor_schedules ds
  order by ds.schedule_date asc, ds.start_time asc;
end;
$$;

grant execute on function public.list_doctor_schedules() to authenticated;

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
  v_schedule public.doctor_schedules;
begin
  v_role := lower(coalesce(public.get_staff_role(), ''));
  if v_role <> 'admin' then
    raise exception 'Forbidden: admin role required';
  end if;

  select s.id into v_actor_staff_id
  from public.staff s
  where s.auth_user_id = auth.uid()
    and lower(coalesce(s.status, '')) = 'active'
  limit 1;

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

grant execute on function public.upsert_doctor_schedule_admin(bigint, bigint, date, time, time, text) to authenticated;

create or replace function public.delete_doctor_schedule_admin(p_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  v_role := lower(coalesce(public.get_staff_role(), ''));
  if v_role <> 'admin' then
    raise exception 'Forbidden: admin role required';
  end if;

  delete from public.doctor_schedules where id = p_id;
  return true;
end;
$$;

grant execute on function public.delete_doctor_schedule_admin(bigint) to authenticated;
