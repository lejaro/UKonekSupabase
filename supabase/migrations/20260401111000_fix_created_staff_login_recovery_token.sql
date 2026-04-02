-- Fix login crash for admin-created accounts when recovery_token is NULL.

update auth.users
set recovery_token = ''
where recovery_token is null;

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
  v_role text;
  v_auth_user_id uuid;
begin
  if not public.is_admin() then
    return json_build_object('error', 'Forbidden: admin role required');
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  v_username := trim(coalesce(p_username, ''));
  v_employee_id := trim(coalesce(p_employee_id, ''));
  v_role := lower(trim(coalesce(p_role, 'staff')));

  if v_email = '' or v_username = '' or v_employee_id = '' then
    return json_build_object('error', 'Email, username, and employee ID are required');
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
  boolean,
  text
) to authenticated;
