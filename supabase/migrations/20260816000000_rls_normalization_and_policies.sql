-- =============================================================================
-- P0-1: RLS Normalization — Eliminate sequential scans on `staff` table.
--
-- Root cause (live-verified 2026-08-16):
--   staff.status stored as 'Active' (capitalized) while policies compare to
--   lowercase 'active', forcing `lower(trim(coalesce(status, '')))` wrappers
--   that defeat index usage → 461,908 sequential scans / 2.36M rows read.
--
-- Fix:
--   1. Add BEFORE INSERT/UPDATE trigger on staff + queue_tickets that stores
--      lowercase/trimmed status/role/availability_status so policies can use
--      plain equality (index-friendly).
--   2. Normalize existing data.
--   3. Rewrite is_admin() + all RLS policies to use plain column equality.
--   4. Simplify get_today_ticket_count() (removes lower/trim wrapper that
--      blocked idx_queue_tickets_date_status).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Normalization trigger function (staff)
-- ---------------------------------------------------------------------------
create or replace function public.normalize_staff_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  new.role := lower(btrim(coalesce(new.role::text, '')));
  new.status := lower(btrim(coalesce(new.status::text, '')));
  -- Preserve semantics: old policies used coalesce(availability_status,'available').
  -- NULL → 'available'; '' stays '' (neither maps to 'available' nor 'on_break').
  new.availability_status := lower(btrim(coalesce(new.availability_status, 'available')));
  return new;
end;
$function$;

drop trigger if exists trg_normalize_staff_columns on public.staff;
create trigger trg_normalize_staff_columns
  before insert or update on public.staff
  for each row execute function public.normalize_staff_columns();

-- ---------------------------------------------------------------------------
-- 2. Normalize existing staff data + supporting composite index
--    (supports the rewritten EXISTS(... status = 'active') subqueries)
-- ---------------------------------------------------------------------------
update public.staff
set status = lower(btrim(status::text)),
    role = lower(btrim(role::text)),
    availability_status = lower(btrim(coalesce(availability_status, 'available')));

create index if not exists idx_staff_auth_id_status
  on public.staff (auth_user_id, status);

-- ---------------------------------------------------------------------------
-- 3. Normalization trigger function (queue_tickets) — defense-in-depth
--    (CHECK constraint already enforces lowercase, this guards direct SQL)
-- ---------------------------------------------------------------------------
create or replace function public.normalize_queue_ticket_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  new.status := lower(btrim(coalesce(new.status::text, '')));
  return new;
end;
$function$;

drop trigger if exists trg_normalize_queue_ticket_columns on public.queue_tickets;
create trigger trg_normalize_queue_ticket_columns
  before insert or update on public.queue_tickets
  for each row execute function public.normalize_queue_ticket_columns();

-- ---------------------------------------------------------------------------
-- 4. Rewrite is_admin() using normalized columns
--    (semantics preserved: role IN ('doctor','nurse') AND status = 'active')
-- ---------------------------------------------------------------------------
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
      and role in ('doctor', 'nurse')
      and status = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- 5. Rewrite all RLS policies to use plain equality (no lower/trim wrappers)
--    ACCESS CONTROL SEMANTICS PRESERVED EXACTLY.
-- ---------------------------------------------------------------------------

-- ── citizens ────────────────────────────────────────────────────────────────
drop policy if exists citizens_select_own on public.citizens;
create policy citizens_select_own
  on public.citizens for select
  using ( auth_user_id = auth.uid() );

drop policy if exists citizens_select_admin on public.citizens;
create policy citizens_select_admin
  on public.citizens for select
  using ( public.is_admin() );

drop policy if exists citizens_select_active_staff on public.citizens;
create policy citizens_select_active_staff
  on public.citizens for select
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists citizens_update_own on public.citizens;
create policy citizens_update_own
  on public.citizens for update
  using ( auth_user_id = auth.uid() )
  with check ( auth_user_id = auth.uid() );

-- ── staff ───────────────────────────────────────────────────────────────────
drop policy if exists staff_select_own on public.staff;
create policy staff_select_own
  on public.staff for select
  using ( auth_user_id = auth.uid() );

drop policy if exists staff_select_admin on public.staff;
create policy staff_select_admin
  on public.staff for select
  using ( public.is_admin() );

drop policy if exists staff_delete_admin on public.staff;
create policy staff_delete_admin
  on public.staff for delete
  using ( public.is_admin() );

-- ── consultations ───────────────────────────────────────────────────────────
drop policy if exists consultations_select_active_staff on public.consultations;
create policy consultations_select_active_staff
  on public.consultations for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists consultations_insert_doctor_only on public.consultations;
create policy consultations_insert_doctor_only
  on public.consultations for insert
  with check (
    exists (
      select 1 from public.staff s
      where s.id = consultations.doctor_staff_id
        and s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'doctor'
    )
  );

drop policy if exists consultations_update_nurse_vitals on public.consultations;
create policy consultations_update_nurse_vitals
  on public.consultations for update
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role in ('doctor', 'nurse')
    )
  )
  with check (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role in ('doctor', 'nurse')
    )
  );

-- ── prescription_headers ────────────────────────────────────────────────────
drop policy if exists prescription_headers_select_active_staff on public.prescription_headers;
create policy prescription_headers_select_active_staff
  on public.prescription_headers for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists prescription_headers_insert_doctor_only on public.prescription_headers;
create policy prescription_headers_insert_doctor_only
  on public.prescription_headers for insert
  with check (
    exists (
      select 1 from public.staff s
      where s.id = prescription_headers.doctor_staff_id
        and s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'doctor'
    )
  );

drop policy if exists prescription_headers_select_pharmacist on public.prescription_headers;
create policy prescription_headers_select_pharmacist
  on public.prescription_headers for select
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'pharmacist'
    )
  );

drop policy if exists prescription_headers_update_pharmacist on public.prescription_headers;
create policy prescription_headers_update_pharmacist
  on public.prescription_headers for update
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'pharmacist'
    )
  )
  with check (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'pharmacist'
    )
  );

-- ── prescription_items ──────────────────────────────────────────────────────
drop policy if exists prescription_items_select_active_staff on public.prescription_items;
create policy prescription_items_select_active_staff
  on public.prescription_items for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists prescription_items_insert_doctor_only on public.prescription_items;
create policy prescription_items_insert_doctor_only
  on public.prescription_items for insert
  with check (
    exists (
      select 1 from public.prescription_headers ph
      join public.staff s on s.id = ph.doctor_staff_id
      where ph.id = prescription_items.prescription_id
        and s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role = 'doctor'
    )
  );

-- ── queue_tickets ───────────────────────────────────────────────────────────
drop policy if exists queue_tickets_select_policy on public.queue_tickets;
create policy queue_tickets_select_policy
  on public.queue_tickets for select
  using (
    exists (
      select 1 from public.citizens c
      where c.id = queue_tickets.citizen_id
        and c.auth_user_id = auth.uid()
    )
    or public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
  );

drop policy if exists queue_tickets_insert_citizen on public.queue_tickets;
create policy queue_tickets_insert_citizen
  on public.queue_tickets for insert
  with check (
    exists (
      select 1 from public.citizens c
      where c.id = queue_tickets.citizen_id
        and c.auth_user_id = auth.uid()
    )
  );

drop policy if exists queue_tickets_update_policy on public.queue_tickets;
create policy queue_tickets_update_policy
  on public.queue_tickets for update
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
    or exists (
      select 1 from public.citizens c
      where c.id = queue_tickets.citizen_id
        and c.auth_user_id = auth.uid()
    )
  )
  with check (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
    )
    or (
      exists (
        select 1 from public.citizens c
        where c.id = queue_tickets.citizen_id
          and c.auth_user_id = auth.uid()
      )
      and queue_tickets.status in ('waiting', 'cancelled')
    )
  );

drop policy if exists queue_tickets_delete_policy on public.queue_tickets;
create policy queue_tickets_delete_policy
  on public.queue_tickets for delete
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = auth.uid()
        and s.status = 'active'
        and s.role in ('doctor', 'nurse', 'admin')
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Simplify get_today_ticket_count() — remove lower/trim wrapper that
--    blocks idx_queue_tickets_date_status. Semantics preserved (FROM clause
--    and status list already verified live as the corrected version).
-- ---------------------------------------------------------------------------
create or replace function public.get_today_ticket_count()
returns integer
language sql
security definer
set search_path to 'public'
as $function$
  select count(*)::integer
  from public.queue_tickets
  where queue_date = public.get_manila_date()
    and status in ('serving', 'completed', 'on_call');
$function$;