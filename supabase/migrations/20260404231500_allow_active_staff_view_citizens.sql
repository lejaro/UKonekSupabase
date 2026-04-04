-- Allow active staff (doctor/nurse/staff/admin) to view citizen accounts.
-- This is read-only access for dashboard user management lists.

drop policy if exists citizens_select_active_staff on public.citizens;
create policy citizens_select_active_staff
  on public.citizens
  for select
  using (
    exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
    )
  );

grant select on public.citizens to authenticated;
