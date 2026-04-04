-- Restrict hard delete of medicines to admins only.

drop policy if exists medicines_delete_admin_or_doctor on public.medicines;
drop policy if exists medicines_delete_admin_only on public.medicines;

create policy medicines_delete_admin_only
  on public.medicines
  for delete
  using (public.is_admin());
