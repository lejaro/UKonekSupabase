# UKonek Database & Schema Audit Findings

> **Audit Basis:** Comparison of the live PostgreSQL schema (`dqjxpwbsbzagbjtulhue`, `UKonek_Plus`), local `supabase/migrations/` (`183` files), `supabase/functions/`, `web/src/`, and `mobile/lib/`. No code, migrations, or live data were modified.

---

## Executive Summary — Top 5 Critical Findings

1. **Broken Citizen Medication Schedule & Dispense History RPCs + Type/Schema Bugs in Live Functions:** Both `get_my_medicine_schedule(p_citizen_id)` and `get_my_prescription_dispense_logs(...)` query non-existent column `m.dosage` from `public.medicines` (which only has `dosage_form` and `dosage_strength`), failing at runtime for citizens; additionally `return_dispensed_prescription_item()` sets `dispensing_status = 'partially_dispensed'` (violating `chk_dispensing_status`), `merge_walkin_to_citizen()` sets `queue_tickets.citizen_type = 'citizen'` (violating `queue_tickets_citizen_type_valid`), and 3 legacy RPCs reference dropped/non-existent tables (`pending_staff`, `medicine_inventory_transactions`, `medicine_return_logs`).
2. **Permissive & Privilege-Escalating RLS Policies (`vital_signs`, `system_config`, `audit_log`, `staff`, `feedbacks`):** While all `24` tables have RLS enabled, stale/over-broad policies leave critical gaps: any authenticated user (including citizens) can `UPDATE` any row in `vital_signs` (`"Allow staff to update vital signs"`) and read/overwrite `system_config` (`"Anyone can read system config"`, `"Authenticated users can update system config"`); even `anon` can `INSERT` into `audit_log` (`audit_log_insert_authenticated` with `WITH CHECK (true)`); `staff` policies trust JWT `user_metadata` (`raw_user_meta_data`); and `feedbacks_delete_doctor_or_admin` lets pharmacists delete feedback via `is_active_staff()`.
3. **Client Code vs. Live Schema & RLS Mismatches (`web`):** `web/src/js/services/pharmacyService.js` queries non-existent tables `prescriptions` and `prescription_dispense_logs` (plus non-existent `pharmacist_staff_id`); `reportsHubController.js` joins `citizens` using `first_name, last_name` instead of `firstname, surname`; `usersController.js` filters `lab_orders` by non-existent `patient_identifier`; `reports.js` reads non-existent `consult.treatment_plan`; and `triageController.js` inserts/updates `citizens` and `queue_tickets` directly despite missing staff RLS policies and passes a plain string (`vitals-allergies`) into `citizens.allergies` (`text[]`).
4. **14 Unindexed Foreign Keys (of 42) & 14 Implied Non-FK Relationships:** Exactly **14 of 42** foreign keys lack supporting indexes (including `feedbacks.citizen_id`, `lab_orders.doctor_staff_id`, `vital_signs.nurse_id`, `prescription_headers.dispensed_by_staff_id`, `prescription_item_dispenses.medicine_id`, and `medicine_intake_logs.prescription_item_id` leading column). Critical identity/clinical links (`staff.auth_user_id`, `citizens.auth_user_id`, polymorphic `patient_identifier` on `consultations`/`prescription_headers`, and `prescription_items.medicine_name`) lack foreign key constraints.
5. **Migration Drift, Unmigrated Live Tables & 5 Overloaded RPC Signatures:** Local `supabase/migrations/` and remote `supabase_migrations` each list `183` entries, yet **20 migration names/entries differ**, and **4 live tables** (`audit_log`, `clinic_transactions`, `consultation_attachments`, `medicine_restock_logs`) have **no `CREATE TABLE` migration locally**. Five live RPC names are overloaded in PostgreSQL (`dispense_otc_medicines`, `dispense_prescription`, `get_my_dispense_history`, `purge_completed_queue_tickets`, `update_staff_account_admin`), creating PostgREST `PGRST203` ambiguity risks, while **all 114 functions** in `public` grant `EXECUTE` to `anon` and `authenticated`.

---

## Detailed Findings by Category

### 1. Code References Missing From Live Schema (and Vice Versa)

#### A. Application Code Queries Targeting Non-Existent Tables or Columns
| Location | Code Reference | Live Schema Reality | Impact |
|---|---|---|---|
| `web/src/js/services/pharmacyService.js:134-149` | `.from('prescriptions')` with `items:prescription_items(...)`, `doctor`, `patient` | Live table is `prescription_headers` (`listPrescriptions` is defined/exported but appears unused by active UI) | Fails with table-not-found if invoked |
| `web/src/js/services/pharmacyService.js:183-199, 229` | `.from('prescription_dispense_logs')` selecting `pharmacist_staff_id` | Live table is `prescription_item_dispenses` with column `dispensed_by_staff_id` | Fails if `listDispenseLogs` / old path invoked |
| `web/src/js/controllers/reportsHubController.js:159, 212` | `.from('feedbacks').select('..., citizen:citizens(id, first_name, last_name, email)')` | `citizens` uses `firstname` and `surname` (not `first_name` / `last_name`) | Embedded PostgREST join errors, forcing fallback to flat query without citizen names |
| `web/src/js/controllers/usersController.js:662-664` | `.from('lab_orders')...or('patient_citizen_id.eq...,patient_identifier.eq...')` | `lab_orders` has `patient_citizen_id`, **no `patient_identifier` column** | Fails Citizen Health Record Lab Orders tab load for non-NULL filters |
| `web/src/js/reports.js:380` | `consult.treatment_plan` | `consultations` has no `treatment_plan` column | Always exports `'—'` |
| `web/src/js/controllers/triageController.js:473, 502, 526` | Reads string input `#vitals-allergies` and writes scalar `text` directly to `citizens.allergies` | `citizens.allergies` is `text[]` (whereas `consultations.allergies` is `text`) | Type mismatch / malformed array literal on insert or update (`'None'` comparison also assumes string) |
| `web/src/js/services/authService.js:290-292` | Direct client `.from('staff').upsert(payload, { onConflict: 'email' })` | `staff` has **no `INSERT` RLS policy** | Fails under RLS unless replaced by `register_staff_direct` / admin RPC |
| `web/src/js/controllers/triageController.js:530-533, 580-595` | Direct nurse `.from('citizens').insert(...)`, `.from('citizens').update(...)`, `.from('queue_tickets').insert(...)` | `citizens` has no `INSERT` policy and only `citizens_update_own` (`auth_user_id = auth.uid()`); `queue_tickets` only has `queue_tickets_insert_citizen` | Walk-in registration & nurse-issued walk-in queue ticket fail RLS |
| `web/backend/auth-routes.js` | Express route stubs (`findUserByEmail` returns `null`) | Unused stub backend alongside direct Supabase SDK usage | Dead code / misleading architecture artifact |

#### B. Live Schema Tables Unused in Client Code (or Only Used Internally)
All 24 live `public` tables exist in the database, but **7 tables have zero direct `.from()` calls** across `web/src/`, `mobile/lib/`, and `supabase/functions/`:
- **Truly Unused / Unwired Tables (0 live rows, 0 client calls):**
  - `audit_log` (0 rows, 0 client calls, **0 RPC references** — completely unused)
  - `consultation_attachments` (0 rows, 0 client calls, **0 RPC references** — completely unused)
  - `medicine_restock_logs` (0 rows, 0 client calls; written only by `restock_medicine()` RPC, which itself is broken and uncalled by UI)
  - `clinic_transactions` (0 rows, 0 client calls; read only by `get_financial_summary()` RPC, which has no UI caller)
- **RPC-Only Tables (actively used via `SECURITY DEFINER` RPCs, no `.from()` needed):**
  - `dispense_returns` (`return_dispensed_prescription_item`, `return_otc_dispensed_item`, `refresh_operational_test_data`)
  - `otc_dispense_items` (`dispense_otc_medicines`, `get_my_medicine_schedule`, `get_my_prescription_dispense_logs`, `return_otc_dispensed_item`)
  - `system_config` (`get_queue_limiter_status`, `get_daily_ticket_limit`, `is_queue_limiter_enabled`, `check_and_delete_old_queue_tickets`)

---

### 2. Broken Live Database Functions, Dead Table References & Overloaded RPCs

| Database Function | Defect Observed in Live `pg_proc` Source | Impact |
|---|---|---|
| `get_my_medicine_schedule(p_citizen_id)` | OTC `UNION ALL` branch selects `coalesce(m.dosage, '')` from `medicines m`; `medicines` has `dosage_form` & `dosage_strength`, **no `dosage` column** | Mobile Medicine Schedule RPC fails (`column m.dosage does not exist`) |
| `get_my_prescription_dispense_logs(p_prescription_id, p_limit, p_citizen_id)` | OTC CTE selects `coalesce(m.dosage, '')` from `medicines m` | Mobile dispense log primary RPC fails before falling back to `get_my_dispense_history` |
| `return_dispensed_prescription_item(p_prescription_item_id, p_quantity, p_reason)` | Sets `v_new_status := 'partially_dispensed'` and updates `prescription_headers.dispensing_status` | Violates `chk_dispensing_status` (allowed: `'pending'`, `'partial'`, `'dispensed'`, `'cancelled'`, `'expired'`); caught & returned as `{ "error": ... }` |
| `merge_walkin_to_citizen(p_walkin_identifier, p_citizen_id)` | Updates `queue_tickets SET citizen_type = 'citizen'` | Violates `queue_tickets_citizen_type_valid` (allowed: `'regular'`, `'pwd'`, `'pregnant'`) |
| `approve_pending_staff(pending_id)` | Queries and deletes from `public.pending_staff` | Fails (`relation "public.pending_staff" does not exist`) |
| `refresh_operational_test_data()` | References `public.pending_staff` alongside operational resets | Fails unless `pending_staff` guard/branch removed |
| `get_inventory_report()` & `restock_medicine(...)` | Query/insert into `public.medicine_inventory_transactions` | Fails (`relation "public.medicine_inventory_transactions" does not exist`) |
| `restock_prescription_item(...)` | Inserts into `public.medicine_return_logs` (replaced by `dispense_returns`) | Fails (`relation "public.medicine_return_logs" does not exist`) |
| `handle_new_user()` (`on_auth_user_created` on `auth.users`) | Trigger body does nothing (`return new;`) | Active trigger overhead with no behavior |
| `check_and_delete_old_queue_tickets()` | Returns `trigger`, references `system_config` cleanup date | **Not attached to any trigger** in `pg_trigger` (cleanup runs via `pg_cron` job `delete-old-pending-queue-tickets`) |

#### Overloaded RPC Signatures (PostgREST Ambiguity Risk)
Five function names in `public` have 2 overloaded definitions each (`114` total functions across `109` distinct names):
1. `dispense_otc_medicines(p_citizen_id, p_patient_name, p_items, p_notes)` **vs.** `dispense_otc_medicines(p_items, p_citizen_id, p_walkin_name, p_patient_name, p_notes)` — actively called in `web/src/js/dashboard-pharmacist.js:1532` (disambiguated only because caller supplies `p_walkin_name`)
2. `dispense_prescription(p_prescription_code)` **vs.** `dispense_prescription(p_prescription_code, p_items, p_note)`
3. `get_my_dispense_history(p_prescription_id, p_limit)` **vs.** `get_my_dispense_history(p_prescription_id, p_limit, p_citizen_id)` — called in `mobile/lib/services/prescription_service.dart:212`
4. `purge_completed_queue_tickets(p_queue_date, p_service_key)` **vs.** `purge_completed_queue_tickets(p_queue_date, p_service_key, p_grace_seconds)`
5. `update_staff_account_admin(...9 args)` **vs.** `update_staff_account_admin(...10 args w/ p_status)` — called in `web/src/js/services/staffService.js:97`

---

### 3. Implied Relationships Without Foreign Key Constraints

The schema relies on **14 implied relationships** without FK enforcement (full details in [`erd.md`](./erd.md#part-c-implied-un-enforced-relationships)):
- **Auth UUID & Email Bridges (no FK to `auth.users`):** `staff.auth_user_id` (`UK`), `citizens.auth_user_id` (`UK`), `audit_log.performed_by_auth_uid`, and `pending_citizen_signups.email` (`<->` `citizens.email` / `auth.users.email`). Deleting an Auth user does not cascade automatically (requiring imperative cleanup inside `delete_staff_member()`).
- **Polymorphic String Foreign Keys (`patient_identifier`):** `consultations.patient_identifier` (`NOT NULL`) and `prescription_headers.patient_identifier` (`NOT NULL`) encode `'CIT-<id>'`, `'<id>'`, `'<ticket_code>'`, `'QUEUE-<id>'`, or walk-in names alongside nullable typed FKs `patient_citizen_id`. Mobile RPCs & RLS policies must run multi-branch regex/substring/EXISTS scans across `citizens` and `queue_tickets`.
- **Name-Based Medicine Fallback:** `prescription_items.medicine_id` is nullable, falling back to case-insensitive `lower(trim(medicine_name)) = lower(trim(medicines.name))` at dispense/return time.
- **Unconstrained Polymorphic / External Links:** `audit_log.(entity_type, entity_id)`, `clinic_transactions.reference_id`, `feedbacks.from_email` (`<->` `citizens.email`), and `announcements.image_url` (`<->` `storage.objects` in `promo-banners`).

---

### 4. Foreign Keys Without Supporting Indexes (14 of 42)

Exactly **14 foreign key columns** lack a leading-column B-tree index (causing sequential scans during parent deletes/updates and joins):

| # | Child Table.Column | Referenced Parent | `ON DELETE` | Risk / Notes |
|---:|---|---|---|---|
| 1 | `announcements.created_by_staff_id` | `staff.id` | `SET NULL` | Embedded join in `promoPosterController.js` & `dashboard-admin.js` |
| 2 | `clinic_transactions.created_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 3 | `consultation_attachments.uploaded_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 4 | `dispense_returns.otc_item_id` | `otc_dispense_items.id` | `SET NULL` | Note `prescription_item_id` is indexed, `otc_item_id` was missed |
| 5 | `doctor_schedules.created_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 6 | `feedbacks.citizen_id` | `citizens.id` | `SET NULL` | Embedded citizen join in `reportsHubController.js` |
| 7 | `lab_orders.doctor_staff_id` | `staff.id` | `SET NULL` | Embedded doctor join in `usersController.js` & `health-records.js` |
| 8 | `medicine_intake_logs.prescription_item_id` | `prescription_items.id` | `CASCADE` | Column is 2nd in `unique_intake_per_dose_per_day`, **not leading** -> slow cascade when deleting prescription items |
| 9 | `medicine_restock_logs.restocked_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 10 | `medicines.created_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 11 | `prescription_headers.dispensed_by_staff_id` | `staff.id` | `SET NULL` | Scan on `staff` delete |
| 12 | `prescription_item_dispenses.medicine_id` | `medicines.id` | `SET NULL` | Scan on `medicines` delete |
| 13 | `system_config.updated_by` | `auth.users.id` | `NO ACTION` | Blocks `auth.users` delete if referenced without index scan |
| 14 | `vital_signs.nurse_id` | `staff.id` | `SET NULL` | Embedded nurse join in `usersController.js` & `health-records.js` |

---

### 5. Orphan Tables

- **`pending_citizen_signups`**: Structurally an orphan table (`0` incoming or outgoing `FOREIGN KEY` constraints). It serves cleanly as a short-lived OTP registration staging table accessed exclusively via Supabase Edge Functions (`service_role`), matching `citizens.email` and `auth.users.email` implicitly.
- **`audit_log`** and **`consultation_attachments`**: Have enforced FKs (`staff.id`, `consultations.id`), yet are functionally orphaned from application code (`0` rows, `0` client queries, `0` RPC calls).

---

### 6. RLS Security Gaps, Redundant Policies & Over-Broad Grants

- **RLS Status Across All Tables:** Every one of the **24 `public` tables** has `relrowsecurity = true` (`rls_enabled = true`) — **0 tables have RLS disabled**.
- **Critical Stale / Over-Permissive Policies:**
  1. `vital_signs`: Policy `"Allow staff to update vital signs"` (`TO authenticated`, `USING (true)`, `WITH CHECK (true)`) completely nullifies `vital_signs_update_staff`, allowing **any logged-in citizen** to modify any patient's vital signs.
  2. `system_config`: Policies `"Anyone can read system config"` (`TO public`, `USING (true)`) and `"Authenticated users can update system config"` (`TO public`, `USING (auth.uid() IS NOT NULL)`, `WITH CHECK (auth.uid() IS NOT NULL)`) allow **any logged-in citizen or non-admin staff** to read and alter clinic limits/cleanup config (`anon` is blocked only by table `REVOKE`).
  3. `audit_log`: Policy `audit_log_insert_authenticated` (`TO public`, `WITH CHECK (true)`) paired with default table `INSERT` grant to `anon` lets **unauthenticated `anon` users** forge `audit_log` rows.
  4. `staff`: `staff_select_unified`, `staff_update_unified`, and `staff_delete_unified` authorize admins via `auth.jwt() -> 'user_metadata' ->> 'role' = 'admin'`, which reads client-writable `raw_user_meta_data` instead of strictly `app_metadata` / `is_admin()`.
  5. `feedbacks`: `feedbacks_delete_doctor_or_admin` evaluates `(is_doctor_or_admin() OR is_clinical_staff() OR is_active_staff() OR is_admin())`; because `is_active_staff()` matches all active roles, **pharmacists and nurses** can delete feedback despite the policy name.
- **Redundant / Overlapping Policies:**
  - `medicine_intake_logs`: `"Citizens can manage their own intake logs"` (`ALL`) already subsumes `"Citizens can insert their own intake logs"` (`INSERT`) and `"Citizens can view their own intake logs"` (`SELECT`).
  - `medicines`: `medicines_select_active_staff` already covers `medicines_select_pharmacist`.
- **Excessive Function `EXECUTE` Privileges:** **All 114 non-C functions** in `public` grant `EXECUTE` to `anon`, `authenticated`, and `public` (including `approve_pending_staff`, `refresh_operational_test_data`, `delete_staff_member`, `delete_old_pending_queue_tickets`, and `reset_staff_password_admin`), leaving internal procedural checks as the sole barrier.

---

### 7. Migration Drift, Naming & Schema Design Inconsistencies

1. **Local vs. Remote Migration Drift (`20` Mismatches out of `183`):**
   - `20260501110000`: remote `enhance_medicine_inventory` vs. local `auto_generate_staff_employee_id.sql`
   - `20260511000004`: remote `fix_create_queue_ticket_ambiguous_queue_number` vs. local `fix_staff_status_case_sensitivity.sql`
   - `18` migrations between `20260910000000` and `20261108143000` exist locally without matching version rows in remote `supabase_migrations`, while remote has 18 different version rows not listed cleanly 1:1 (exact `183` count on each side masks diverged filenames/versions, and `audit_log`, `clinic_transactions`, `consultation_attachments`, `medicine_restock_logs` lack local `CREATE TABLE` DDL entirely).
2. **Duplicate & Overlapping Columns:**
   - `medicines`: both `expiration_date` (`date`) and `expiry_date` (`date`).
   - `consultations`: both `history_of_present_illness` and `hpi`; both `physical_examination` (`jsonb`) and `physical_exam` (`jsonb`); both `lab_requests` (`jsonb`) and `lab_orders` (`text`, alongside normalized table `public.lab_orders`).
3. **Inconsistent Column & Type Naming Conventions:**
   - **Name fields:** `citizens.firstname` / `surname` / `middle_initial` vs. `staff.first_name` / `last_name` / `middle_name`.
   - **Staff FK naming:** `vital_signs.nurse_id` vs. `doctor_staff_id`, `created_by_staff_id`, `dispensed_by_staff_id`, `returned_by_staff_id`, `restocked_by_staff_id`, `uploaded_by_staff_id`, `performed_by_staff_id`.
   - **Primary key types:** `20` tables use `bigint` (`int8` identity), `3` tables use `uuid` (`gen_random_uuid()`: `vital_signs`, `lab_orders`, `medicine_intake_logs`), and `1` table uses `text` (`system_config.config_key`).
   - **Allergy type mismatch:** `citizens.allergies` is `text[]`, while `consultations.allergies` is `text`.
   - **Timestamp inconsistency:** Most tables use `created_at`/`updated_at`; `otc_dispenses` uses `dispensed_at` without `created_at`; `dispense_returns` uses `returned_at` without `created_at`; `staff_login_logs` uses `logged_at` without `created_at`.
   - **Status case drift:** `staff.status` defaults to Title Case `'Active'`, whereas `trg_normalize_staff_columns` normalizes to lowercase `'active'`/`'disabled'`.
4. **Duplicate Indexes (14 Redundant/Overlapping Indexes Across 9 Tables) & Duplicate Check:**
   - `citizens`: `idx_citizens_auth_user_id` duplicates UK `citizens_auth_user_id_key`.
   - `staff`: `idx_staff_auth_user_id` duplicates UK `staff_auth_user_id_key`.
   - `consultations`: `idx_consultations_date` duplicates `idx_consultations_consulted_at`; `idx_consultations_doctor` duplicates `idx_consultations_doctor_staff_id`.
   - `otc_dispenses`: `idx_otc_dispenses_dispensed_at` overlaps `idx_otc_dispenses_date`; `idx_otc_dispenses_ref` duplicates UK `otc_dispenses_reference_no_key`.
   - `prescription_headers`: `idx_prescription_headers_doctor` duplicates `idx_prescription_headers_doctor_staff_id`; `idx_prescription_headers_patient_ident` duplicates `idx_prescription_headers_patient_identifier`; `idx_prescription_headers_code` overlaps UK `prescription_headers_prescription_code_key`.
   - `prescription_item_dispenses`: `idx_rx_dispenses_dispensed_at` duplicates `idx_pid_dispensed_at`.
   - `prescription_items`: `idx_prescription_items_med_id` duplicates `idx_prescription_items_medicine_id`; `idx_prescription_items_header` duplicates `idx_prescription_items_prescription_id`.
   - `queue_tickets`: `idx_queue_tickets_ticket_code` duplicates UK `queue_tickets_ticket_code_key`; duplicate `CHECK` constraints `queue_tickets_service_label_non_empty` and `queue_tickets_service_label_not_whitespace` both enforce `length(TRIM(BOTH FROM service_label)) > 0`.
   - `vital_signs`: `idx_vital_signs_queue_ticket_id` duplicates UK `uq_vital_signs_queue_ticket`.
