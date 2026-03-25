-- Migration: Add helper function to link pending/staff accounts to auth users
-- This ensures that when users reset passwords, their accounts are properly linked
-- Active accounts remain active - no admin re-activation needed!

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
  -- Normalize email (case-insensitive)
  p_email := lower(coalesce(p_email, ''));

  if p_email = '' or p_auth_user_id is null then
    return json_build_object('error', 'Email and auth_user_id are required');
  end if;

  -- Check if user is already in staff table (already been approved)
  select status into v_staff_status
  from public.staff
  where lower(email) = p_email
  limit 1;

  if v_staff_status = 'Active' then
    -- Account is already active! Just link the auth_user_id
    update public.staff
    set auth_user_id = p_auth_user_id
    where lower(email) = p_email
      and auth_user_id is null;

    if found then
      return json_build_object(
        'message', 'Active staff account linked to auth user - ready to login!',
        'email', p_email,
        'status', 'Active',
        'auth_user_id', p_auth_user_id
      );
    else
      -- Already linked, no action needed
      return json_build_object(
        'message', 'Staff account already linked to auth user',
        'email', p_email,
        'status', 'Active'
      );
    end if;
  end if;

  -- If staff entry exists but not active, link it anyway (will still need admin approval)
  if v_staff_status is not null then
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
  end if;

  -- If not in staff table, try pending_staff
  update public.pending_staff
  set auth_user_id = p_auth_user_id
  where lower(email) = p_email
    and auth_user_id is null;

  if found then
    return json_build_object(
      'message', 'Linked pending_staff account to auth user',
      'email', p_email,
      'status', 'Pending',
      'auth_user_id', p_auth_user_id
    );
  end if;

  -- If neither pending_staff nor staff found
  return json_build_object(
    'message', 'Warning: No staff account found for this email',
    'email', p_email,
    'status', 'Not Found'
  );
end;
$$;

-- Ensure the function has proper grants for authenticated users
grant execute on function public.link_staff_to_auth(text, uuid) to authenticated;

-- Helper function to check if a user has a pending staff account
create or replace function public.check_pending_staff_status(p_email text)
returns json
language sql
security definer
as $$
  select json_build_object(
    'is_pending',
    exists(
      select 1
      from public.pending_staff
      where lower(email) = lower(coalesce(p_email, ''))
    ),
    'is_active_staff',
    exists(
      select 1
      from public.staff
      where lower(email) = lower(coalesce(p_email, ''))
        and lower(status) = 'active'
    ),
    'needs_admin_approval',
    exists(
      select 1
      from public.staff
      where lower(email) = lower(coalesce(p_email, ''))
        and lower(status) != 'active'
    )
  )
$$;

grant execute on function public.check_pending_staff_status(text) to authenticated;
