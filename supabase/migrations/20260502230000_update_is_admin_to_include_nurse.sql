-- Update is_admin() to include both doctor and nurse roles for management access.
-- This ensures that both roles can view citizens and staff accounts in the dashboard.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
as $$
  select exists (
    select 1
    from public.staff
    where auth_user_id = auth.uid()
      and lower(trim(coalesce(role, ''))) in ('doctor', 'nurse')
      and lower(coalesce(status, '')) = 'active'
  );
$$;
