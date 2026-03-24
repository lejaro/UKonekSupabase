-- Ensure pending_staff signup works for public clients.
-- Recreate RLS policies and grants explicitly for anon/authenticated roles.

alter table public.pending_staff enable row level security;

-- Clean up existing policies in case remote state diverged.
drop policy if exists pending_staff_insert_anon on public.pending_staff;
drop policy if exists pending_staff_insert_public on public.pending_staff;
drop policy if exists pending_staff_select_admin on public.pending_staff;
drop policy if exists pending_staff_delete_admin on public.pending_staff;

-- Allow public signup submissions from web/mobile clients.
create policy pending_staff_insert_public
  on public.pending_staff
  for insert
  to anon, authenticated
  with check (true);

-- Admin-only visibility and delete operations.
create policy pending_staff_select_admin
  on public.pending_staff
  for select
  to authenticated
  using (public.is_admin());

create policy pending_staff_delete_admin
  on public.pending_staff
  for delete
  to authenticated
  using (public.is_admin());

-- Ensure roles can use table + identity sequence for inserts.
grant usage on schema public to anon, authenticated;
grant insert on table public.pending_staff to anon, authenticated;
grant select, delete on table public.pending_staff to authenticated;
grant usage, select on sequence public.pending_staff_id_seq to anon, authenticated;
