-- Map legacy roles: admin -> doctor (elevated / command center), staff -> nurse.
-- Elevated DB helper is_admin() now means active staff with role doctor.

begin;

update public.staff
set role = 'doctor'
where lower(trim(coalesce(role, ''))) = 'admin';

update public.staff
set role = 'nurse'
where lower(trim(coalesce(role, ''))) = 'staff';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
as $$
  select exists (
    select 1
    from public.staff
    where auth_user_id = auth.uid()
      and lower(trim(coalesce(role, ''))) = 'doctor'
      and lower(coalesce(status, '')) = 'active'
  );
$$;

-- Bootstrap row for admin@ukonek.local uses role doctor (was admin).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  v_role := lower(coalesce(new.raw_user_meta_data->>'role', ''));

  if lower(coalesce(new.email, '')) = 'admin@ukonek.local' then
    insert into public.staff (
      first_name,
      middle_name,
      last_name,
      birthday,
      gender,
      username,
      employee_id,
      email,
      role,
      consent_given,
      status,
      auth_user_id
    ) values (
      'System',
      '-',
      'Admin',
      date '1990-01-01',
      'Prefer not to say',
      'admin',
      '01',
      'admin@ukonek.local',
      'doctor',
      true,
      'Active',
      new.id
    )
    on conflict (email)
    do update set
      role = excluded.role,
      status = excluded.status,
      auth_user_id = excluded.auth_user_id;

    return new;
  end if;

  if v_role = 'citizen' then
    insert into public.citizens (
      firstname, surname, middle_initial, date_of_birth, age,
      contact_number, sex, email, complete_address,
      emergency_contact_complete_name, emergency_contact_contact_number,
      relation, username, role, auth_user_id
    ) values (
      coalesce(new.raw_user_meta_data->>'firstname', ''),
      coalesce(new.raw_user_meta_data->>'surname', ''),
      new.raw_user_meta_data->>'middle_initial',
      (new.raw_user_meta_data->>'date_of_birth')::date,
      (new.raw_user_meta_data->>'age')::integer,
      new.raw_user_meta_data->>'contact_number',
      new.raw_user_meta_data->>'sex',
      new.email,
      new.raw_user_meta_data->>'complete_address',
      new.raw_user_meta_data->>'emergency_contact_complete_name',
      new.raw_user_meta_data->>'emergency_contact_contact_number',
      new.raw_user_meta_data->>'relation',
      new.raw_user_meta_data->>'username',
      'citizen',
      new.id
    );
  end if;

  return new;
end;
$$;

create extension if not exists pgcrypto with schema extensions;

create or replace function public.create_staff_account_admin(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthday date,
  p_gender text,
  p_username text,
  p_email text,
  p_role text,
  p_password text,
  p_consent_given boolean default true,
  p_status text default 'Active'
)
returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text;
  v_username text;
  v_employee_id text;
  v_employee_number bigint;
  v_role text;
  v_auth_user_id uuid;
begin
  if not public.is_admin() then
    return json_build_object('error', 'Forbidden: doctor role required');
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  v_username := trim(coalesce(p_username, ''));
  v_employee_id := null;
  v_role := lower(trim(coalesce(p_role, 'nurse')));

  if v_role not in ('doctor', 'nurse') then
    return json_build_object('error', 'Role must be doctor or nurse');
  end if;

  perform pg_advisory_xact_lock(hashtext('public.staff.employee_id')::bigint);

  select coalesce(max(coalesce((substring(employee_id from '[0-9]+'))::bigint, 0)), 1000) + 1
    into v_employee_number
  from public.staff
  where employee_id ~ '^UK-[0-9]+$';

  v_employee_id := 'UK-' || v_employee_number::text;

  if v_email = '' or v_username = '' then
    return json_build_object('error', 'Email and username are required');
  end if;

  if trim(coalesce(p_first_name, '')) = '' or trim(coalesce(p_last_name, '')) = '' then
    return json_build_object('error', 'First name and last name are required');
  end if;

  if length(coalesce(p_password, '')) < 8 then
    return json_build_object('error', 'Password must be at least 8 characters');
  end if;

  if exists (select 1 from public.staff where lower(email) = v_email) then
    return json_build_object('error', 'A staff account with this email already exists');
  end if;

  if exists (select 1 from public.staff where lower(username) = lower(v_username)) then
    return json_build_object('error', 'Username is already taken');
  end if;

  if exists (select 1 from public.staff where employee_id = v_employee_id) then
    return json_build_object('error', 'Employee ID is already in use');
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    return json_build_object('error', 'An auth account with this email already exists');
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    extensions.gen_random_uuid(),
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object('role', v_role, 'created_by', auth.uid()),
    now(),
    now(),
    ''
  )
  returning id into v_auth_user_id;

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    extensions.gen_random_uuid(),
    v_auth_user_id,
    jsonb_build_object('sub', v_auth_user_id::text, 'email', v_email),
    'email',
    v_auth_user_id::text,
    now(),
    now(),
    now()
  );

  insert into public.staff (
    first_name,
    middle_name,
    last_name,
    birthday,
    gender,
    username,
    employee_id,
    email,
    role,
    consent_given,
    status,
    auth_user_id
  )
  values (
    trim(coalesce(p_first_name, '')),
    nullif(trim(coalesce(p_middle_name, '')), ''),
    trim(coalesce(p_last_name, '')),
    p_birthday,
    nullif(trim(coalesce(p_gender, '')), ''),
    v_username,
    v_employee_id,
    v_email,
    v_role,
    coalesce(p_consent_given, true),
    coalesce(nullif(trim(coalesce(p_status, '')), ''), 'Active'),
    v_auth_user_id
  );

  return json_build_object(
    'message', 'Staff account created successfully',
    'auth_user_id', v_auth_user_id,
    'employee_id', v_employee_id
  );
exception
  when others then
    if v_auth_user_id is not null then
      delete from auth.identities where user_id = v_auth_user_id;
      delete from auth.users where id = v_auth_user_id;
    end if;
    return json_build_object('error', coalesce(sqlerrm, 'Unable to create staff account'));
end;
$$;

grant execute on function public.create_staff_account_admin(
  text,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  boolean,
  text
) to authenticated;

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
  order by case when lower(coalesce(s.role, '')) = 'doctor' then 0 else 1 end, s.id asc
  limit 1;

  if v_role <> 'doctor' then
    raise exception 'Forbidden: doctor role required';
  end if;

  perform public.purge_expired_doctor_schedules();

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
  order by case when lower(coalesce(s.role, '')) = 'doctor' then 0 else 1 end, s.id asc
  limit 1;

  if v_role <> 'doctor' then
    raise exception 'Forbidden: doctor role required';
  end if;

  delete from public.doctor_schedules where id = p_id;
  return true;
end;
$$;

grant execute on function public.upsert_doctor_schedule_admin(bigint, bigint, date, time, time, text) to authenticated;
grant execute on function public.delete_doctor_schedule_admin(bigint) to authenticated;

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
  v_current_role text;
  updated_row public.staff%rowtype;
begin
  v_current_role := lower(coalesce(public.get_staff_role(), ''));

  if v_current_role <> 'doctor' then
    return jsonb_build_object('ok', false, 'error', 'Doctor access required.');
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

do $$
begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'appointments') then
    execute 'drop policy if exists "staff_view_all_appointments" on public.appointments';
    execute 'drop policy if exists "staff_manage_appointments" on public.appointments';

    execute 'create policy "staff_view_all_appointments"
    on public.appointments for select
    using (
      exists (
        select 1 from public.staff
        where auth_user_id = auth.uid()
        and lower(trim(coalesce(role, ''''))) in (''doctor'', ''nurse'', ''specialist'')
      )
    )';

    execute 'create policy "staff_manage_appointments"
    on public.appointments for all
    using (
      exists (
        select 1 from public.staff
        where auth_user_id = auth.uid()
        and lower(trim(coalesce(role, ''''))) = ''doctor''
      )
    )
    with check (
      exists (
        select 1 from public.staff
        where auth_user_id = auth.uid()
        and lower(trim(coalesce(role, ''''))) = ''doctor''
      )
    )';
  end if;
end
$$;

commit;
