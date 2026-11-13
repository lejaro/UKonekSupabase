# UKonek Role-Based Access Control (RBAC) & RLS Matrix

> **Scope:** Access rules derived directly from live PostgreSQL `pg_policies` (`74` `public` policies + `4` `storage.objects` policies), `information_schema.role_table_grants`, `pg_proc` `SECURITY DEFINER` helpers/RPCs, and Supabase Edge Functions on project `dqjxpwbsbzagbjtulhue`. All `24` `public` tables have **Row Level Security (`RLS`) enabled**.

---

## 1. Roles & How They Are Stored

UKonek does **not** use a dedicated `roles` join table or PostgreSQL custom role hierarchy per user role. All API clients connect as Supabase PostgreSQL roles `anon`, `authenticated`, or `service_role`. Application roles are resolved via database profile tables and JWT metadata:

| Role | Storage Location & Values | Active / Linking Condition |
|---|---|---|
| **`anon`** | Built-in PostgreSQL/Supabase unauthenticated role (`auth.uid() IS NULL`) | Default unauthenticated PostgREST key |
| **`citizen`** | `public.citizens.role` (`varchar(50)`, default `'citizen'`), linked via `citizens.auth_user_id = auth.uid()` | RLS policies resolve `EXISTS (SELECT 1 FROM citizens c WHERE c.auth_user_id = auth.uid())` |
| **`admin`** | `public.staff.role = 'admin'` (normalized lowercase by `trg_normalize_staff_columns`), plus optional JWT `app_metadata.role` / `user_metadata.role` | Must have `lower(trim(staff.status)) = 'active'` and match `auth_user_id = auth.uid()` or JWT email (unless bypassed by stale policy/JWT fallback) |
| **`doctor`** | `public.staff.role = 'doctor'` (comment on column also mentions `'receptionist'`, though no `receptionist` RLS branch or active UI exists; `medicines_update_admin_doctor_nurse` also references `'specialist'`) | Active row in `public.staff` (`lower(trim(status)) = 'active'`) |
| **`nurse`** | `public.staff.role = 'nurse'` | Active row in `public.staff` (`lower(trim(status)) = 'active'`) |
| **`pharmacist`** | `public.staff.role = 'pharmacist'` | Active row in `public.staff` (`lower(trim(status)) = 'active'`) |
| **`service_role`** | Supabase server-side privileged key (used by Edge Functions `citizen-*`) | Bypasses RLS entirely |

### Authorization Helper Functions (`SECURITY DEFINER` in `public`)

All four RLS helpers disable row security internally (`PERFORM set_config('row_security', 'off', true)`) to avoid RLS recursion on `public.staff`, and match the caller via `auth_user_id = auth.uid()` **or** `lower(trim(email)) = lower(trim(auth.jwt()->>'email'))` with `lower(trim(coalesce(status, ''))) = 'active'`:

- `is_active_staff()` -> `status = 'active'` (any `staff.role`: `admin`, `doctor`, `nurse`, `pharmacist`)
- `is_clinical_staff()` -> `status = 'active'` AND `role IN ('doctor', 'nurse', 'admin')`
- `is_doctor_or_admin()` -> `status = 'active'` AND `role IN ('doctor', 'admin')`
- `is_admin()` -> `status = 'active'` AND `role = 'admin'`
- `get_staff_role()` -> returns `staff.role` for active staff (and opportunistically backfills `staff.auth_user_id` if matching by email)

> **Security Note on JWT `user_metadata`:** `staff_select_unified`, `staff_update_unified`, `staff_delete_unified`, and `system_config_read_policy` check `auth.jwt() -> 'user_metadata' ->> 'role' = 'admin'`, which relies on user-modifiable `raw_user_meta_data` unless locked down. Live `auth.users` rows were observed containing `raw_user_meta_data.role` values including `'admin'`, `'citizen'`, `'doctor'`, `'nurse'`, `'staff'`.

---

## 2. Direct PostgREST Access Matrix (RLS + Table Grants)

**Legend (per table/role):**
- **S** = `SELECT`, **I** = `INSERT`, **U** = `UPDATE`, **D** = `DELETE`, **—** = Denied by RLS or Table `GRANT`
- `(own)` = Scoped to caller's own citizen/doctor/staff record or filtered rows
- **`[BUG]`** = Over-permissive or unintended access confirmed in live `pg_policies`
- *(Edge / RPC writes bypassing direct table RLS are summarized separately in Section 3 so direct PostgREST permissions stay unmistakable.)*

> **`service_role`** has full `S / I / U / D` (RLS bypass) on all `24` `public` tables and `storage.objects`; excluded from columns below for readability.

| Table (`public` / `storage`) | `anon` | `citizen` | `nurse` | `doctor` | `pharmacist` | `admin` | Primary Policy / Grant Conditions |
|---|---|---|---|---|---|---|---|
| **`announcements`** | `S` (filtered) | `S` (filtered) | `S / I / U / D` | `S / I / U / D` | `S` | `S / I / U / D` | `anon`/`citizen`: `SELECT` where `visibility` is NULL/`'all'`/`'citizen'`/`'citizens'`. Active staff: `SELECT` all. Clinical staff + admin (`doctor`, `nurse`, `admin`): `INSERT`/`UPDATE`/`DELETE`. |
| **`audit_log`** | **`I [BUG]`** | **`I [BUG]`** | **`I [BUG]`** | **`I [BUG]`** | **`I [BUG]`** | `S` / **`I [BUG]`** | `audit_log_select_admin` restricts `SELECT` to `is_admin()`. However `audit_log_insert_authenticated` targets `{public}` with `WITH CHECK (true)` and `anon` has table `INSERT` grant. |
| **`citizens`** | — | `S(own) / U(own)` | `S` | `S` | `S` | `S` | `SELECT`: own `auth_user_id` OR `is_active_staff()` OR `is_admin()`. `UPDATE`: own row only. **No `INSERT` or `DELETE` RLS policies exist** (profile creation uses `service_role` Edge Function; no staff update/insert allowed). |
| **`clinic_transactions`** | — | — | `S` | `S` | `S` | `S / I / U / D` | Any active staff (`is_active_staff()`-style check) + admin can `SELECT`. Only `is_admin()` can `INSERT` / `UPDATE` / `DELETE`. |
| **`consultation_attachments`** | — | — | `S / I` | `S / I` | `S` | `S / I` | Any active staff + admin can `SELECT`. `doctor`, `nurse`, and `is_admin()` can `INSERT`. No `UPDATE` or `DELETE` policies. |
| **`consultations`** | — | `S(own)` | `S / U` | `S / I(own) / U` | `S` | `S` | `SELECT`: active staff/admin, or citizen matching `patient_citizen_id`, `patient_identifier`, or `queue_tickets`. `INSERT`: active `doctor` with `doctor_staff_id = s.id`. `UPDATE`: `doctor` or `nurse` (`consultations_update_nurse_vitals`). No `DELETE` policy. |
| **`dispense_returns`** | — | — | `S` | `S` | `S` | `S` | Active staff `SELECT` only. Writes occur only inside `SECURITY DEFINER` RPCs (`return_dispensed_prescription_item`, `return_otc_dispensed_item`). |
| **`doctor_schedules`** | — | — | `S` | `S` | `S` | `S / I / U / D` | Active staff `SELECT`; `is_admin()` `INSERT` / `UPDATE` / `DELETE`. Citizens read via `SECURITY DEFINER` RPCs (`list_available_doctor_schedules`, `list_staff_accounts`). |
| **`feedbacks`** | — | `I(own)` | `S` / **`D [BUG]`** | `S` / `D` | `S` / **`D [BUG]`** | `S / I / U / D` | Citizens can `INSERT` (`citizen_id IS NULL` or own); no citizen `SELECT`. Active staff `SELECT`. `feedbacks_delete_doctor_or_admin` includes `is_active_staff()`, allowing `nurse` & `pharmacist` to `DELETE`. `feedbacks_manage_admin` grants `admin` `ALL`. |
| **`lab_orders`** | — | — | `S / U` | `S / I / U` | `S` | `S / D` | Active staff `SELECT`; active `doctor` `INSERT`; `doctor` or `nurse` `UPDATE`; `is_admin()` `DELETE`. Citizens have no `SELECT` policy. |
| **`medicine_intake_logs`** | — | `S/I/U/D(own)` | `S` | `S` | `S` | `S` | Citizens `ALL` (`S/I/U/D`) on own `citizen_id` (plus redundant `INSERT` & `SELECT` policies). Active staff `SELECT` all. |
| **`medicine_restock_logs`** | — | — | `S / I` | `S / I` | `S / I` | `S / I` | Active staff + admin `SELECT`. `INSERT`: `is_admin()` or active `doctor` / `nurse` / `pharmacist` / `staff`. No `UPDATE` / `DELETE` policies. |
| **`medicines`** | — | — | `S / U(qty>=0)` | `S / U(qty>=0)` | `S / I / U(qty>=0)` | `S / U(qty>=0) / D` | Active staff `SELECT`; active `pharmacist` `INSERT` & `UPDATE`; `is_admin()` / active `doctor` / `specialist` / `nurse` `UPDATE`; `is_admin()` `DELETE`. |
| **`otc_dispense_items`** | — | — | `S` | `S` | `S` | `S` | Active staff `SELECT` only. Inserts/updates occur inside `dispense_otc_medicines` / `return_otc_dispensed_item` RPCs. |
| **`otc_dispenses`** | — | — | `S` | `S` | `S` | `S` | Active staff `SELECT` only. Inserts occur inside `dispense_otc_medicines` RPC. |
| **`pending_citizen_signups`** | — | — | — | — | — | — | `pending_citizen_signups_block_all` (`USING (false) WITH CHECK (false)` for `authenticated`; default-deny for `anon`). Accessed exclusively by Edge Functions (`service_role`). |
| **`prescription_headers`** | — | `S(own)` | `S` | `S / I(own)` | `S / U` | `S` | `SELECT`: active staff/admin, or citizen via `patient_citizen_id` / `patient_identifier` / `queue_tickets`. `INSERT`: active `doctor` matching `doctor_staff_id`. `UPDATE`: active `pharmacist` only. No `DELETE` policy. |
| **`prescription_item_dispenses`** | — | — | — | — | `S / I(own)` | `S` | `SELECT`: `is_admin()` or active `pharmacist`. `INSERT`: active `pharmacist` where `dispensed_by_staff_id = s.id`. Citizens read via `get_my_prescription_dispense_logs` / `get_my_dispense_history` RPCs. |
| **`prescription_items`** | — | — *(via RPC)* | `S` | `S / I(own rx)` | `S` | `S` | `SELECT`: active staff/admin only. `INSERT`: active `doctor` owning parent `prescription_headers`. **No citizen `SELECT`, and no `UPDATE`/`DELETE` policies** (citizens & pharmacists rely on `SECURITY DEFINER` RPCs). |
| **`queue_tickets`** | — | `S/I/U(own)` | `S / U / D` | `S / U / D` | `S / U` | `S / U / D` | `SELECT`: own citizen, active staff, or admin. `INSERT`: **citizen own only** (staff walk-ins blocked unless via RPC/walkin gap). `UPDATE`: active staff/admin, or own citizen (`WITH CHECK status IN ('waiting','cancelled')`). `DELETE`: `doctor`, `nurse`, or `admin`. |
| **`staff`** | — *(revoked)* | `S(doc/nurse)` | `S(own,doc/nurse) / U(own)` | `S(own,doc/nurse) / U(own)` | `S(own,doc/nurse) / U(own)` | `S / U / D` *(+JWT metadata)* | Table `SELECT` revoked from `anon`. `authenticated` sees active `doctor`/`nurse` rows + self; admins also via `is_admin()` or JWT `app_metadata`/`user_metadata`. Self/admin can `UPDATE`; admin (JWT claim!) can `DELETE`. **No `INSERT` policy** (created via admin/register RPCs). |
| **`staff_login_logs`** | — | — | — | — | — | `S` | `is_admin()` `SELECT` only. Inserts via `log_staff_action()` RPC. |
| **`system_config`** | — *(revoked)* | **`S / U [BUG]`** | **`S / U [BUG]`** | **`S / U [BUG]`** | **`S / U [BUG]`** | `S / U` | `anon` privileges revoked cleanly. Stale policies `"Anyone can read system config"` (`USING (true)`) and `"Authenticated users can update system config"` (`auth.uid() IS NOT NULL`) grant every logged-in citizen & staff member `SELECT` and `UPDATE`! |
| **`vital_signs`** | — | `S(own)` / **`U [BUG]`** | `S / I / U` | `S / I / U` | **`U [BUG]`** | **`U [BUG]`** | `SELECT`: own citizen OR active `doctor`/`nurse`. `INSERT`: active `doctor`/`nurse`. Stale permissive policy `"Allow staff to update vital signs"` (`TO authenticated USING (true) WITH CHECK (true)`) allows **any authenticated user** (including citizens) to `UPDATE` all rows. |
| **`storage.objects`** (`promo-banners`) | `S` | `S` | `S / I / U / D` | `S / I / U / D` | `S` | `S / I / U / D` | `promo_banners_public_select`: public `SELECT` on bucket `promo-banners`. Clinical staff + admin (`is_clinical_staff() OR is_admin()`) can `INSERT` / `UPDATE` / `DELETE`. |

---

## 3. Indirect Access Paths (`SECURITY DEFINER` RPCs & Edge Functions)

Because `public` direct RLS policies intentionally withhold direct writes (or citizen reads) on several tables, authorized workflows rely on **`SECURITY DEFINER` RPCs** and **Supabase Edge Functions**:

| Role | Access Mechanism | Target Tables Accessed | Internal Guard Implemented |
|---|---|---|---|
| `anon` (Public Display / Signup) | Edge Functions `citizen-request-otp`, `citizen-verify-otp`, `citizen-complete-signup` | `pending_citizen_signups`, `citizens`, `staff`, `auth.users` | Validates OTP hash/expiry; creates citizen Auth user & `citizens` row (`service_role`). |
| `anon` (Pre-login / TV) | RPCs `resolve_staff_login_email`, `is_citizen_email_available`, `is_citizen_username_available`, `get_tv_queue_display`, `list_available_queue_services`, `get_queue_limiter_status` | `staff`, `citizens`, `pending_citizen_signups`, `queue_tickets`, `doctor_schedules`, `system_config` | Read-only or sanitized lookups safe for public display / login resolution. |
| `citizen` | RPCs `create_queue_ticket`, `cancel_my_queue_ticket`, `get_my_queue_dashboard`, `get_my_consultations`, `get_my_prescribed_medicines`, `get_my_medicine_schedule`, `get_my_prescription_dispense_logs`, `get_my_dispense_history`, `list_available_doctor_schedules`, `list_staff_accounts`, `complete_my_citizen_profile`, `link_my_citizen_auth_by_email` | `queue_tickets`, `vital_signs`, `consultations`, `prescription_headers`, `prescription_items`, `prescription_item_dispenses`, `otc_dispenses`, `otc_dispense_items`, `medicines`, `doctor_schedules`, `staff`, `citizens`, `system_config` | Resolves caller via `auth.uid()` -> `citizens.id` (unless caller is active staff). *(Note: `get_my_medicine_schedule` & `get_my_prescription_dispense_logs` currently error at runtime due to missing `medicines.dosage` column in their OTC `UNION ALL` branch.)* |
| `nurse` / `doctor` | Clinical & Queue RPCs: `upsert_vital_assessment`, `save_consultation_with_vitals`, `advance_queue_ticket`, `set_queue_current_serving`, `list_queue_tickets_for_staff`, `get_vitals_for_ticket`, `get_patient_consultation_history`, `check_prescription_safety`, `set_staff_presence`, `set_staff_availability`, `log_staff_action`, `update_my_staff_profile(_v2)` | `vital_signs`, `consultations`, `queue_tickets`, `citizens`, `staff`, `staff_login_logs`, `prescription_items` | Verifies active clinical staff / doctor via `staff.auth_user_id = auth.uid()`. |
| `pharmacist` | Pharmacy RPCs: `dispense_prescription_items`, `dispense_otc_medicines`, `lookup_prescription_by_code`, `pharmacist_get_medicines`, `pharmacist_upsert_medicine`, `return_dispensed_prescription_item`, `return_otc_dispensed_item`, `restock_medicine` | `prescription_headers`, `prescription_items`, `prescription_item_dispenses`, `otc_dispenses`, `otc_dispense_items`, `dispense_returns`, `medicines`, `medicine_restock_logs` | Checks `staff.role = 'pharmacist'` and active status (some admin/stock RPCs allow active staff). *(Note several pharmacy RPCs contain runtime bugs documented in [`findings.md`](./findings.md).)* |
| `admin` | Admin RPCs: `list_all_staff_admin`, `create_staff_account_admin`, `update_staff_account_admin`, `toggle_staff_status_admin`, `delete_staff_member`, `reset_staff_password_admin`, `set_staff_specialization_admin`, `upsert_doctor_schedule_admin`, `delete_doctor_schedule_admin`, `purge_completed_queue_tickets`, `purge_expired_*`, `get_system_reports_summary`, `get_financial_summary`, `get_consultation_analytics`, `get_patient_statistics`, `get_clinical_operations_metrics`, `get_dashboard_bootstrap_data`, `merge_walkin_to_citizen` | `staff`, `auth.users`, `doctor_schedules`, `queue_tickets`, `consultations`, `vital_signs`, `lab_orders`, `citizens`, `medicines`, `clinic_transactions`, `feedbacks`, `announcements`, `staff_login_logs`, `prescription_headers` | Enforces `is_admin()` (with `delete_staff_member` blocking self-deletion). |

> **Privilege Surface Warning:** All **114** functions in `public` currently retain PostgreSQL `EXECUTE` grants for `anon`, `authenticated`, `public`, and `service_role`, relying exclusively on procedural `IF NOT is_admin()` / `auth.uid()` guards inside each function body.
