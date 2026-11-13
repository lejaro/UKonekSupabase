# UKonek Data Dictionary

> **Source of Truth:** Live PostgreSQL `17.6.1.084` schema on Supabase project `dqjxpwbsbzagbjtulhue` (`UKonek_Plus`). Exact counts observed: **24 `public` tables**, **291 columns**, **127 constraints** (`24` PKs, `42` FKs, `12` named UK constraints + `4` standalone unique indexes, `49` CHECK constraints), **124 indexes**, **17 triggers** (`16` on `public`, `1` on `auth.users`), **0 PostgreSQL `ENUM` types**, **0 views**, and **114 non-C database functions** (`109` distinct names, `5` overloaded RPCs).

---

## Global Schema Objects & Cross-Cutting Notes

### Enumerated Values & Domain Enforcement
- **PostgreSQL `ENUM` Types:** `0` (`pg_enum` is empty). All categorical/status fields use `text` or `character varying` columns constrained via `CHECK` constraints (documented per table below). Note `staff.role` and `lab_orders.priority`/`status` have no `CHECK` constraint (documented via column comment / defaults).
- **Views:** `0` in `public`.

### Auth Linkage (`auth.users` <-> `staff` / `citizens`)
Neither `public.staff.auth_user_id` nor `public.citizens.auth_user_id` has a database-level `FOREIGN KEY` constraint to `auth.users(id)`. Linkage is maintained at application/RPC/Edge Function runtime:
- **Citizen Accounts:** `citizen-complete-signup` Edge Function creates the `auth.users` account and inserts `public.citizens` with `auth_user_id`. Existing citizens without `auth_user_id` are matched by case-insensitive email via `link_my_citizen_auth_by_email()`.
- **Staff Accounts:** `create_staff_account_admin()` / `register_staff_direct()` / `link_staff_to_auth()` associate `staff.auth_user_id` with `auth.users.id`. `get_staff_role()`, `is_admin()`, `is_clinical_staff()`, `is_doctor_or_admin()`, and `is_active_staff()` match either `auth_user_id = auth.uid()` OR `lower(trim(email)) = lower(trim(auth.jwt()->>'email'))`.
- **Auth Signup Trigger:** `auth.users` has `AFTER INSERT` trigger `on_auth_user_created` calling `public.handle_new_user()`, which is currently a **no-op stub** (`return new;`).

### Realtime Publication & Scheduled Jobs
- **`supabase_realtime` (`public` tables):** `prescription_headers`, `queue_tickets`, `staff` (`3` tables).
- **`pg_cron` (`cron.job`):**
  - `delete-old-pending-queue-tickets` (`0 16 * * *` UTC / `00:00` Manila): `SELECT public.delete_old_pending_queue_tickets();`
  - `staff_unavailable_5pm_manila` (`0 9 * * *` UTC / `17:00` Manila): `select public.set_staff_unavailable_after_hours();`
  - `cleanup-cron-logs` (`0 3 * * 0` UTC): `DELETE FROM cron.job_run_details WHERE start_time < now() - interval '7 days'`
- **Supabase Storage (`storage.buckets`):** `promo-banners` (`public = true`, `10 MiB` limit, MIME types: `image/jpeg`, `image/jpg`, `image/png`, `image/webp`, `image/gif`).

---

## Tables in `public` Schema (24)

### 1. `announcements`
Stores clinic announcements and promotional posters shown across staff and citizen apps. *(Live rows observed: 1; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `announcements_pkey` |
| `title` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM title)) > 0)` (`announcements_title_non_empty`) |
| `content` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM content)) > 0)` (`announcements_content_non_empty`) |
| `created_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`announcements_created_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Row creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_announcements_set_updated_at` |
| `visibility` | `varchar(20)` | NO | `'all'::character varying` | — | `CHECK (visibility::text = ANY (ARRAY['all','staff','citizen']))` (`announcements_visibility_check`) |
| `image_url` | `text` | YES | — | — | Implied link to public URL in `promo-banners` storage bucket |

**Indexes (3):** `announcements_pkey (id)`, `idx_announcements_created_at (created_at DESC)`, `idx_announcements_visibility (visibility)`.
**Trigger (1):** `trg_announcements_set_updated_at` (`BEFORE UPDATE` -> `set_announcements_updated_at()`).

---

### 2. `audit_log`
General-purpose audit trail table capturing action metadata, target entity identifiers, and actor references (present on live DB, unreferenced in client code or local table-creation migrations). *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `audit_log_pkey` |
| `action` | `text` | NO | — | — | Recorded action name |
| `entity_type` | `text` | NO | — | — | Polymorphic target table/entity type |
| `entity_id` | `text` | YES | — | — | Polymorphic target record ID |
| `details` | `jsonb` | YES | — | — | Structured event payload |
| `performed_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`audit_log_performed_by_staff_id_fkey`) |
| `performed_by_auth_uid` | `uuid` | YES | — | — | Implied reference to `auth.users(id)` (no FK) |
| `ip_address` | `text` | YES | — | — | Client IP address |
| `created_at` | `timestamptz` | NO | `now()` | — | Log creation timestamp |

**Indexes (4):** `audit_log_pkey (id)`, `idx_audit_log_created_at (created_at DESC)`, `idx_audit_log_entity (entity_type, entity_id)`, `idx_audit_log_staff (performed_by_staff_id)`.

---

### 3. `citizens`
Stores registered citizen and walk-in patient demographics, emergency contacts, medical notes, and optional Supabase Auth user linkage. *(Live rows observed: 46; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `citizens_pkey` |
| `firstname` | `varchar(100)` | NO | — | — | `CHECK (length(TRIM(BOTH FROM firstname)) > 0)` (`citizens_firstname_not_empty`) |
| `surname` | `varchar(100)` | NO | — | — | `CHECK (length(TRIM(BOTH FROM surname)) > 0)` (`citizens_surname_not_empty`) |
| `middle_initial` | `varchar(100)` | YES | — | — | Optional middle name/initial |
| `date_of_birth` | `date` | YES | — | — | Date of birth |
| `age` | `int4` (`integer`) | YES | — | — | Age in years |
| `contact_number` | `varchar(30)` | YES | — | — | Trigram-indexed phone number |
| `sex` | `varchar(10)` | YES | — | — | Patient sex |
| `email` | `varchar(100)` | NO | — | `UK` | `citizens_email_key`; `CHECK (length(TRIM(BOTH FROM email)) > 0 AND email::text ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')` (`citizens_email_not_empty`) |
| `complete_address` | `varchar(255)` | YES | — | — | Residential address |
| `emergency_contact_complete_name` | `varchar(200)` | YES | — | — | Emergency contact full name |
| `emergency_contact_contact_number` | `varchar(30)` | YES | — | — | Emergency contact phone |
| `relation` | `varchar(100)` | YES | — | — | Relationship to emergency contact |
| `username` | `varchar(100)` | YES | — | `UK` | `citizens_username_key` |
| `role` | `varchar(50)` | NO | `'citizen'::character varying` | — | Stored citizen role label |
| `created_at` | `timestamptz` | NO | `now()` | — | Registration timestamp |
| `auth_user_id` | `uuid` | YES | — | `UK` | `citizens_auth_user_id_key`; implied FK `-> auth.users(id)` (NULL for unlinked/walk-in records) |
| `allergies` | `text[]` | YES | — | — | Postgres text array of patient allergies |
| `blood_type` | `text` | YES | — | — | Blood group |
| `medical_notes` | `text` | YES | — | — | Free-text medical history notes |

**Indexes (8):** `citizens_pkey (id)`, `citizens_auth_user_id_key (auth_user_id)` [UK], `citizens_email_key (email)` [UK], `citizens_username_key (username)` [UK], `idx_citizens_auth_user_id (auth_user_id)` [redundant], `idx_citizens_contact_trgm (GIN contact_number gin_trgm_ops)`, `idx_citizens_email_lower (lower(email))`, `idx_citizens_name_trgm (GIN (firstname || ' ' || surname) gin_trgm_ops)`.
**Trigger (1):** `sanitize_citizens_input` (`BEFORE INSERT OR UPDATE` -> `sanitize_text_columns()`).

---

### 4. `clinic_transactions`
Tracks clinic income and expense financial ledger entries (present on live DB; read by `get_financial_summary()` RPC, unreferenced by client code or local table-creation migrations). *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `clinic_transactions_pkey` |
| `transaction_type` | `text` | NO | — | — | `CHECK (transaction_type = ANY (ARRAY['income','expense']))` (`clinic_transactions_type_valid`) |
| `category` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM category)) > 0)` (`clinic_transactions_category_non_empty`) |
| `amount` | `numeric(12,2)` | NO | — | — | `CHECK (amount >= 0::numeric)` (`clinic_transactions_amount_positive`) |
| `description` | `text` | YES | — | — | Transaction details |
| `reference_id` | `text` | YES | — | — | Implied polymorphic external/source reference |
| `transaction_date` | `date` | NO | `CURRENT_DATE` | — | Effective accounting date |
| `created_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`clinic_transactions_created_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_clinic_transactions_updated_at` |

**Indexes (3):** `clinic_transactions_pkey (id)`, `idx_clinic_transactions_date (transaction_date DESC)`, `idx_clinic_transactions_type_date (transaction_type, transaction_date)`.
**Trigger (1):** `trg_clinic_transactions_updated_at` (`BEFORE UPDATE` -> `set_clinic_transactions_updated_at()`).

---

### 5. `consultation_attachments`
Stores file metadata/URLs attached to clinical consultations (present on live DB; unreferenced in client code, RPCs, or local table-creation migrations). *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `consultation_attachments_pkey` |
| `consultation_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.consultations(id) ON DELETE CASCADE` (`consultation_attachments_consultation_id_fkey`) |
| `file_name` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM file_name)) > 0)` (`consultation_attachments_file_name_non_empty`) |
| `file_type` | `text` | YES | — | — | MIME or extension label |
| `file_url` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM file_url)) > 0)` (`consultation_attachments_file_url_non_empty`) |
| `description` | `text` | YES | — | — | Attachment notes |
| `uploaded_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`consultation_attachments_uploaded_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Upload timestamp |

**Indexes (2):** `consultation_attachments_pkey (id)`, `idx_consultation_attachments_consultation_id (consultation_id)`.

---

### 6. `consultations`
Records doctor consultation encounters, SOAP/clinical history, embedded JSON clinical payloads, diagnoses, and follow-up plans. *(Live rows observed: 12; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `consultations_pkey` |
| `patient_identifier` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM patient_identifier)) > 0)` (`consultations_patient_identifier_non_empty`); implied link (`CIT-<id>`, `<id>`, `<ticket_code>`, `QUEUE-<id>`, or walk-in name) |
| `patient_citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE SET NULL` (`consultations_patient_citizen_id_fkey`) |
| `doctor_staff_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.staff(id) ON DELETE RESTRICT` (`consultations_doctor_staff_id_fkey`) |
| `symptoms` | `text` | YES | — | — | Reported symptoms |
| `diagnosis` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM diagnosis)) > 0)` (`consultations_diagnosis_non_empty`) |
| `notes` | `text` | YES | — | — | Clinical consultation notes |
| `consulted_at` | `timestamptz` | NO | `now()` | — | Consultation timestamp |
| `created_at` | `timestamptz` | NO | `now()` | — | Record creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_consultations_set_updated_at` |
| `chief_complaint` | `text` | YES | — | — | Chief complaint text |
| `history_of_present_illness` | `text` | YES | — | — | HPI (see also `hpi`) |
| `vital_signs` | `jsonb` | YES | — | — | Embedded snapshot of vitals |
| `physical_examination` | `jsonb` | YES | — | — | Physical exam JSON (see also `physical_exam`) |
| `lab_requests` | `jsonb` | YES | — | — | Lab requests JSON (see also `lab_orders` text & `public.lab_orders` table) |
| `follow_up_date` | `date` | YES | — | — | Scheduled follow-up date |
| `follow_up_notes` | `text` | YES | — | — | Follow-up instructions |
| `consultation_status` | `text` | NO | `'completed'::text` | — | `CHECK (consultation_status = ANY (ARRAY['awaiting','in_progress','completed']))` (`consultations_status_valid`) |
| `hpi` | `text` | YES | — | — | Expanded clinical HPI field |
| `pmh` | `text` | YES | — | — | Past medical history |
| `allergies` | `text` | YES | — | — | Consultation-level allergies text (note `citizens.allergies` is `text[]`) |
| `immunization_status` | `text` | YES | — | — | Immunization status |
| `social_history` | `text` | YES | — | — | Social history |
| `physical_exam` | `jsonb` | YES | — | — | Expanded clinical physical exam JSONB |
| `differential_diagnosis` | `text` | YES | — | — | Differential diagnosis notes |
| `lab_orders` | `text` | YES | — | — | Free-text lab order summary |

**Indexes (11):** `consultations_pkey (id)`, `idx_consultations_consulted_at (consulted_at DESC)`, `idx_consultations_created_at (created_at)`, `idx_consultations_date (consulted_at DESC)` [duplicate], `idx_consultations_doctor (doctor_staff_id)`, `idx_consultations_doctor_staff_id (doctor_staff_id)` [duplicate], `idx_consultations_follow_up_date (follow_up_date) WHERE follow_up_date IS NOT NULL`, `idx_consultations_patient (patient_citizen_id)`, `idx_consultations_patient_date (patient_citizen_id, consulted_at DESC)`, `idx_consultations_patient_ident (patient_identifier)`, `idx_consultations_status (consultation_status)`.
**Trigger (1):** `trg_consultations_set_updated_at` (`BEFORE UPDATE` -> `set_consultations_updated_at()`).

---

### 7. `dispense_returns`
Audit ledger of returned/restocked prescription or OTC medicine units processed by pharmacy staff. *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `dispense_returns_pkey` |
| `return_type` | `text` | NO | — | — | `CHECK (return_type = ANY (ARRAY['prescription','otc']))` (`dispense_returns_return_type_check`) |
| `prescription_item_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.prescription_items(id) ON DELETE SET NULL` (`dispense_returns_prescription_item_id_fkey`) |
| `otc_item_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.otc_dispense_items(id) ON DELETE SET NULL` (`dispense_returns_otc_item_id_fkey`, **unindexed**) |
| `medicine_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.medicines(id) ON DELETE NO ACTION` (`dispense_returns_medicine_id_fkey`) |
| `quantity` | `int4` (`integer`) | NO | — | — | `CHECK (quantity > 0)` (`dispense_returns_quantity_check`) |
| `reason` | `text` | NO | — | — | Mandatory return reason |
| `returned_by_staff_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.staff(id) ON DELETE NO ACTION` (`dispense_returns_returned_by_staff_id_fkey`) |
| `returned_at` | `timestamptz` | NO | `now()` | — | Return event timestamp |

**Indexes (4):** `dispense_returns_pkey (id)`, `idx_dispense_returns_med (medicine_id)`, `idx_dispense_returns_rx_item (prescription_item_id)`, `idx_dispense_returns_staff (returned_by_staff_id)`.

---

### 8. `doctor_schedules`
Stores scheduled clinic availability slots for doctors (`doctor_staff_id`), used by admins and queue/schedule pickers. *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `doctor_schedules_pkey` |
| `doctor_staff_id` | `int8` (`bigint`) | NO | — | `FK,UK` | `-> public.staff(id) ON DELETE CASCADE` (`doctor_schedules_doctor_staff_id_fkey`); leading col of `uq_doctor_schedules_slot` |
| `doctor_name` | `varchar(200)` | YES | — | — | Denormalized doctor display name snapshot |
| `schedule_date` | `date` | NO | — | `UK` | Part of `uq_doctor_schedules_slot` |
| `start_time` | `time` | NO | — | `UK` | Part of `uq_doctor_schedules_slot` |
| `end_time` | `time` | NO | — | `UK` | `CHECK (end_time > start_time)` (`doctor_schedules_time_range_chk`); part of `uq_doctor_schedules_slot` |
| `notes` | `text` | YES | — | — | Schedule notes |
| `created_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`doctor_schedules_created_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Record creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_doctor_schedules_set_updated_at` |

**Indexes (5):** `doctor_schedules_pkey (id)`, `uq_doctor_schedules_slot (doctor_staff_id, schedule_date, start_time, end_time)` [UNIQUE], `idx_doctor_schedules_date (schedule_date)`, `idx_doctor_schedules_doc_date (doctor_staff_id, schedule_date)`, `idx_doctor_schedules_doctor_date (doctor_staff_id, schedule_date, start_time)`.
**Trigger (1):** `trg_doctor_schedules_set_updated_at` (`BEFORE UPDATE` -> `set_doctor_schedule_updated_at()`).

---

### 9. `feedbacks`
Stores citizen ratings and written feedback submitted from the mobile app and reviewed in the web Reports Hub. *(Live rows observed: 1; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `feedbacks_pkey` |
| `citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE SET NULL` (`feedbacks_citizen_id_fkey`, **unindexed**) |
| `from_email` | `text` | NO | — | — | Submitter email; implied fallback correlation with `citizens.email` |
| `subject` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM subject)) > 0)` (`feedbacks_subject_non_empty`) |
| `message` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM message)) > 0)` (`feedbacks_message_non_empty`) |
| `rating` | `int2` (`smallint`) | YES | — | — | `CHECK (rating IS NULL OR rating >= 1 AND rating <= 5)` (`feedbacks_rating_range`) |
| `created_at` | `timestamptz` | NO | `now()` | — | Submission timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_feedbacks_set_updated_at` |

**Indexes (2):** `feedbacks_pkey (id)`, `idx_feedbacks_created_at (created_at DESC)`.
**Trigger (1):** `trg_feedbacks_set_updated_at` (`BEFORE UPDATE` -> `set_feedbacks_updated_at()`).

---

### 10. `lab_orders`
Tracks laboratory diagnostic orders created by doctors during clinical encounters and updated with completion results. *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | `PK` | `lab_orders_pkey` |
| `consultation_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.consultations(id) ON DELETE CASCADE` (`lab_orders_consultation_id_fkey`) |
| `patient_citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE CASCADE` (`lab_orders_patient_citizen_id_fkey`) |
| `doctor_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`lab_orders_doctor_staff_id_fkey`, **unindexed**) |
| `test_name` | `text` | NO | — | — | Ordered lab test name |
| `priority` | `text` | YES | `'Regular'::text` | — | No `CHECK` constraint |
| `status` | `text` | YES | `'Pending'::text` | — | No `CHECK` constraint |
| `results_notes` | `text` | YES | — | — | Recorded lab result notes |
| `created_at` | `timestamptz` | NO | `now()` | — | Order timestamp |
| `completed_at` | `timestamptz` | YES | — | — | Completion timestamp |

**Indexes (5):** `lab_orders_pkey (id)`, `idx_lab_orders_consultation_id (consultation_id)`, `idx_lab_orders_created_at (created_at DESC)`, `idx_lab_orders_patient_citizen_id (patient_citizen_id)`, `idx_lab_orders_status (status)`.

---

### 11. `medicine_intake_logs`
Records citizen self-reported daily dose adherence per prescribed item, dose slot, and calendar date. *(Live rows observed: 8; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | `PK` | `medicine_intake_logs_pkey` |
| `citizen_id` | `int8` (`bigint`) | YES | — | `FK,UK` | `-> public.citizens(id) ON DELETE CASCADE` (`medicine_intake_logs_citizen_id_fkey`); part of `unique_intake_per_dose_per_day` |
| `prescription_item_id` | `int8` (`bigint`) | YES | — | `FK,UK` | `-> public.prescription_items(id) ON DELETE CASCADE` (`medicine_intake_logs_prescription_item_id_fkey`, **no leading-column index**); part of `unique_intake_per_dose_per_day` |
| `scheduled_time` | `text` | NO | — | — | Dose schedule slot label/time string |
| `actual_time` | `timestamptz` | YES | `now()` | — | Timestamp dose was logged |
| `status` | `text` | YES | `'taken'::text` | — | Intake state (`'taken'`, etc.; no `CHECK` constraint) |
| `dose_index` | `int4` (`integer`) | YES | — | `UK` | Dose index within day; part of `unique_intake_per_dose_per_day` |
| `created_at` | `timestamptz` | YES | `now()` | — | Creation timestamp |
| `intake_date` | `date` | YES | `CURRENT_DATE` | `UK` | Part of `unique_intake_per_dose_per_day` |

**Indexes (3):** `medicine_intake_logs_pkey (id)`, `unique_intake_per_dose_per_day (citizen_id, prescription_item_id, dose_index, intake_date)` [UNIQUE], `idx_medicine_intake_citizen_date (citizen_id, intake_date)`.

---

### 12. `medicine_restock_logs`
Records historical stock replenishment quantities, suppliers, batch numbers, and costs for catalog medicines (present on live DB; referenced by `restock_medicine()` RPC, no client callers or local `CREATE TABLE`). *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `medicine_restock_logs_pkey` |
| `medicine_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.medicines(id) ON DELETE CASCADE` (`medicine_restock_logs_medicine_id_fkey`) |
| `qty_added` | `int4` (`integer`) | NO | — | — | `CHECK (qty_added > 0)` (`medicine_restock_logs_qty_positive`) |
| `previous_qty` | `int4` (`integer`) | NO | `0` | — | Stock before restock |
| `resulting_qty` | `int4` (`integer`) | NO | — | — | Stock after restock |
| `supplier_name` | `text` | YES | — | — | Supplier name |
| `supplier_contact` | `text` | YES | — | — | Supplier phone/email |
| `batch_number` | `text` | YES | — | — | Manufacturer lot/batch code |
| `expiration_date` | `date` | YES | — | — | Batch expiration date |
| `unit_cost` | `numeric(10,2)` | YES | — | — | Unit cost |
| `total_cost` | `numeric(10,2)` | YES | — | — | Computed/total batch cost |
| `notes` | `text` | YES | — | — | Restock notes |
| `restocked_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`medicine_restock_logs_restocked_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Restock event timestamp |

**Indexes (2):** `medicine_restock_logs_pkey (id)`, `idx_medicine_restock_logs_medicine_id (medicine_id, created_at DESC)`.

---

### 13. `medicines`
Clinic pharmacy inventory catalog including generic/brand names, stock counts, classifications, reorder levels, and soft-archival timestamps. *(Live rows observed: 39; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `medicines_pkey` |
| `name` | `text` | NO | — | `UK` | `CHECK (length(TRIM(BOTH FROM name)) > 0)` (`medicines_name_non_empty`); partial unique index `idx_medicines_name_lower_active (lower(trim(name)) WHERE archived_at IS NULL)` |
| `qty` | `int4` (`integer`) | NO | `0` | — | `CHECK (qty >= 0)` (`medicines_qty_non_negative`) |
| `unit` | `text` | YES | — | — | Dispensing unit (tablet, bottle, etc.) |
| `created_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`medicines_created_by_staff_id_fkey`, **unindexed**) |
| `created_at` | `timestamptz` | NO | `now()` | — | Record creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_medicines_set_updated_at` |
| `archived_at` | `timestamptz` | YES | — | — | Soft-delete timestamp |
| `generic_name` | `text` | YES | — | — | Generic drug name |
| `brand_name` | `text` | YES | — | — | Brand name |
| `dosage_form` | `text` | YES | — | — | `CHECK (dosage_form IS NULL OR dosage_form = ANY (ARRAY['tablet','capsule','syrup','suspension','injection','cream','ointment','drops','inhaler','suppository','patch','powder','solution','gel','spray','other']))` (`medicines_dosage_form_valid`) |
| `dosage_strength` | `text` | YES | — | — | Strength (e.g., `500mg`) |
| `expiration_date` | `date` | YES | — | — | Primary expiration date (partially indexed where not archived) |
| `batch_number` | `text` | YES | — | — | Current lot/batch number |
| `supplier_name` | `text` | YES | — | — | Current supplier name |
| `supplier_contact` | `text` | YES | — | — | Current supplier contact |
| `reorder_level` | `int4` (`integer`) | NO | `10` | — | Low-stock alert threshold |
| `category` | `text` | NO | `'general'::text` | — | `CHECK (category = ANY (ARRAY['general','fast_moving','slow_moving','critical','controlled']))` (`medicines_category_valid`) |
| `last_restocked_at` | `timestamptz` | YES | — | — | Last restock timestamp |
| `expiry_date` | `date` | YES | — | — | Duplicate expiry column alongside `expiration_date` |
| `description` | `text` | YES | — | — | Medicine description |
| `drug_classification` | `text` | NO | `'rx'::text` | — | `CHECK (drug_classification = ANY (ARRAY['rx','otc']))` (`medicines_drug_classification_check`) |

**Indexes (6):** `medicines_pkey (id)`, `idx_medicines_name_lower_active (lower(trim(name)) WHERE archived_at IS NULL)` [UNIQUE], `idx_medicines_classification (drug_classification)`, `idx_medicines_created_at (created_at DESC)`, `idx_medicines_expiration_date (expiration_date WHERE expiration_date IS NOT NULL AND archived_at IS NULL)`, `idx_medicines_qty_reorder (qty, reorder_level WHERE archived_at IS NULL)`.
**Trigger (1):** `trg_medicines_set_updated_at` (`BEFORE UPDATE` -> `set_medicines_updated_at()`).

---

### 14. `otc_dispense_items`
Line items linking over-the-counter dispense transactions to individual inventory medicines and quantities. *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `otc_dispense_items_pkey` |
| `otc_dispense_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.otc_dispenses(id) ON DELETE CASCADE` (`otc_dispense_items_otc_dispense_id_fkey`) |
| `medicine_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.medicines(id) ON DELETE NO ACTION` (`otc_dispense_items_medicine_id_fkey`) |
| `quantity` | `int4` (`integer`) | NO | — | — | `CHECK (quantity > 0)` (`otc_dispense_items_quantity_check`) |
| `unit` | `text` | YES | — | — | Dispensing unit |
| `instructions` | `text` | YES | — | — | Pharmacist usage instructions |
| `returned_quantity` | `int4` (`integer`) | NO | `0` | — | `CHECK (returned_quantity >= 0)` (`otc_dispense_items_returned_quantity_check`) |

**Indexes (3):** `otc_dispense_items_pkey (id)`, `idx_otc_dispense_items_dispense (otc_dispense_id)`, `idx_otc_dispense_items_med (medicine_id)`.

---

### 15. `otc_dispenses`
Header table for over-the-counter medicine dispenses to registered citizens or walk-in patients. *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `otc_dispenses_pkey` |
| `reference_no` | `text` | NO | — | `UK` | `otc_dispenses_reference_no_key` |
| `citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE SET NULL` (`otc_dispenses_citizen_id_fkey`) |
| `walkin_patient_name` | `text` | NO | `'Walk-in Patient'::text` | — | Display name for walk-in OTC recipients |
| `dispensed_by_staff_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.staff(id) ON DELETE NO ACTION` (`otc_dispenses_dispensed_by_staff_id_fkey`) |
| `dispensed_at` | `timestamptz` | NO | `now()` | — | Dispense timestamp |
| `notes` | `text` | YES | — | — | Dispense notes |

**Indexes (7):** `otc_dispenses_pkey (id)`, `otc_dispenses_reference_no_key (reference_no)` [UNIQUE], `idx_otc_dispenses_citizen (citizen_id)`, `idx_otc_dispenses_date (dispensed_at DESC)`, `idx_otc_dispenses_dispensed_at (dispensed_at)` [duplicate], `idx_otc_dispenses_ref (reference_no)` [duplicate], `idx_otc_dispenses_staff (dispensed_by_staff_id)`.

---

### 16. `pending_citizen_signups`
Staging table holding hashed OTP verification codes and pending profile JSON payloads during Edge Function citizen signup (`0` FKs; all direct PostgREST access blocked). *(Live rows observed: 0; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `pending_citizen_signups_pkey` |
| `email` | `text` | NO | — | `UK` | `pending_citizen_signups_email_key`; implied link to `citizens.email` & `auth.users.email` |
| `profile` | `jsonb` | NO | — | — | Citizen registration fields staged before confirmation |
| `otp_hash` | `text` | NO | — | — | Hashed email OTP token |
| `otp_expires_at` | `timestamptz` | NO | — | — | Expiration deadline for OTP |
| `attempts_left` | `int4` (`integer`) | NO | `5` | — | Remaining verification attempts |
| `verified_at` | `timestamptz` | YES | — | — | Timestamp OTP was verified |
| `consumed_at` | `timestamptz` | YES | — | — | Timestamp signup finalized into `auth.users` & `citizens` |
| `created_at` | `timestamptz` | NO | `now()` | — | Staging record creation |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_pending_citizen_signups_updated_at` |

**Indexes (3):** `pending_citizen_signups_pkey (id)`, `pending_citizen_signups_email_key (email)` [UNIQUE], `idx_pending_citizen_signups_expires (otp_expires_at)`.
**Trigger (1):** `trg_pending_citizen_signups_updated_at` (`BEFORE UPDATE` -> `set_pending_citizen_signups_updated_at()`).

---

### 17. `prescription_headers`
Header records for prescriptions issued by doctors and tracked through pharmacy dispensing status transitions. *(Live rows observed: 11; RLS: enabled; Realtime: yes)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `prescription_headers_pkey` |
| `consultation_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.consultations(id) ON DELETE SET NULL` (`prescription_headers_consultation_id_fkey`) |
| `patient_identifier` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM patient_identifier)) > 0)` (`prescription_headers_patient_identifier_non_empty`); implied polymorphic patient ref |
| `doctor_staff_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.staff(id) ON DELETE RESTRICT` (`prescription_headers_doctor_staff_id_fkey`) |
| `issued_at` | `timestamptz` | NO | `now()` | — | Prescription issue timestamp |
| `created_at` | `timestamptz` | NO | `now()` | — | Creation timestamp |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_prescription_headers_set_updated_at` |
| `prescription_code` | `text` | YES | — | `UK` | `prescription_headers_prescription_code_key`; generated `BEFORE INSERT` by `trg_generate_prescription_code` |
| `dispensing_status` | `text` | NO | `'pending'::text` | — | `CHECK (dispensing_status = ANY (ARRAY['pending','partial','dispensed','cancelled','expired']))` (`chk_dispensing_status`) |
| `dispensed_by_staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`prescription_headers_dispensed_by_staff_id_fkey`, **unindexed**) |
| `dispensed_at` | `timestamptz` | YES | — | — | Completion dispense timestamp |
| `first_dispensed_at` | `timestamptz` | YES | — | — | First partial/full dispense timestamp |
| `last_dispensed_at` | `timestamptz` | YES | — | — | Most recent dispense timestamp |
| `patient_citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE SET NULL` (`prescription_headers_patient_citizen_id_fkey`) |

**Indexes (13):** `prescription_headers_pkey (id)`, `prescription_headers_prescription_code_key (prescription_code)` [UNIQUE], `idx_prescription_headers_citizen (patient_citizen_id)`, `idx_prescription_headers_code (prescription_code WHERE prescription_code IS NOT NULL)`, `idx_prescription_headers_consultation (consultation_id)`, `idx_prescription_headers_doctor (doctor_staff_id)`, `idx_prescription_headers_doctor_staff_id (doctor_staff_id)` [duplicate], `idx_prescription_headers_issued_at (issued_at DESC)`, `idx_prescription_headers_patient_date (patient_citizen_id, issued_at DESC)`, `idx_prescription_headers_patient_ident (patient_identifier)`, `idx_prescription_headers_patient_identifier (patient_identifier)` [duplicate], `idx_prescription_headers_status (dispensing_status)`, `idx_prescription_headers_upper_code (upper(trim(prescription_code)))`.
**Triggers (2):** `trg_generate_prescription_code` (`BEFORE INSERT` -> `generate_prescription_code()`), `trg_prescription_headers_set_updated_at` (`BEFORE UPDATE` -> `set_prescription_headers_updated_at()`).

---

### 18. `prescription_item_dispenses`
Transactional dispensing log capturing each partial or full fulfillment of a prescription item by a pharmacist. *(Live rows observed: 4; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `prescription_item_dispenses_pkey` |
| `prescription_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.prescription_headers(id) ON DELETE CASCADE` (`prescription_item_dispenses_prescription_id_fkey`) |
| `prescription_item_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.prescription_items(id) ON DELETE CASCADE` (`prescription_item_dispenses_prescription_item_id_fkey`) |
| `medicine_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.medicines(id) ON DELETE SET NULL` (`prescription_item_dispenses_medicine_id_fkey`, **unindexed**) |
| `dispensed_quantity` | `int4` (`integer`) | NO | — | — | `CHECK (dispensed_quantity > 0)` (`chk_prescription_item_dispenses_qty_positive`) |
| `unit` | `text` | YES | — | — | Dispensing unit |
| `note` | `text` | YES | — | — | Pharmacist note |
| `dispensed_by_staff_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.staff(id) ON DELETE RESTRICT` (`prescription_item_dispenses_dispensed_by_staff_id_fkey`) |
| `dispensed_at` | `timestamptz` | NO | `now()` | — | Fulfillment timestamp |
| `created_at` | `timestamptz` | NO | `now()` | — | Creation timestamp |

**Indexes (6):** `prescription_item_dispenses_pkey (id)`, `idx_pid_dispensed_at (dispensed_at)`, `idx_pid_dispensed_by_staff_id (dispensed_by_staff_id, dispensed_at DESC)`, `idx_pid_prescription_id (prescription_id, dispensed_at DESC)`, `idx_pid_prescription_item_id (prescription_item_id, dispensed_at DESC)`, `idx_rx_dispenses_dispensed_at (dispensed_at)` [duplicate].

---

### 19. `prescription_items`
Individual medicine line items within a prescription, holding dosage schedules and remaining/dispensed/returned counters. *(Live rows observed: 18; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `prescription_items_pkey` |
| `prescription_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.prescription_headers(id) ON DELETE CASCADE` (`prescription_items_prescription_id_fkey`) |
| `medicine_name` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM medicine_name)) > 0)` (`prescription_items_medicine_name_non_empty`); implied name fallback if `medicine_id` NULL |
| `quantity` | `int4` (`integer`) | NO | — | — | `CHECK (quantity > 0)` (`prescription_items_quantity_positive`) |
| `unit` | `text` | YES | — | — | Unit |
| `created_at` | `timestamptz` | NO | `now()` | — | Creation timestamp |
| `dosage` | `text` | YES | — | — | Dose amount per intake |
| `frequency` | `text` | YES | — | — | Intake schedule frequency |
| `instructions` | `text` | YES | — | — | Patient instructions |
| `additional_info` | `text` | YES | — | — | Supplementary directions |
| `duration` | `text` | YES | — | — | Course duration |
| `is_available` | `bool` | YES | `true` | — | Clinic pharmacy stock flag |
| `is_dispensed` | `bool` | YES | `false` | — | Synced by `trg_sync_prescription_item_quantities` |
| `dispensed_quantity` | `int4` (`integer`) | NO | `0` | — | `CHECK (dispensed_quantity >= 0 AND dispensed_quantity <= quantity)` (`chk_prescription_items_dispensed_quantity_range`) |
| `remaining_quantity` | `int4` (`integer`) | YES | — | — | `CHECK (remaining_quantity >= 0 AND remaining_quantity <= quantity)` (`chk_prescription_items_remaining_quantity_range`); synced by trigger |
| `last_dispensed_at` | `timestamptz` | YES | — | — | Last partial dispense timestamp |
| `medicine_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.medicines(id) ON DELETE SET NULL` (`prescription_items_medicine_id_fkey`) |
| `returned_quantity` | `int4` (`integer`) | NO | `0` | — | `CHECK (returned_quantity >= 0)` (`prescription_items_returned_quantity_check`) |

**Indexes (7):** `prescription_items_pkey (id)`, `idx_prescription_items_dispensed (prescription_id, is_dispensed)`, `idx_prescription_items_header (prescription_id)`, `idx_prescription_items_med_id (medicine_id)`, `idx_prescription_items_medicine_id (medicine_id)` [duplicate], `idx_prescription_items_prescription_id (prescription_id)` [duplicate], `idx_prescription_items_prescription_remaining (prescription_id, remaining_quantity)`.
**Trigger (1):** `trg_sync_prescription_item_quantities` (`BEFORE INSERT OR UPDATE` -> `sync_prescription_item_quantities()`).

---

### 20. `queue_tickets`
Daily clinic service queue tickets supporting citizens, priority groups, walk-in patients, and real-time TV/staff displays. *(Live rows observed: 0; RLS: enabled; Realtime: yes)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `queue_tickets_pkey` |
| `queue_date` | `date` | NO | `((now() AT TIME ZONE 'Asia/Manila'::text))::date` | `UK` | Part of `idx_queue_tickets_unique_slot` |
| `service_key` | `text` | NO | — | `UK` | `CHECK (length(TRIM(BOTH FROM service_key)) > 0)` (`queue_tickets_service_key_non_empty`); part of `idx_queue_tickets_unique_slot` |
| `service_label` | `text` | NO | — | — | Duplicate `CHECK`: `queue_tickets_service_label_non_empty` & `queue_tickets_service_label_not_whitespace` |
| `queue_number` | `int4` (`integer`) | NO | — | `UK` | `CHECK (queue_number > 0)` (`queue_tickets_queue_number_positive`); part of `idx_queue_tickets_unique_slot` |
| `ticket_code` | `text` | NO | — | `UK` | `queue_tickets_ticket_code_key` |
| `citizen_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.citizens(id) ON DELETE CASCADE` (`queue_tickets_citizen_id_fkey`) |
| `citizen_type` | `text` | NO | — | — | `CHECK (length(TRIM(BOTH FROM citizen_type)) > 0)` (`queue_tickets_citizen_type_not_whitespace`); `CHECK (lower(TRIM(BOTH FROM citizen_type)) = ANY (ARRAY['regular','pwd','pregnant']))` (`queue_tickets_citizen_type_valid`) |
| `reason` | `text` | YES | — | — | Visit reason |
| `symptoms` | `text` | YES | — | — | Symptoms reported at check-in |
| `status` | `text` | NO | `'waiting'::text` | — | `CHECK (lower(TRIM(BOTH FROM status)) = ANY (ARRAY['waiting','on_call','serving','completed','cancelled']))` (`queue_tickets_status_valid`) |
| `created_at` | `timestamptz` | NO | `now()` | — | Ticket issue time |
| `updated_at` | `timestamptz` | NO | `now()` | — | Maintained by `trg_queue_tickets_set_updated_at` |
| `served_at` | `timestamptz` | YES | — | — | Timestamp moved to `serving` |
| `completed_at` | `timestamptz` | YES | — | — | Timestamp completed |
| `walkin_patient_name` | `text` | YES | — | — | Walk-in patient display name |

**Indexes (9):** `queue_tickets_pkey (id)`, `idx_queue_tickets_unique_slot (queue_date, service_key, queue_number)` [UNIQUE], `queue_tickets_ticket_code_key (ticket_code)` [UNIQUE], `idx_queue_tickets_citizen_date (citizen_id, queue_date DESC, created_at DESC)`, `idx_queue_tickets_citizen_id (citizen_id)`, `idx_queue_tickets_created_at (created_at)`, `idx_queue_tickets_date_status (queue_date, status)`, `idx_queue_tickets_service_status (queue_date, service_key, status, queue_number)`, `idx_queue_tickets_ticket_code (ticket_code)` [redundant].
**Triggers (3):** `sanitize_queue_tickets_input` (`BEFORE INSERT OR UPDATE` -> `sanitize_text_columns()`), `trg_normalize_queue_ticket_columns` (`BEFORE INSERT OR UPDATE` -> `normalize_queue_ticket_columns()`), `trg_queue_tickets_set_updated_at` (`BEFORE UPDATE` -> `set_queue_tickets_updated_at()`).

---

### 21. `staff`
Stores clinic staff profiles, authorization roles (`admin`, `doctor`, `nurse`, `pharmacist`), account status, online presence, and availability. *(Live rows observed: 7; RLS: enabled; Realtime: yes)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `staff_pkey` |
| `first_name` | `varchar(100)` | YES | — | — | `CHECK (first_name IS NULL OR length(TRIM(BOTH FROM first_name)) > 0)` (`staff_first_name_not_empty`) |
| `middle_name` | `varchar(100)` | YES | — | — | Optional middle name |
| `last_name` | `varchar(100)` | YES | — | — | `CHECK (last_name IS NULL OR length(TRIM(BOTH FROM last_name)) > 0)` (`staff_last_name_not_empty`) |
| `birthday` | `date` | YES | — | — | Date of birth |
| `gender` | `varchar(20)` | YES | — | — | Gender |
| `username` | `varchar(100)` | NO | — | `UK` | `staff_username_key`; `CHECK (length(TRIM(BOTH FROM username)) > 0)` (`staff_username_not_empty`) |
| `employee_id` | `varchar(100)` | NO | — | `UK` | `staff_employee_id_key` |
| `email` | `varchar(100)` | YES | — | `UK` | `staff_email_key`; `CHECK (email IS NULL OR length(TRIM(BOTH FROM email)) > 0 AND email::text ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')` (`staff_email_not_empty`) |
| `role` | `varchar(100)` | NO | — | — | Lowercased by `trg_normalize_staff_columns`; comment: `"Staff role: doctor, nurse, pharmacist, admin, receptionist"` (no `CHECK`) |
| `consent_given` | `bool` | NO | `false` | — | Privacy/terms consent flag |
| `status` | `varchar(50)` | YES | `'Active'::character varying` | — | Lowercased to `'active'`/`'disabled'` by trigger despite `'Active'` default |
| `created_at` | `timestamptz` | NO | `now()` | — | Creation timestamp |
| `auth_user_id` | `uuid` | YES | — | `UK` | `staff_auth_user_id_key`; implied FK `-> auth.users(id)` |
| `is_online` | `bool` | NO | `false` | — | Real-time presence boolean |
| `last_seen` | `timestamptz` | YES | — | — | Last presence heartbeat |
| `doctor_specialization` | `text` | YES | — | — | Medical specialty label |
| `availability_status` | `text` | NO | `'available'::text` | — | `CHECK (lower(TRIM(BOTH FROM availability_status)) = ANY (ARRAY['available','on_break','unavailable']))` (`staff_availability_status_valid`) |

**Indexes (9):** `staff_pkey (id)`, `staff_auth_user_id_key (auth_user_id)` [UK], `staff_email_key (email)` [UK], `staff_employee_id_key (employee_id)` [UK], `staff_username_key (username)` [UK], `idx_staff_auth_user_id (auth_user_id)` [redundant], `idx_staff_auth_id_status (auth_user_id, status)`, `idx_staff_email_lower (lower(email))`, `idx_staff_online_last_seen (is_online, last_seen DESC)`.
**Triggers (2):** `sanitize_staff_input` (`BEFORE INSERT OR UPDATE` -> `sanitize_text_columns()`), `trg_normalize_staff_columns` (`BEFORE INSERT OR UPDATE` -> `normalize_staff_columns()`).

---

### 22. `staff_login_logs`
Records staff login and logout session events with point-in-time username, email, and role snapshots. *(Live rows observed: 54; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `int8` (`bigint`) | NO | `IDENTITY(BY DEFAULT)` | `PK` | `staff_login_logs_pkey` |
| `staff_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE CASCADE` (`staff_login_logs_staff_id_fkey`) |
| `username` | `text` | NO | — | — | Denormalized staff username snapshot |
| `email` | `text` | NO | — | — | Denormalized staff email snapshot |
| `role` | `text` | NO | — | — | Denormalized staff role snapshot |
| `action` | `text` | NO | — | — | `CHECK (action = ANY (ARRAY['login','logout']))` (`check_staff_action`) |
| `logged_at` | `timestamptz` | NO | `now()` | — | Event timestamp |

**Indexes (3):** `staff_login_logs_pkey (id)`, `idx_staff_login_logs_logged_at (logged_at DESC)`, `idx_staff_login_logs_staff_id (staff_id)`.

---

### 23. `system_config`
Key-value configuration store for clinic operational settings such as daily ticket limits, limiter toggles, and last cleanup dates. *(Live rows observed: 3; table comment: `"System-wide configuration settings"`; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `config_key` | `text` | NO | — | `PK` | `system_config_pkey` |
| `config_value` | `text` | NO | — | — | Stringified setting value |
| `description` | `text` | YES | — | — | Human-readable config description |
| `updated_at` | `timestamptz` | YES | `now()` | — | Last modification timestamp |
| `updated_by` | `uuid` | YES | — | `FK` | `-> auth.users(id) ON DELETE NO ACTION` (`system_config_updated_by_fkey`, **unindexed**) |

**Indexes (1):** `system_config_pkey (config_key)`.

---

### 24. `vital_signs`
Stores nurse-recorded patient vital signs and triage measurements, optionally linked 1:1 to a queue ticket. *(Live rows observed: 9; RLS: enabled; Realtime: no)*

| Column | Data Type | Nullable | Default | Keys | Constraints / Notes |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | `gen_random_uuid()` | `PK` | `vital_signs_pkey` |
| `citizen_id` | `int8` (`bigint`) | NO | — | `FK` | `-> public.citizens(id) ON DELETE CASCADE` (`vital_signs_citizen_id_fkey`) |
| `nurse_id` | `int8` (`bigint`) | YES | — | `FK` | `-> public.staff(id) ON DELETE SET NULL` (`vital_signs_nurse_id_fkey`, **unindexed**) |
| `chief_complaint` | `text` | NO | — | — | Primary triage complaint |
| `blood_pressure` | `text` | YES | — | — | Systolic/diastolic reading |
| `respiratory_rate` | `int4` (`integer`) | YES | — | — | Breaths per minute |
| `temperature` | `numeric(4,1)` | YES | — | — | Body temperature |
| `oxygen_saturation` | `int4` (`integer`) | YES | — | — | SpO2 percentage |
| `current_medications` | `text` | YES | — | — | Medications noted at triage |
| `created_at` | `timestamptz` | NO | `now()` | — | Triage timestamp |
| `heart_rate` | `int4` (`integer`) | YES | — | — | Beats per minute |
| `queue_ticket_id` | `int8` (`bigint`) | YES | — | `FK,UK` | `-> public.queue_tickets(id) ON DELETE SET NULL` (`vital_signs_queue_ticket_id_fkey`); `uq_vital_signs_queue_ticket` enforces 1:1 |
| `notes` | `text` | YES | — | — | Triage notes |
| `height_cm` | `numeric(5,1)` | YES | `NULL::numeric` | — | Height in centimeters |
| `weight_kg` | `numeric(5,1)` | YES | `NULL::numeric` | — | Weight in kilograms |
| `bmi` | `numeric(4,1)` | YES | `NULL::numeric` | — | Calculated BMI |

**Indexes (5):** `vital_signs_pkey (id)`, `uq_vital_signs_queue_ticket (queue_ticket_id)` [UNIQUE], `idx_vital_signs_queue_ticket_id (queue_ticket_id)` [redundant], `idx_vital_signs_citizen_id (citizen_id)`, `idx_vital_signs_created_at (created_at)`.

---

## External Supabase Schemas Referenced

| Schema.Table | Purpose in System | Relationships & Access Notes |
|---|---|---|
| `auth.users` | Supabase Auth identity directory (`id`, `email`, `raw_app_meta_data`, `raw_user_meta_data`, `banned_until`) | Enforced FK from `public.system_config.updated_by`; implied links to `staff.auth_user_id`/`email`, `citizens.auth_user_id`/`email`, `audit_log.performed_by_auth_uid`, and `pending_citizen_signups.email`. Has trigger `on_auth_user_created`. |
| `storage.objects` (`promo-banners`) | Public image storage bucket (`10 MiB` max; jpeg/png/webp/gif) | Holds announcement banner images referenced implicitly via `announcements.image_url`. Public `SELECT`; clinical staff + admin `INSERT`/`UPDATE`/`DELETE`. |
