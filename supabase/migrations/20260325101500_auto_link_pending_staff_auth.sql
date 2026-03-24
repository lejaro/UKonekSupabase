-- Remove manual auth UID copy for pending staff by:
-- 1) Auto-linking pending_staff.auth_user_id when an auth user is created.
-- 2) Resolving auth_user_id by pending email during approval if still null.

create or replace function public.approve_pending_staff(pending_id bigint)
returns json
language plpgsql
security definer
as $$
declare
  v_pending record;
  v_resolved_auth_user_id uuid;
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

  v_resolved_auth_user_id := coalesce(
    v_pending.auth_user_id,
    (
      select u.id
      from auth.users u
      where lower(u.email) = lower(v_pending.email)
      order by u.created_at desc
      limit 1
    )
  );

  insert into public.staff (
    first_name, middle_name, last_name, birthday, gender,
    username, employee_id, email, role, consent_given,
    status, auth_user_id
  ) values (
    v_pending.first_name, v_pending.middle_name, v_pending.last_name,
    v_pending.birthday, v_pending.gender, v_pending.username,
    v_pending.employee_id, v_pending.email, v_pending.role,
    v_pending.consent_given, 'Active', v_resolved_auth_user_id
  );

  delete from public.pending_staff where id = pending_id;

  return json_build_object('message', 'Staff approved successfully');
end;
$$;

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

  -- Hardcoded admin bootstrap account.
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

  -- Auto-link staff approvals waiting in pending_staff by matching auth email.
  update public.pending_staff
  set auth_user_id = new.id
  where lower(email) = lower(coalesce(new.email, ''))
    and auth_user_id is null;

  if found then
    return new;
  end if;

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
