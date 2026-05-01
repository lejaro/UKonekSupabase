-- Remove family number and family-assignment features from the schema.
-- This migration drops family-related data structures and RPCs, then
-- restores citizen profile/auth flows without family fields.

-- Remove family-specific RPCs and helpers.
drop function if exists public.api_upsert_citizen_family_assignment(bigint, text, bigint, text, text);
drop function if exists public.api_get_family_by_id(bigint);
drop function if exists public.api_get_families(text, text);
drop function if exists public.ensure_family(text, text);
drop function if exists public.normalize_family_number(text);

-- Replace citizen listing RPC with a family-agnostic version.
drop function if exists public.api_get_citizens(text, text, text);
drop function if exists public.api_get_citizens(text);

create or replace function public.api_get_citizens(
  p_name text default null
)
returns table (
  id bigint,
  username text,
  firstname text,
  surname text,
  email text,
  contact_number text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    c.id,
    c.username,
    c.firstname,
    c.surname,
    c.email,
    c.contact_number,
    c.created_at
  from public.citizens c
  where
    (
      nullif(trim(coalesce(p_name, '')), '') is null
      or lower(concat_ws(' ', coalesce(c.firstname, ''), coalesce(c.surname, ''), coalesce(c.username, ''))) like '%' || lower(trim(p_name)) || '%'
    )
  order by c.created_at desc;
$$;

grant execute on function public.api_get_citizens(text) to authenticated;

-- Replace profile completion RPC with a family-agnostic signature.
drop function if exists public.complete_my_citizen_profile(
  text,
  text,
  text,
  date,
  integer,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text
);

drop function if exists public.complete_my_citizen_profile(
  text,
  text,
  text,
  date,
  integer,
  text,
  text,
  text,
  text,
  text,
  text,
  text
);

create or replace function public.complete_my_citizen_profile(
  p_firstname text,
  p_surname text,
  p_middle_initial text default null,
  p_date_of_birth date default null,
  p_age integer default null,
  p_contact_number text default null,
  p_sex text default null,
  p_complete_address text default null,
  p_emergency_contact_complete_name text default null,
  p_emergency_contact_contact_number text default null,
  p_relation text default null,
  p_username text default null
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
  select c.id
  into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid()
  limit 1;

  if v_citizen_id is null then
    return jsonb_build_object('ok', false, 'error', 'Citizen profile not found for verified account.');
  end if;

  v_username := nullif(trim(coalesce(p_username, '')), '');
  if v_username is null then
    return jsonb_build_object('ok', false, 'error', 'Username is required.');
  end if;

  if exists (
    select 1
    from public.citizens c
    where lower(trim(coalesce(c.username, ''))) = lower(v_username)
      and c.id <> v_citizen_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'Username already used, please choose another username.');
  end if;

  v_auth_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));

  update public.citizens c
  set
    firstname = case
      when nullif(trim(coalesce(p_firstname, '')), '') is not null then trim(p_firstname)
      else c.firstname
    end,
    surname = case
      when nullif(trim(coalesce(p_surname, '')), '') is not null then trim(p_surname)
      else c.surname
    end,
    middle_initial = nullif(trim(coalesce(p_middle_initial, '')), ''),
    date_of_birth = coalesce(p_date_of_birth, c.date_of_birth),
    age = coalesce(p_age, c.age),
    contact_number = nullif(trim(coalesce(p_contact_number, '')), ''),
    sex = nullif(trim(coalesce(p_sex, '')), ''),
    complete_address = nullif(trim(coalesce(p_complete_address, '')), ''),
    emergency_contact_complete_name = nullif(trim(coalesce(p_emergency_contact_complete_name, '')), ''),
    emergency_contact_contact_number = nullif(trim(coalesce(p_emergency_contact_contact_number, '')), ''),
    relation = nullif(trim(coalesce(p_relation, '')), ''),
    username = v_username,
    email = case
      when v_auth_email <> '' then v_auth_email
      else c.email
    end
  where c.id = v_citizen_id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.complete_my_citizen_profile(
  text,
  text,
  text,
  date,
  integer,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;

-- Replace auth trigger handler logic to avoid family metadata handling.
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
      'admin',
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
      firstname,
      surname,
      middle_initial,
      date_of_birth,
      age,
      contact_number,
      sex,
      email,
      complete_address,
      emergency_contact_complete_name,
      emergency_contact_contact_number,
      relation,
      username,
      role,
      auth_user_id
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
    )
    on conflict (email)
    do update set
      firstname = excluded.firstname,
      surname = excluded.surname,
      middle_initial = excluded.middle_initial,
      date_of_birth = excluded.date_of_birth,
      age = excluded.age,
      contact_number = excluded.contact_number,
      sex = excluded.sex,
      complete_address = excluded.complete_address,
      emergency_contact_complete_name = excluded.emergency_contact_complete_name,
      emergency_contact_contact_number = excluded.emergency_contact_contact_number,
      relation = excluded.relation,
      username = excluded.username,
      auth_user_id = excluded.auth_user_id;
  end if;

  return new;
end;
$$;

-- Drop citizens family constraints/indexes/columns.
alter table public.citizens
  drop constraint if exists citizens_family_assignment_consistent;

alter table public.citizens
  drop constraint if exists citizens_family_id_fkey;

drop index if exists public.idx_citizens_family_id;
drop index if exists public.idx_citizens_family_status;
drop index if exists public.idx_citizens_family_number;

alter table public.citizens
  drop constraint if exists citizens_family_number_citizen_only;

alter table public.citizens
  drop column if exists family_id,
  drop column if exists family_status,
  drop column if exists family_number;

-- Drop family status enum if no longer used.
do $$
begin
  if exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'family_status_enum'
  ) then
    drop type public.family_status_enum;
  end if;
end;
$$;

-- Drop families table and remaining policies.
drop policy if exists families_select_active_staff on public.families;
drop table if exists public.families;
