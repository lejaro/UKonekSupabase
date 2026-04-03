-- Allow authenticated staff users to update their own profile details safely.
create or replace function public.update_my_staff_profile(
  p_display_name text,
  p_doctor_specialization text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_email text;
  v_role text;
  v_display_name text;
  v_profile json;
begin
  v_display_name := nullif(trim(coalesce(p_display_name, '')), '');
  if v_display_name is null then
    return json_build_object('error', 'Display name is required');
  end if;

  -- Ensure current auth user is linked to an active staff profile.
  select lower(email) into v_user_email
  from auth.users
  where id = auth.uid()
  limit 1;

  if v_user_email is null then
    return json_build_object('error', 'Authenticated user not found');
  end if;

  update public.staff
  set auth_user_id = auth.uid()
  where auth_user_id is null
    and lower(email) = v_user_email
    and lower(coalesce(status, '')) = 'active';

  select lower(coalesce(role, '')) into v_role
  from public.staff
  where auth_user_id = auth.uid()
    and lower(coalesce(status, '')) = 'active'
  limit 1;

  if v_role is null then
    return json_build_object('error', 'Active staff profile not found');
  end if;

  update public.staff
  set
    first_name = v_display_name,
    doctor_specialization = case
      when v_role = 'doctor' then nullif(trim(coalesce(p_doctor_specialization, '')), '')
      else doctor_specialization
    end
  where auth_user_id = auth.uid()
    and lower(coalesce(status, '')) = 'active';

  select row_to_json(t) into v_profile
  from (
    select id, first_name, middle_name, last_name, username, role, email, status, doctor_specialization
    from public.staff
    where auth_user_id = auth.uid()
      and lower(coalesce(status, '')) = 'active'
    limit 1
  ) t;

  return json_build_object(
    'message', 'Profile updated successfully',
    'profile', v_profile
  );
end;
$$;

grant execute on function public.update_my_staff_profile(text, text) to authenticated;
