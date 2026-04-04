-- Complete citizen profile after OTP magic-link verification.

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
      when nullif(trim(coalesce(p_firstname, '')), '') is not null
        then trim(p_firstname)
      else c.firstname
    end,
    surname = case
      when nullif(trim(coalesce(p_surname, '')), '') is not null
        then trim(p_surname)
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
