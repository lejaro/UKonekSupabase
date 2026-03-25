-- =============================================================================
-- Migration: Replace Express.js backend with direct Supabase client access.
-- Adds proper RLS policies, PostgreSQL functions for admin ops, and a trigger
-- to auto-populate profile tables on user signup.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Drop legacy tables and columns no longer needed
-- ---------------------------------------------------------------------------

drop table if exists public.staff_email_verifications cascade;
drop table if exists public.citizen_otps cascade;

alter table public.staff
  drop column if exists password_hash,
  drop column if exists password_reset_token_hash,
  drop column if exists password_reset_token_expires,
  drop column if exists password_reset_otp_hash,
  drop column if exists password_reset_otp_expires,
  drop column if exists password_reset_otp_attempts_left;

alter table public.citizens
  drop column if exists password_hash,
  drop column if exists password_reset_token_hash,
  drop column if exists password_reset_token_expires;

alter table public.pending_staff
  drop column if exists password_hash;

-- ---------------------------------------------------------------------------
-- 2. Drop temporary allow-all policies
-- ---------------------------------------------------------------------------

drop policy if exists temp_allow_all_staff on public.staff;
drop policy if exists temp_allow_all_pending_staff on public.pending_staff;
drop policy if exists temp_allow_all_citizens on public.citizens;

-- ---------------------------------------------------------------------------
-- 3. Helper: check if the current auth user is a staff admin
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
    where auth_user_id = auth.uid()
      and lower(role) = 'admin'
      and lower(status) = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS Policies — staff table
-- ---------------------------------------------------------------------------

-- Admins can see all staff
create policy staff_select_admin
  on public.staff for select
  using ( public.is_admin() );

-- Non-admin staff can see their own row
create policy staff_select_own
  on public.staff for select
  using ( auth_user_id = auth.uid() );

-- Inserts/updates/deletes on staff are done through security-definer functions
-- so we allow insert only via service role (the functions run as definer).
-- Direct client inserts are blocked by default (no INSERT policy for anon/authenticated).

-- Admin can delete (also handled via RPC, but belt-and-suspenders)
create policy staff_delete_admin
  on public.staff for delete
  using ( public.is_admin() );

-- ---------------------------------------------------------------------------
-- 5. RLS Policies — pending_staff table
-- ---------------------------------------------------------------------------

-- Anyone (even unauthenticated via anon key) can insert a pending registration
create policy pending_staff_insert_anon
  on public.pending_staff for insert
  with check ( true );

-- Only admins can view pending registrations
create policy pending_staff_select_admin
  on public.pending_staff for select
  using ( public.is_admin() );

-- Only admins can delete (reject) pending registrations
create policy pending_staff_delete_admin
  on public.pending_staff for delete
  using ( public.is_admin() );

-- ---------------------------------------------------------------------------
-- 6. RLS Policies — citizens table
-- ---------------------------------------------------------------------------

-- Citizens can read their own row
create policy citizens_select_own
  on public.citizens for select
  using ( auth_user_id = auth.uid() );

-- Admins can see all citizens
create policy citizens_select_admin
  on public.citizens for select
  using ( public.is_admin() );

-- Inserts happen via the handle_new_user trigger (service role context),
-- so no explicit INSERT policy for the client is needed.

-- ---------------------------------------------------------------------------
-- 7. PostgreSQL function: get the current user's staff role
-- ---------------------------------------------------------------------------

create or replace function public.get_staff_role()
returns text
language plpgsql
stable
security definer
as $$
declare
  v_user_email text;
  v_role text;
begin
  -- Get the current auth user's email
  v_user_email := auth.jwt()->>'email';

  if v_user_email is null then
    return null;
  end if;

  -- Try to find staff role - first check by auth_user_id (most efficient)
  select role into v_role
  from public.staff
  where auth_user_id = auth.uid()
    and lower(status) = 'active'
  limit 1;

  if v_role is not null then
    return v_role;
  end if;

  -- If not found by auth_user_id, try to find by email and auto-link
  -- This handles cases where account was created but not linked
  select role into v_role
  from public.staff
  where lower(email) = lower(v_user_email)
    and lower(status) = 'active'
  limit 1;

  if v_role is not null then
    -- Auto-link the account for future logins (more efficient)
    update public.staff
    set auth_user_id = auth.uid()
    where lower(email) = lower(v_user_email)
      and auth_user_id is null;
    
    return v_role;
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. PostgreSQL function: get current user's staff profile
-- ---------------------------------------------------------------------------

create or replace function public.get_staff_profile()
returns json
language plpgsql
stable
security definer
as $$
declare
  v_user_email text;
  v_profile json;
begin
  -- Get the current auth user's email
  v_user_email := auth.jwt()->>'email';

  if v_user_email is null then
    return null;
  end if;

  -- Try to find profile by auth_user_id first (most efficient)
  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status
    from public.staff
    where auth_user_id = auth.uid()
      and lower(status) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    return v_profile;
  end if;

  -- If not found by auth_user_id, try to find by email and auto-link
  -- This handles cases where account was created but not linked
  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status
    from public.staff
    where lower(email) = lower(v_user_email)
      and lower(status) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    -- Auto-link the account for future logins (more efficient)
    update public.staff
    set auth_user_id = auth.uid()
    where lower(email) = lower(v_user_email)
      and auth_user_id is null;
    
    return v_profile;
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. PostgreSQL function: approve pending staff (admin only)
-- ---------------------------------------------------------------------------

create or replace function public.approve_pending_staff(pending_id bigint)
returns json
language plpgsql
security definer
as $$
declare
  v_pending record;
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

  insert into public.staff (
    first_name, middle_name, last_name, birthday, gender,
    username, employee_id, email, role, consent_given,
    status, auth_user_id
  ) values (
    v_pending.first_name, v_pending.middle_name, v_pending.last_name,
    v_pending.birthday, v_pending.gender, v_pending.username,
    v_pending.employee_id, v_pending.email, v_pending.role,
    v_pending.consent_given, 'Active', v_pending.auth_user_id
  );

  delete from public.pending_staff where id = pending_id;

  return json_build_object('message', 'Staff approved successfully');
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. PostgreSQL function: reject pending staff (admin only)
-- ---------------------------------------------------------------------------

create or replace function public.reject_pending_staff(pending_id bigint)
returns json
language plpgsql
security definer
as $$
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  delete from public.pending_staff where id = pending_id;

  return json_build_object('message', 'Pending staff rejected');
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. PostgreSQL function: delete staff member (admin only)
-- ---------------------------------------------------------------------------

create or replace function public.delete_staff_member(target_staff_id bigint)
returns json
language plpgsql
security definer
as $$
declare
  v_auth_user_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  select auth_user_id into v_auth_user_id
  from public.staff
  where id = target_staff_id;

  if not found then
    raise exception 'Staff not found';
  end if;

  delete from public.staff where id = target_staff_id;

  -- Note: deleting the auth.users row requires service_role.
  -- The client cannot do this directly. If you need to also delete
  -- the auth user, use a Supabase Edge Function or do it manually.

  return json_build_object('message', 'Staff deleted successfully');
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. PostgreSQL function: register staff directly (admin only)
--     Creates a staff row; auth user is created client-side by admin via
--     supabase.auth.admin (requires service_role key — use Edge Function
--     if needed). For now, this just inserts the staff profile row.
-- ---------------------------------------------------------------------------

create or replace function public.register_staff_direct(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthday date,
  p_gender text,
  p_username text,
  p_employee_id text,
  p_email text,
  p_role text,
  p_consent_given boolean,
  p_auth_user_id uuid default null
)
returns json
language plpgsql
security definer
as $$
begin
  if not public.is_admin() then
    raise exception 'Forbidden: admin role required';
  end if;

  insert into public.staff (
    first_name, middle_name, last_name, birthday, gender,
    username, employee_id, email, role, consent_given,
    status, auth_user_id
  ) values (
    p_first_name, p_middle_name, p_last_name, p_birthday, p_gender,
    p_username, p_employee_id, p_email, p_role, p_consent_given,
    'Active', p_auth_user_id
  );

  return json_build_object('message', 'Staff account created successfully');
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Trigger: auto-populate profile table on auth user creation
--     Uses raw_user_meta_data.role to decide which table to insert into.
-- ---------------------------------------------------------------------------

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

  -- Staff profiles are created via register_staff_direct or approve_pending_staff,
  -- not via this trigger. Only citizen signups go through auth.signUp() directly.

  return new;
end;
$$;

-- Create the trigger on auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
