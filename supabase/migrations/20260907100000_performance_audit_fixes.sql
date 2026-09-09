-- =============================================================================
-- Performance Audit Fixes
-- Date: 2026-09-07
--
-- This migration addresses the following database performance issues:
--   1. New consolidated RPC: get_clinical_operations_metrics()
--   2. RLS InitPlan optimization: wrap auth.uid() in (select auth.uid())
--   3. Deadlock prevention: deterministic lock ordering in dispense_prescription()
--   4. Update get_my_queue_dashboard to return has_vitals boolean
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. CONSOLIDATED CLINICAL OPERATIONS METRICS RPC
--    Replaces 6 concurrent HEAD count queries from web dashboard.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_clinical_operations_metrics()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'waiting',        (select count(*) from public.queue_tickets where status in ('waiting', 'on_call')),
    'serving',        (select count(*) from public.queue_tickets where status = 'serving'),
    'consults_today', (select count(*) from public.consultations where created_at >= current_date),
    'vitals_today',   (select count(*) from public.vital_signs where created_at >= current_date),
    'dispenses_today',(
      (select count(*) from public.prescription_item_dispenses where dispensed_at >= current_date) +
      (select count(*) from public.otc_dispenses where dispensed_at >= current_date)
    )
  );
$$;

grant execute on function public.get_clinical_operations_metrics() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. RLS InitPlan OPTIMIZATION
--    Wrap bare auth.uid() calls in (select auth.uid()) so PostgreSQL evaluates
--    the function call exactly once per query (InitPlan scalar caching) instead
--    of re-evaluating per candidate row during sequential scans.
--
--    Also applies to is_admin() helper function.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── is_admin() ──────────────────────────────────────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
as $$
  select exists (
    select 1
    from public.staff
    where auth_user_id = (select auth.uid())
      and role in ('doctor', 'nurse')
      and status = 'active'
  );
$$;

-- ── citizens ────────────────────────────────────────────────────────────────
drop policy if exists citizens_select_own on public.citizens;
create policy citizens_select_own
  on public.citizens for select
  using ( auth_user_id = (select auth.uid()) );

drop policy if exists citizens_select_active_staff on public.citizens;
create policy citizens_select_active_staff
  on public.citizens for select
  using (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
    )
  );

drop policy if exists citizens_update_own on public.citizens;
create policy citizens_update_own
  on public.citizens for update
  using ( auth_user_id = (select auth.uid()) )
  with check ( auth_user_id = (select auth.uid()) );

-- ── staff ───────────────────────────────────────────────────────────────────
drop policy if exists staff_select_own on public.staff;
create policy staff_select_own
  on public.staff for select
  using ( auth_user_id = (select auth.uid()) );

-- ── consultations ───────────────────────────────────────────────────────────
drop policy if exists consultations_select_active_staff on public.consultations;
create policy consultations_select_active_staff
  on public.consultations for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
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
        and s.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and s.role in ('doctor', 'nurse')
    )
  )
  with check (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
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
        and s.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and s.role = 'pharmacist'
    )
  )
  with check (
    exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
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
        and s.auth_user_id = (select auth.uid())
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
        and c.auth_user_id = (select auth.uid())
    )
    or public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
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
        and c.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists queue_tickets_update_policy on public.queue_tickets;
create policy queue_tickets_update_policy
  on public.queue_tickets for update
  using (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
    )
    or exists (
      select 1 from public.citizens c
      where c.id = queue_tickets.citizen_id
        and c.auth_user_id = (select auth.uid())
    )
  )
  with check (
    public.is_admin()
    or exists (
      select 1 from public.staff s
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
    )
    or (
      exists (
        select 1 from public.citizens c
        where c.id = queue_tickets.citizen_id
          and c.auth_user_id = (select auth.uid())
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
      where s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and s.role in ('doctor', 'nurse', 'admin')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. DEADLOCK PREVENTION IN dispense_prescription()
--    Re-create the function with items processed in deterministic order
--    (ORDER BY prescription_item_id ASC) to prevent deadlocks when concurrent
--    pharmacists lock medicines in different orders.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.dispense_prescription(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id bigint;
  v_role text;
  v_header_id bigint;
  v_header_status text;
  v_row record;
  v_item record;
  v_medicine_id bigint;
  v_medicine_qty integer;
  v_medicine_expiry date;
  v_new_status text;
  v_total_rows integer;
begin
  -- Resolve caller
  select s.id, s.role
  into v_staff_id, v_role
  from public.staff s
  where s.auth_user_id = (select auth.uid())
    and s.status = 'active'
  limit 1;

  if v_staff_id is null then
    return json_build_object('error', 'Not authenticated as active staff');
  end if;

  if v_role <> 'pharmacist' then
    return json_build_object('error', 'Forbidden: only pharmacists can dispense prescriptions');
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return json_build_object('error', 'No dispense items provided');
  end if;

  begin
    -- Lock target prescription
    select ph.id, ph.dispensing_status
    into v_header_id, v_header_status
    from public.prescription_headers ph
    where upper(trim(ph.prescription_code)) = upper(trim(coalesce(p_prescription_code, '')))
    limit 1
    for update;

    if v_header_id is null then
      raise exception 'Prescription not found';
    end if;

    if v_header_status = 'cancelled' then
      raise exception 'Prescription has been cancelled and cannot be dispensed';
    end if;

    if v_header_status = 'expired' then
      raise exception 'Prescription has expired and can no longer be dispensed';
    end if;

    if v_header_status = 'dispensed' then
      raise exception 'Prescription is already fully dispensed';
    end if;

    -- Disallow duplicate item IDs in request payload
    if exists (
      select 1
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
      group by r.prescription_item_id
      having count(*) > 1
    ) then
      raise exception 'Duplicate prescription_item_id in request payload';
    end if;

    -- *** DEADLOCK FIX: Process items in deterministic ascending order ***
    for v_row in
      select r.prescription_item_id, r.quantity
      from jsonb_to_recordset(p_items) as r(prescription_item_id bigint, quantity integer)
      order by r.prescription_item_id asc
    loop
      if v_row.prescription_item_id is null then
        raise exception 'prescription_item_id is required for every item';
      end if;

      if v_row.quantity is null or v_row.quantity < 0 then
        raise exception 'Dispense quantity cannot be negative for item %', v_row.prescription_item_id;
      end if;

      if v_row.quantity = 0 then
        continue;
      end if;

      select
        pi.id,
        pi.medicine_id,
        pi.medicine_name,
        pi.unit,
        pi.quantity,
        coalesce(pi.dispensed_quantity, 0) as dispensed_quantity,
        coalesce(pi.remaining_quantity, pi.quantity - coalesce(pi.dispensed_quantity, 0)) as remaining_quantity
      into v_item
      from public.prescription_items pi
      where pi.id = v_row.prescription_item_id
        and pi.prescription_id = v_header_id
      for update;

      if v_item.id is null then
        raise exception 'Prescription item % not found for this prescription', v_row.prescription_item_id;
      end if;

      if v_row.quantity > v_item.remaining_quantity then
        raise exception
          'Over-dispense blocked for % (remaining: %, requested: %)',
          v_item.medicine_name, v_item.remaining_quantity, v_row.quantity;
      end if;

      -- Smart match: match by medicine_id first, then fallback to name
      select m.id, m.qty, m.expiry_date
      into v_medicine_id, v_medicine_qty, v_medicine_expiry
      from public.medicines m
      where (
        (v_item.medicine_id is not null and m.id = v_item.medicine_id)
        or lower(trim(m.name)) = lower(trim(v_item.medicine_name))
      )
      and m.archived_at is null
      order by (case when v_item.medicine_id is not null and m.id = v_item.medicine_id then 0 else 1 end) asc, m.id asc
      limit 1
      for update;

      if v_medicine_id is null then
        raise exception 'Medicine not found in inventory: %', v_item.medicine_name;
      end if;

      -- Safety Guard: Block dispensing of expired batch
      if v_medicine_expiry is not null and v_medicine_expiry < current_date then
        raise exception 'Safety block: Inventory batch for % expired on % and cannot be dispensed.',
          v_item.medicine_name, to_char(v_medicine_expiry, 'YYYY-MM-DD');
      end if;

      if v_medicine_qty < v_row.quantity then
        raise exception
          'Insufficient stock for % (available: %, requested: %)',
          v_item.medicine_name, v_medicine_qty, v_row.quantity;
      end if;

      -- Deduct inventory stock
      update public.medicines
      set qty = qty - v_row.quantity
      where id = v_medicine_id;

      -- Update item dispensed & remaining counters
      update public.prescription_items
      set
        medicine_id = coalesce(v_item.medicine_id, v_medicine_id),
        dispensed_quantity = v_item.dispensed_quantity + v_row.quantity,
        remaining_quantity = v_item.remaining_quantity - v_row.quantity,
        is_dispensed = (v_item.remaining_quantity - v_row.quantity = 0)
      where id = v_item.id;

      -- Record dispense event with required prescription_id NOT NULL column
      insert into public.prescription_item_dispenses (
        prescription_id,
        prescription_item_id,
        medicine_id,
        dispensed_quantity,
        unit,
        note,
        dispensed_by_staff_id,
        dispensed_at
      ) values (
        v_header_id,
        v_item.id,
        v_medicine_id,
        v_row.quantity,
        coalesce(v_item.unit, ''),
        nullif(trim(p_note), ''),
        v_staff_id,
        now()
      );
    end loop;

    -- Recalculate prescription header status
    select
      count(*),
      count(*) filter (where remaining_quantity = 0),
      count(*) filter (where remaining_quantity > 0 and dispensed_quantity > 0)
    into v_total_rows, v_medicine_qty, v_medicine_id
    from public.prescription_items
    where prescription_id = v_header_id;

    if v_total_rows = 0 then
      v_new_status := 'pending';
    elsif v_medicine_qty = v_total_rows then
      v_new_status := 'dispensed';
    elsif v_medicine_qty > 0 or v_medicine_id > 0 then
      v_new_status := 'partial';
    else
      v_new_status := 'pending';
    end if;

    update public.prescription_headers
    set
      dispensing_status = v_new_status,
      dispensed_by_staff_id = v_staff_id,
      dispensed_at = case when v_new_status = 'dispensed' then now() else dispensed_at end
    where id = v_header_id;

    return json_build_object(
      'ok', true,
      'prescription_code', upper(trim(p_prescription_code)),
      'dispensing_status', v_new_status
    );
  exception
    when others then
      return json_build_object('error', sqlerrm);
  end;
end;
$$;

-- Provide dispense_prescription_items definition and grants as well
create or replace function public.dispense_prescription_items(
  p_prescription_code text,
  p_items jsonb,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.dispense_prescription(p_prescription_code, p_items, p_note);
end;
$$;

grant execute on function public.dispense_prescription(text, jsonb, text) to authenticated;
grant execute on function public.dispense_prescription_items(text, jsonb, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. UPDATE get_my_queue_dashboard TO RETURN has_vitals
--    Eliminates the secondary query the mobile app fires after every RPC call.
-- ═══════════════════════════════════════════════════════════════════════════════

drop function if exists public.get_my_queue_dashboard();

create or replace function public.get_my_queue_dashboard()
 returns table(
   queue_id bigint,
   service_key text,
   service_label text,
   ticket_code text,
   my_queue_number integer,
   currently_serving_queue_number integer,
   estimated_wait_minutes integer,
   status text,
   queue_date date,
   is_on_call boolean,
   waiting_count integer,
   citizen_fullname text,
   citizen_age integer,
   citizen_address text,
   citizen_contact text,
   chief_complaint text,
   has_vitals boolean
 )
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_citizen_id bigint;
  v_queue_id bigint;
  v_service_key text;
  v_service_label text;
  v_ticket_code text;
  v_my_queue integer;
  v_status text;
  v_serving_queue integer;
  v_waiting_ahead integer;
  v_on_call_ahead integer;
  v_waiting_total integer;
  v_queue_date date;
  v_reason text;
  v_symptoms text;
  v_fullname text;
  v_age integer;
  v_address text;
  v_contact text;
  v_has_vitals boolean;
begin
  -- Get active citizen info
  select
    c.id,
    concat_ws(' ', c.firstname, c.surname),
    c.age,
    c.complete_address,
    c.contact_number
  into
    v_citizen_id,
    v_fullname,
    v_age,
    v_address,
    v_contact
  from public.citizens c
  where c.auth_user_id = (select auth.uid())
  limit 1;

  if v_citizen_id is null then
    return;
  end if;

  -- Find the most recent active ticket for today
  select
    q.id,
    q.service_key,
    q.service_label,
    q.ticket_code,
    q.queue_number,
    trim(both from q.status),
    q.queue_date,
    q.reason,
    q.symptoms
  into
    v_queue_id,
    v_service_key,
    v_service_label,
    v_ticket_code,
    v_my_queue,
    v_status,
    v_queue_date,
    v_reason,
    v_symptoms
  from public.queue_tickets q
  where q.citizen_id = v_citizen_id
    and q.queue_date = public.get_manila_date()
    and lower(trim(both from coalesce(q.status, ''))) in ('waiting', 'on_call', 'serving')
  order by q.created_at desc
  limit 1;

  if v_queue_id is null then
    return;
  end if;

  -- Check if vitals exist for this queue ticket (eliminates mobile secondary query)
  v_has_vitals := exists(select 1 from public.vital_signs vs where vs.queue_ticket_id = v_queue_id);

  -- Currently serving is the lowest number in 'serving' or 'on_call' status
  select min(q.queue_number)
  into v_serving_queue
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) in ('serving', 'on_call');

  -- Count how many 'waiting' people are ahead
  select count(*)::integer
  into v_waiting_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) = 'waiting'
    and q.queue_number < v_my_queue;

  -- Count how many 'on_call' people are ahead
  select count(*)::integer
  into v_on_call_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) = 'on_call'
    and q.queue_number < v_my_queue;

  queue_id := v_queue_id;
  service_key := v_service_key;
  service_label := v_service_label;
  ticket_code := v_ticket_code;
  my_queue_number := v_my_queue;
  currently_serving_queue_number := v_serving_queue;

  -- Calculate estimated wait
  if lower(trim(both from coalesce(v_status, ''))) in ('serving', 'on_call') then
    estimated_wait_minutes := 0;
  else
    estimated_wait_minutes := (
      coalesce(v_waiting_ahead, 0)
      + coalesce(v_on_call_ahead, 0)
      + case when v_serving_queue is not null and v_serving_queue < v_my_queue then 1 else 0 end
    ) * 10;
  end if;

  status := v_status;
  queue_date := v_queue_date;
  is_on_call := lower(trim(both from coalesce(v_status, ''))) = 'on_call';

  waiting_count := coalesce(v_waiting_ahead, 0) + coalesce(v_on_call_ahead, 0);

  citizen_fullname := v_fullname;
  citizen_age := v_age;
  citizen_address := v_address;
  citizen_contact := v_contact;
  chief_complaint := concat_ws(': ', v_reason, nullif(v_symptoms, ''));
  has_vitals := v_has_vitals;

  return next;
end;
$function$;

grant execute on function public.get_my_queue_dashboard() to authenticated;
