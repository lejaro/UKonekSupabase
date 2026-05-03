-- Drop the old version of the function with 13 parameters
DROP FUNCTION IF EXISTS public.complete_my_citizen_profile(
  text, text, text, date, integer, text, text, text, text, text, text, text, text
);

-- Re-create the 12-parameter version to be sure
CREATE OR REPLACE FUNCTION public.complete_my_citizen_profile(
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  text, text, text, date, integer, text, text, text, text, text, text, text
) to authenticated;
