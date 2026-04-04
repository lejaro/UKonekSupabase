-- Allow authorized inventory managers to remove medicine rows.

drop policy if exists medicines_delete_admin_or_doctor on public.medicines;
create policy medicines_delete_admin_or_doctor
  on public.medicines
  for delete
  using (
    public.is_admin()
    or exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) = any (array['doctor', 'specialist'])
    )
  );

grant delete on public.medicines to authenticated;
