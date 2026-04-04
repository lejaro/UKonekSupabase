-- Automatically remove doctor schedules that already passed their end time.

create or replace function public.purge_expired_doctor_schedules()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  delete from public.doctor_schedules ds
  where (ds.schedule_date + ds.end_time) < now();

  get diagnostics v_deleted = row_count;
  return coalesce(v_deleted, 0);
end;
$$;

grant execute on function public.purge_expired_doctor_schedules() to authenticated;

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

  perform public.purge_expired_doctor_schedules();

  return query
  select ds.*
  from public.doctor_schedules ds
  order by ds.schedule_date asc, ds.start_time asc;
end;
$$;

grant execute on function public.list_doctor_schedules() to authenticated;

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

  perform public.purge_expired_doctor_schedules();

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
