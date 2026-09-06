-- Fix is_admin() role resolution and admin RPC permissions
-- 1. Redefine is_admin() to include 'admin' role along with 'doctor' and 'nurse',
--    ensure case-insensitive status check ('active' / 'Active'), and allow verified JWT email matching.
-- 2. Backfill unlinked staff auth_user_id records where email matches auth.users.
-- 3. Redefine delete_staff_member with self-deletion guardrail and clean auth.users deletion.
-- 4. Redefine upsert_doctor_schedule_admin and delete_doctor_schedule_admin to use is_admin().
-- 5. Redefine set_staff_specialization_admin to use is_admin().
-- 6. Redefine approve_pending_staff to insert normalized 'active' status.

-- ---------------------------------------------------------------------------
-- 1. Redefine public.is_admin()
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
as $$
  select exists (
    select 1
    from public.staff
    where (
      auth_user_id = auth.uid()
      or (
        auth.jwt()->>'email' is not null
        and lower(trim(email)) = lower(trim(auth.jwt()->>'email'))
      )
    )
    and lower(trim(coalesce(role, ''))) in ('admin', 'doctor', 'nurse')
    and lower(trim(coalesce(status, ''))) = 'active'
  );
$$;

grant execute on function public.is_admin() to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2. Backfill & Normalize Staff
-- ---------------------------------------------------------------------------
-- Link any staff records whose auth_user_id is missing but exist in auth.users
update public.staff s
set auth_user_id = u.id
from auth.users u
where lower(trim(s.email)) = lower(trim(u.email))
  and s.auth_user_id is null;

-- Normalize existing status values in staff table to lowercase 'active'
update public.staff
set status = 'active'
where lower(trim(coalesce(status, ''))) = 'active'
  and status <> 'active';

-- ---------------------------------------------------------------------------
-- 3. Redefine public.delete_staff_member
-- ---------------------------------------------------------------------------
create or replace function public.delete_staff_member(target_staff_id bigint)
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_auth_user_id uuid;
  v_staff_email text;
  v_current_email text;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  select auth_user_id, lower(trim(coalesce(email, '')))
    into v_auth_user_id, v_staff_email
  from public.staff
  where id = target_staff_id;

  if not found then
    raise exception 'Staff not found';
  end if;

  v_current_email := lower(trim(coalesce(auth.jwt()->>'email', '')));

  -- Guardrail: User cannot delete their own account
  if (v_auth_user_id is not null and v_auth_user_id = auth.uid())
     or (v_current_email <> '' and v_staff_email = v_current_email) then
    raise exception 'Guardrail Active: You cannot delete your own account';
  end if;

  delete from public.staff
  where id = target_staff_id;

  if v_auth_user_id is not null then
    delete from auth.users
    where id = v_auth_user_id;
  elsif v_staff_email <> '' then
    delete from auth.users
    where lower(trim(email)) = v_staff_email;
  end if;

  return json_build_object('success', true);
end;
$$;

grant execute on function public.delete_staff_member(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Redefine Schedule Admin Functions
-- ---------------------------------------------------------------------------
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
  v_actor_staff_id bigint;
  v_schedule public.doctor_schedules;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  perform public.purge_expired_doctor_schedules();

  select s.id into v_actor_staff_id
  from public.staff s
  where (
    s.auth_user_id = auth.uid()
    or (
      auth.jwt()->>'email' is not null
      and lower(trim(s.email)) = lower(trim(auth.jwt()->>'email'))
    )
  )
  and lower(trim(coalesce(s.status, ''))) = 'active'
  order by case when lower(trim(coalesce(s.role, ''))) = 'admin' then 0 else 1 end, s.id asc
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
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  delete from public.doctor_schedules where id = p_id;
  return true;
end;
$$;

grant execute on function public.delete_doctor_schedule_admin(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Redefine Specialization Admin Function
-- ---------------------------------------------------------------------------
create or replace function public.set_staff_specialization_admin(
  target_staff_id bigint,
  p_specialization text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.staff%rowtype;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'Forbidden: admin role required');
  end if;

  update public.staff
     set doctor_specialization = nullif(trim(coalesce(p_specialization, '')), '')
   where id = target_staff_id
   returning * into updated_row;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Staff record not found.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'staff', jsonb_build_object(
      'id', updated_row.id,
      'role', updated_row.role,
      'doctor_specialization', updated_row.doctor_specialization
    )
  );
end;
$$;

grant execute on function public.set_staff_specialization_admin(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Redefine Staff Approval with Normalized Status
-- ---------------------------------------------------------------------------
create or replace function public.approve_pending_staff(pending_id bigint)
returns json
language plpgsql
security definer
as $$
declare
  v_pending record;
  v_resolved_auth_user_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  select * into v_pending
  from public.pending_staff
  where id = pending_id;

  if v_pending is null then
    raise exception 'Pending staff not found';
  end if;

  v_resolved_auth_user_id := coalesce(
    v_pending.auth_user_id,
    (
      select u.id
      from auth.users u
      where lower(u.email) = lower(v_pending.email)
      order by u.created_at desc
      limit 1
    )
  );

  insert into public.staff (
    first_name, middle_name, last_name, birthday, gender,
    username, employee_id, email, role, consent_given,
    status, auth_user_id
  ) values (
    v_pending.first_name, v_pending.middle_name, v_pending.last_name,
    v_pending.birthday, v_pending.gender, v_pending.username,
    v_pending.employee_id, v_pending.email, v_pending.role,
    v_pending.consent_given, 'active', v_resolved_auth_user_id
  );

  delete from public.pending_staff where id = pending_id;

  return json_build_object('message', 'Staff approved successfully');
end;
$$;

grant execute on function public.approve_pending_staff(bigint) to authenticated;
