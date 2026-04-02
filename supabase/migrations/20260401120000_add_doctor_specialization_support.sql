-- Add doctor specialization support for admin-managed and self-managed updates.

alter table public.staff
add column if not exists doctor_specialization text;

-- Replace old signature so RPC calls are unambiguous with specialization support.
drop function if exists public.create_staff_account_admin(
  text,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  boolean,
  text
);

create or replace function public.create_staff_account_admin(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthday date,
  p_gender text,
  p_username text,
  p_employee_id text,
  p_email text,
  p_role text,
  p_doctor_specialization text default null,
  p_password text default '',
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
  v_role text;
  v_specialization text;
  v_auth_user_id uuid;
begin
  if not public.is_admin() then
    return json_build_object('error', 'Forbidden: admin role required');
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  v_username := trim(coalesce(p_username, ''));
  v_employee_id := trim(coalesce(p_employee_id, ''));
  v_role := lower(trim(coalesce(p_role, 'staff')));
  v_specialization := nullif(trim(coalesce(p_doctor_specialization, '')), '');

  if v_email = '' or v_username = '' or v_employee_id = '' then
    return json_build_object('error', 'Email, username, and employee ID are required');
  end if;

  if trim(coalesce(p_first_name, '')) = '' or trim(coalesce(p_last_name, '')) = '' then
    return json_build_object('error', 'First name and last name are required');
  end if;

  if length(coalesce(p_password, '')) < 8 then
    return json_build_object('error', 'Password must be at least 8 characters');
  end if;

  if v_role = 'doctor' and v_specialization is null then
    return json_build_object('error', 'Doctor specialization is required for doctor accounts');
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
    recovery_token,
    email_change,
    email_change_token_current,
    email_change_token_new,
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
    '',
    '',
    '',
    '',
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object('role', 'staff', 'created_by', auth.uid()),
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
    doctor_specialization,
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
    case when v_role = 'doctor' then v_specialization else null end,
    coalesce(p_consent_given, true),
    coalesce(nullif(trim(coalesce(p_status, '')), ''), 'Active'),
    v_auth_user_id
  );

  return json_build_object(
    'message', 'Staff account created successfully',
    'auth_user_id', v_auth_user_id
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
  text,
  text,
  boolean,
  text
) to authenticated;

create or replace function public.get_staff_profile()
returns json
language plpgsql
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
    select id, first_name, middle_name, last_name, username, role, email, status, doctor_specialization
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
    select id, first_name, middle_name, last_name, username, role, email, status, doctor_specialization
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

create or replace function public.set_my_doctor_specialization(p_specialization text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select lower(coalesce(role, '')) into v_role
  from public.staff
  where auth_user_id = auth.uid()
    and lower(coalesce(status, '')) = 'active'
  limit 1;

  if v_role is null then
    return json_build_object('error', 'Staff profile not found');
  end if;

  if v_role <> 'doctor' then
    return json_build_object('error', 'Only doctor accounts can set specialization');
  end if;

  update public.staff
  set doctor_specialization = nullif(trim(coalesce(p_specialization, '')), '')
  where auth_user_id = auth.uid()
    and lower(coalesce(status, '')) = 'active';

  return json_build_object('message', 'Specialization updated successfully');
end;
$$;

grant execute on function public.set_my_doctor_specialization(text) to authenticated;
