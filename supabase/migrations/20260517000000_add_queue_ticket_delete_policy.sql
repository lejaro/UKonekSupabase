-- ─────────────────────────────────────────────────────────────────────────────
-- ADD DELETE POLICY FOR QUEUE TICKETS
-- ─────────────────────────────────────────────────────────────────────────────
-- Issue: Staff (doctor/nurse/admin) cannot delete queue tickets from the web
-- app because no DELETE RLS policy exists on public.queue_tickets.
-- The table only had SELECT, INSERT, UPDATE policies and grants.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add DELETE policy: only active staff (doctor, nurse, admin) can delete tickets
drop policy if exists queue_tickets_delete_policy on public.queue_tickets;
create policy queue_tickets_delete_policy
  on public.queue_tickets
  for delete
  using (
    public.is_admin()
    or exists (
      select 1
      from public.staff s
      where s.auth_user_id = auth.uid()
        and lower(trim(coalesce(s.status, ''))) = 'active'
        and lower(trim(coalesce(s.role, ''))) in ('doctor', 'nurse', 'admin')
    )
  );

-- 2. Grant DELETE permission to authenticated users (RLS will still restrict it)
grant delete on public.queue_tickets to authenticated;
