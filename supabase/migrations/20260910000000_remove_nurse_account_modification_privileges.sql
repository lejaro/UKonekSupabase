-- Migration: Remove nurse's ability to modify user accounts
-- 1. Redefine public.is_admin() to strictly include only 'admin' role (removing 'nurse' and non-admin roles).
-- 2. Add staff_select_active_staff RLS policy so all active medical staff (including nurses) can read the staff directory.
-- 3. Add staff_update_admin RLS policy restricting staff updates strictly to admins (denying nurses).
-- 4. Re-enforce staff_delete_admin RLS policy strictly to admins (denying nurses).
-- 5. Add update_staff_account_admin RPC for safe administrative staff account updates.
-- 6. Ensure delete_staff_member and reset_staff_password_admin strictly enforce public.is_admin().

-- ---------------------------------------------------------------------------
-- 1. Redefine public.is_admin() strictly for 'admin' role
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
    and lower(trim(coalesce(role, ''))) = 'admin'
    and lower(trim(coalesce(status, ''))) = 'active'
  );
$$;

grant execute on function public.is_admin() to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2. RLS Policies on public.staff: Active staff read directory, only admin modifies
-- ---------------------------------------------------------------------------
-- Allow all active staff (including nurses, doctors, pharmacists, admins) to view the staff roster & directory
drop policy if exists staff_select_active_staff on public.staff;
create policy staff_select_active_staff
  on public.staff for select
  using (
    exists (
      select 1 from public.staff s
      where (
        s.auth_user_id = auth.uid()
        or (
          auth.jwt()->>'email' is not null
          and lower(trim(s.email)) = lower(trim(auth.jwt()->>'email'))
        )
      )
      and lower(trim(coalesce(s.status, ''))) = 'active'
    )
  );

-- Admins can update staff records; nurses and non-admins are blocked
drop policy if exists staff_update_admin on public.staff;
create policy staff_update_admin
  on public.staff for update
  using ( public.is_admin() )
  with check ( public.is_admin() );

-- Admins can delete staff records; nurses and non-admins are blocked
drop policy if exists staff_delete_admin on public.staff;
create policy staff_delete_admin
  on public.staff for delete
  using ( public.is_admin() );

-- ---------------------------------------------------------------------------
-- 3. Administrative RPC to update staff accounts
-- ---------------------------------------------------------------------------
create or replace function public.update_staff_account_admin(
  target_staff_id bigint,
  p_first_name text default null,
  p_last_name text default null,
  p_middle_name text default null,
  p_username text default null,
  p_email text default null,
  p_employee_id text default null,
  p_role text default null,
  p_birthday date default null
)
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_updated_staff public.staff%rowtype;
  v_auth_user_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  select auth_user_id into v_auth_user_id
  from public.staff
  where id = target_staff_id;

  if not found then
    raise exception 'Staff account not found';
  end if;

  update public.staff
  set
    first_name = coalesce(nullif(trim(p_first_name), ''), first_name),
    last_name = coalesce(nullif(trim(p_last_name), ''), last_name),
    middle_name = nullif(trim(p_middle_name), ''),
    username = coalesce(nullif(trim(p_username), ''), username),
    email = coalesce(nullif(trim(lower(p_email)), ''), email),
    employee_id = coalesce(nullif(trim(p_employee_id), ''), employee_id),
    role = coalesce(nullif(trim(lower(p_role)), ''), role),
    birthday = coalesce(p_birthday, birthday)
  where id = target_staff_id
  returning * into v_updated_staff;

  -- Synchronize auth.users email if linked
  if v_auth_user_id is not null and p_email is not null and trim(p_email) <> '' then
    update auth.users
    set email = lower(trim(p_email))
    where id = v_auth_user_id;
  end if;

  return json_build_object(
    'success', true,
    'message', 'Staff account updated successfully',
    'staff', row_to_json(v_updated_staff)
  );
end;
$$;

grant execute on function public.update_staff_account_admin(bigint, text, text, text, text, text, text, text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Ensure delete_staff_member strictly enforces admin check
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
-- 5. Ensure reset_staff_password_admin strictly enforces admin check
-- ---------------------------------------------------------------------------
create or replace function public.reset_staff_password_admin(
  target_staff_id bigint,
  p_new_password text
)
returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_auth_user_id uuid;
  v_staff_email text;
begin
  if not public.is_admin() then
    return json_build_object('error', 'Forbidden: admin role required');
  end if;

  if length(coalesce(p_new_password, '')) < 8 then
    return json_build_object('error', 'Password must be at least 8 characters');
  end if;

  select auth_user_id, lower(trim(coalesce(email, '')))
    into v_auth_user_id, v_staff_email
  from public.staff
  where id = target_staff_id;

  if not found then
    return json_build_object('error', 'Staff not found');
  end if;

  if v_auth_user_id is null and v_staff_email <> '' then
    select id into v_auth_user_id
    from auth.users
    where lower(email) = v_staff_email
    limit 1;

    if v_auth_user_id is not null then
      update public.staff
      set auth_user_id = v_auth_user_id
      where id = target_staff_id;
    end if;
  end if;

  if v_auth_user_id is null then
    return json_build_object('error', 'No linked auth account found for this staff user');
  end if;

  if v_auth_user_id = auth.uid() then
    return json_build_object('error', 'Use profile settings to change your own password');
  end if;

  update auth.users
  set
    encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
    recovery_token = '',
    email_change = '',
    email_change_token_current = '',
    email_change_token_new = '',
    updated_at = now()
  where id = v_auth_user_id;

  if not found then
    return json_build_object('error', 'Linked auth account was not found');
  end if;

  return json_build_object('message', 'Password reset successful');
end;
$$;

grant execute on function public.reset_staff_password_admin(bigint, text) to authenticated;
