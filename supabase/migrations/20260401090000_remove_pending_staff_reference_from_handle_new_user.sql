-- Fix runtime error after pending_staff removal.
-- The auth trigger function must not reference public.pending_staff anymore.

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

  -- Keep hardcoded admin bootstrap behavior.
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

  -- Only citizen auto-provision remains.
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