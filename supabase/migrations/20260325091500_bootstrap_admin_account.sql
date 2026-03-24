-- Bootstrap a fixed admin account profile in public.staff.
-- This migration expects the Auth user to exist already in auth.users.

do $$
declare
  v_admin_email text := 'admin@ukonek.local';
  v_auth_user_id uuid;
begin
  select id
    into v_auth_user_id
  from auth.users
  where lower(email) = lower(v_admin_email)
  order by created_at asc
  limit 1;

  if v_auth_user_id is null then
    raise notice 'Bootstrap admin auth user not found for %. Create it in Auth Users, then re-run this migration.', v_admin_email;
    return;
  end if;

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
    'System',
    '-',
    'Admin',
    date '1990-01-01',
    'Prefer not to say',
    'admin',
    '000001',
    v_admin_email,
    'admin',
    true,
    'Active',
    v_auth_user_id
  )
  on conflict (email)
  do update set
    role = excluded.role,
    status = excluded.status,
    auth_user_id = excluded.auth_user_id,
    username = excluded.username,
    employee_id = excluded.employee_id;
end
$$;
