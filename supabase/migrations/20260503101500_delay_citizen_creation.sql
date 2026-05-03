-- Update handle_new_user to only handle non-citizen roles (if any)
-- Citizens will now be created only when they complete their credentials via complete_my_citizen_profile
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

  -- We no longer auto-insert citizens here.
  -- This allows us to ensure they have a username/password before the profile exists in public.citizens.
  
  -- If we had other roles that needed auto-creation, they would go here.
  -- For now, staff are handled manually/via other RPCs.

  return new;
end;
$$;

-- Update complete_my_citizen_profile to handle the initial creation of the citizen record
create or replace function public.complete_my_citizen_profile(
  p_firstname text,
  p_surname text,
  p_middle_initial text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_age integer DEFAULT NULL,
  p_contact_number text DEFAULT NULL,
  p_sex text DEFAULT NULL,
  p_complete_address text DEFAULT NULL,
  p_emergency_contact_complete_name text DEFAULT NULL,
  p_emergency_contact_contact_number text DEFAULT NULL,
  p_relation text DEFAULT NULL,
  p_username text DEFAULT NULL
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_username text;
  v_auth_email text;
begin
  -- 1. Validate username
  v_username := nullif(trim(coalesce(p_username, '')), '');
  if v_username is null then
    return jsonb_build_object('ok', false, 'error', 'Username is required.');
  end if;

  -- 2. Check if username is taken by ANOTHER user
  if exists (
    select 1
    from public.citizens c
    where lower(trim(coalesce(c.username, ''))) = lower(v_username)
      and c.auth_user_id <> auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'error', 'Username already used, please choose another username.');
  end if;

  v_auth_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  if v_auth_email = '' then
     -- Fallback to auth.users if not in JWT (unlikely for authenticated calls)
     select email into v_auth_email from auth.users where id = auth.uid();
  end if;

  -- 3. Check if citizen record already exists
  select c.id into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid()
  limit 1;

  if v_citizen_id is null then
    -- CREATE the record
    insert into public.citizens (
      firstname, surname, middle_initial, date_of_birth, age,
      contact_number, sex, email, complete_address,
      emergency_contact_complete_name, emergency_contact_contact_number,
      relation, username, role, auth_user_id
    ) values (
      trim(p_firstname),
      trim(p_surname),
      nullif(trim(p_middle_initial), ''),
      p_date_of_birth,
      p_age,
      nullif(trim(p_contact_number), ''),
      nullif(trim(p_sex), ''),
      v_auth_email,
      nullif(trim(p_complete_address), ''),
      nullif(trim(p_emergency_contact_complete_name), ''),
      nullif(trim(p_emergency_contact_contact_number), ''),
      nullif(trim(p_relation), ''),
      v_username,
      'citizen',
      auth.uid()
    );
  else
    -- UPDATE the existing record
    update public.citizens
    set
      firstname = case when nullif(trim(p_firstname), '') is not null then trim(p_firstname) else firstname end,
      surname = case when nullif(trim(p_surname), '') is not null then trim(p_surname) else surname end,
      middle_initial = nullif(trim(p_middle_initial), ''),
      date_of_birth = coalesce(p_date_of_birth, date_of_birth),
      age = coalesce(p_age, age),
      contact_number = nullif(trim(p_contact_number), ''),
      sex = nullif(trim(p_sex), ''),
      complete_address = nullif(trim(p_complete_address), ''),
      emergency_contact_complete_name = nullif(trim(p_emergency_contact_complete_name), ''),
      emergency_contact_contact_number = nullif(trim(p_emergency_contact_contact_number), ''),
      relation = nullif(trim(p_relation), ''),
      username = v_username,
      email = v_auth_email
    where id = v_citizen_id;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;
