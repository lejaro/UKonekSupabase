-- Admin-only RPC to reset a staff account password in auth.users.

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
