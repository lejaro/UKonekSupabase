-- Ensure staff deletion also removes the linked authentication account.

create or replace function public.delete_staff_member(target_staff_id bigint)
returns json
language plpgsql
security definer
set search_path = public, auth
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

  if v_auth_user_id = auth.uid() then
    raise exception 'You cannot delete your own account';
  end if;

  delete from public.staff
  where id = target_staff_id;

  if v_auth_user_id is not null then
    delete from auth.identities where user_id = v_auth_user_id;
    delete from auth.users where id = v_auth_user_id;
  end if;

  return json_build_object('message', 'Staff account deleted successfully');
end;
$$;

grant execute on function public.delete_staff_member(bigint) to authenticated;
