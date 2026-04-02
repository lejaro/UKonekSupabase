-- Schema cleanup: remove pending approval artifacts now that admin creates staff directly.

-- Keep link_staff_to_auth available for password reset/account linking,
-- but limit it to staff table only.
create or replace function public.link_staff_to_auth(
  p_email text,
  p_auth_user_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_staff_status text;
begin
  p_email := lower(coalesce(p_email, ''));

  if p_email = '' or p_auth_user_id is null then
    return json_build_object('error', 'Email and auth_user_id are required');
  end if;

  select status into v_staff_status
  from public.staff
  where lower(email) = p_email
  limit 1;

  if v_staff_status is null then
    return json_build_object(
      'message', 'Warning: No staff account found for this email',
      'email', p_email,
      'status', 'Not Found'
    );
  end if;

  update public.staff
  set auth_user_id = p_auth_user_id
  where lower(email) = p_email
    and auth_user_id is null;

  if found then
    return json_build_object(
      'message', 'Staff account linked to auth user',
      'email', p_email,
      'status', v_staff_status,
      'auth_user_id', p_auth_user_id
    );
  end if;

  return json_build_object(
    'message', 'Staff account already linked to auth user',
    'email', p_email,
    'status', v_staff_status
  );
end;
$$;

grant execute on function public.link_staff_to_auth(text, uuid) to authenticated;

-- Remove obsolete pending-approval functions.
drop function if exists public.check_pending_staff_status(text);
drop function if exists public.approve_pending_staff(bigint);
drop function if exists public.reject_pending_staff(bigint);

-- Remove policy/grant artifacts before dropping the table.
do $$
begin
  if to_regclass('public.pending_staff') is not null then
    drop policy if exists temp_allow_all_pending_staff on public.pending_staff;
    drop policy if exists pending_staff_insert_anon on public.pending_staff;
    drop policy if exists pending_staff_insert_public on public.pending_staff;
    drop policy if exists pending_staff_select_admin on public.pending_staff;
    drop policy if exists pending_staff_delete_admin on public.pending_staff;

    revoke all on table public.pending_staff from anon;
    revoke all on table public.pending_staff from authenticated;
  end if;
end
$$;

-- Remove pending registrations table and dependent objects.
drop table if exists public.pending_staff cascade;
