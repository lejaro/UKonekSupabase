-- Fix staff login after password reset by auto-linking auth.users to public.staff via email.
-- This avoids false "not active" errors when status is already Active.

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
  v_user_email := auth.jwt()->>'email';

  if v_user_email is null then
    return null;
  end if;

  select role into v_role
  from public.staff
  where auth_user_id = auth.uid()
    and lower(coalesce(status, '')) = 'active'
  limit 1;

  if v_role is not null then
    return v_role;
  end if;

  select role into v_role
  from public.staff
  where lower(email) = lower(v_user_email)
    and lower(coalesce(status, '')) = 'active'
  limit 1;

  if v_role is not null then
    update public.staff
    set auth_user_id = auth.uid()
    where lower(email) = lower(v_user_email)
      and auth_user_id is null;

    return v_role;
  end if;

  return null;
end;
$$;

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
  v_user_email := auth.jwt()->>'email';

  if v_user_email is null then
    return null;
  end if;

  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status
    from public.staff
    where auth_user_id = auth.uid()
      and lower(coalesce(status, '')) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    return v_profile;
  end if;

  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status
    from public.staff
    where lower(email) = lower(v_user_email)
      and lower(coalesce(status, '')) = 'active'
    limit 1
  ) t;

  if v_profile is not null then
    update public.staff
    set auth_user_id = auth.uid()
    where lower(email) = lower(v_user_email)
      and auth_user_id is null;

    return v_profile;
  end if;

  return null;
end;
$$;
