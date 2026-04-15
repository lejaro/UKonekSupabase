# UKonek System Data Dictionary

Last updated: 2026-04-05
Source of truth: `supabase/migrations/*.sql`, `supabase/functions/*/index.ts`, and active web queue module usage.

Companion docs:
- ER diagram: `docs/architecture/ER_DIAGRAM.md`
- Module split (onboarding): `docs/data-dictionary/README.md`
- Master table format: `docs/data-dictionary/DATA_DICTIONARY_TABLE.md`
- CSV export: `docs/data-dictionary/DATA_DICTIONARY_TABLE.csv`

## 1. Scope

This dictionary documents the **current effective data model** of the system:
- Supabase Postgres tables and relationships
- Important domain constraints and status values
- Database RPC/function contracts used by clients
- Edge Function request/response payloads
- Key web-module data shapes for queue workflows

It excludes historical entities that were removed by later migrations (listed in section 8).

### 1.1 Quick Table Inventory

| Table | Domain Module | Primary Key | Key Foreign Keys | Purpose |
|---|---|---|---|---|
| public.staff | Auth and Identity | id | auth_user_id (logical to auth.users.id) | Staff account/profile records |
| public.citizens | Auth and Identity | id | auth_user_id (logical to auth.users.id) | Citizen profile records |
| public.pending_citizen_signups | Auth and Identity | id | None | OTP-preverified signup staging |
| public.doctor_schedules | Appointments and Scheduling | id | doctor_staff_id -> public.staff.id; created_by_staff_id -> public.staff.id | Doctor availability slots |
| public.appointments | Appointments and Scheduling | id | citizen_id -> public.citizens.id; doctor_staff_id -> public.staff.id | Citizen-doctor appointments |
| public.queue_tickets | Queue Management | id | citizen_id -> public.citizens.id | Queue ticket lifecycle tracking |
| public.medicines | Pharmacy and Consultations | id | created_by_staff_id -> public.staff.id | Medicine inventory |
| public.consultations | Pharmacy and Consultations | id | patient_citizen_id -> public.citizens.id; doctor_staff_id -> public.staff.id | Consultation records |
| public.prescription_headers | Pharmacy and Consultations | id | consultation_id -> public.consultations.id; doctor_staff_id -> public.staff.id | Prescription document headers |
| public.prescription_items | Pharmacy and Consultations | id | prescription_id -> public.prescription_headers.id | Prescription line items |
| public.announcements | Communication and Feedback | id | created_by_staff_id -> public.staff.id | Audience-targeted announcements |
| public.feedbacks | Communication and Feedback | id | citizen_id -> public.citizens.id | Citizen feedback messages |

## 2. Core Entities

### 2.1 `public.staff`
Purpose: Staff identity/profile records (admin, doctor, nurse, staff, specialist).

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| first_name | varchar(100) | Yes |  | |
| middle_name | varchar(100) | Yes |  | |
| last_name | varchar(100) | Yes |  | |
| birthday | date | Yes |  | |
| gender | varchar(20) | Yes |  | |
| username | varchar(100) | No |  | Unique |
| employee_id | varchar(100) | No |  | Unique |
| email | varchar(100) | Yes |  | Unique |
| role | varchar(100) | No |  | Normalized/trimmed by migration |
| consent_given | boolean | No | false | |
| status | varchar(50) | Yes | 'Active' | Normalized/trimmed by migration |
| created_at | timestamptz | No | now() | |
| auth_user_id | uuid | Yes |  | Unique; links to `auth.users.id` |
| is_online | boolean | No | false | Presence flag |
| last_seen | timestamptz | Yes |  | Presence timestamp |
| doctor_specialization | text | Yes |  | Required by RPC when role is doctor |

Indexes:
- `idx_staff_online_last_seen` on `(is_online, last_seen desc)`

Access model:
- RLS enabled
- Select own row for staff, select all for admin
- Delete by admin policy and admin RPCs

---

### 2.2 `public.citizens`
Purpose: Citizen/patient profile records.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| firstname | varchar(100) | No |  | |
| surname | varchar(100) | No |  | |
| middle_initial | varchar(100) | Yes |  | |
| date_of_birth | date | Yes |  | |
| age | integer | Yes |  | |
| contact_number | varchar(30) | Yes |  | |
| sex | varchar(10) | Yes |  | |
| email | varchar(100) | No |  | Unique |
| complete_address | varchar(255) | Yes |  | |
| emergency_contact_complete_name | varchar(200) | Yes |  | |
| emergency_contact_contact_number | varchar(30) | Yes |  | |
| relation | varchar(100) | Yes |  | |
| username | varchar(100) | Yes |  | Unique |
| role | varchar(50) | No | 'citizen' | |
| created_at | timestamptz | No | now() | |
| auth_user_id | uuid | Yes |  | Unique; links to `auth.users.id` |

Access model:
- RLS enabled
- Citizen can select own row
- Admin can select all
- Active staff can select all (`citizens_select_active_staff`)

---

### 2.3 `public.doctor_schedules`
Purpose: Admin-managed doctor schedule slots.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| doctor_staff_id | bigint | No |  | FK -> `staff.id` (cascade delete) |
| doctor_name | varchar(200) | Yes |  | Denormalized display value |
| schedule_date | date | No |  | |
| start_time | time | No |  | |
| end_time | time | No |  | Must be > `start_time` |
| notes | text | Yes |  | |
| created_by_staff_id | bigint | Yes |  | FK -> `staff.id` (set null on delete) |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |

Constraints:
- `doctor_schedules_time_range_chk`: `end_time > start_time`
- Unique slot index `uq_doctor_schedules_slot` on `(doctor_staff_id, schedule_date, start_time, end_time)`

Indexes:
- `idx_doctor_schedules_date` on `(schedule_date)`
- `idx_doctor_schedules_doctor_date` on `(doctor_staff_id, schedule_date, start_time)`

Access model:
- RLS enabled
- Active staff: read
- Admin: insert/update/delete

---

### 2.4 `public.appointments`
Purpose: Citizen-doctor appointment records.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| citizen_id | bigint | No |  | FK -> `citizens.id` (cascade delete) |
| doctor_staff_id | bigint | No |  | FK -> `staff.id` (cascade delete) |
| appointment_date | date | No |  | |
| appointment_time | time | No |  | |
| status | varchar(50) | No | 'pending' | check: pending/confirmed/completed/cancelled/no-show |
| patient_notes | text | Yes |  | |
| doctor_notes | text | Yes |  | |
| cancellation_reason | text | Yes |  | |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | |
| created_by | uuid | Yes |  | auth user id |
| cancelled_by | uuid | Yes |  | auth user id |
| cancelled_at | timestamptz | Yes |  | |

Indexes:
- `idx_appointments_citizen_id`
- `idx_appointments_doctor_staff_id`
- `idx_appointments_date`
- `idx_appointments_status`

Access model:
- RLS enabled
- Citizens: view/create/update own appointments under policy conditions
- Doctors: view/update own assigned appointments
- Admin/staff roles have broad select; admin has all-management policy

---

### 2.5 `public.announcements`
Purpose: Dashboard/mobile announcements.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| title | text | No |  | Non-empty trimmed |
| content | text | No |  | Non-empty trimmed |
| created_by_staff_id | bigint | Yes |  | FK -> `staff.id` (set null on delete) |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |
| visibility | varchar(20) | No | 'all' | check: all/staff/citizen |

Constraints:
- `announcements_title_non_empty`
- `announcements_content_non_empty`

Indexes:
- `idx_announcements_created_at` on `(created_at desc)`
- `idx_announcements_visibility` on `(visibility)`

Access model:
- RLS enabled
- Active staff read
- Admin write/delete

---

### 2.6 `public.feedbacks`
Purpose: Citizen feedback submissions.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| citizen_id | bigint | Yes |  | FK -> `citizens.id` (set null on delete) |
| from_email | text | No |  | |
| subject | text | No |  | Non-empty trimmed |
| message | text | No |  | Non-empty trimmed |
| rating | smallint | Yes |  | Must be 1..5 when provided |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |

Constraints:
- `feedbacks_subject_non_empty`
- `feedbacks_message_non_empty`
- `feedbacks_rating_range`

Indexes:
- `idx_feedbacks_created_at` on `(created_at desc)`

Access model:
- RLS enabled
- Active staff read
- Citizens insert (self/optional citizen_id)
- Admin full management

---

### 2.7 `public.medicines`
Purpose: Medicine inventory.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| name | text | No |  | Non-empty trimmed |
| qty | integer | No | 0 | Must be >= 0 |
| unit | text | Yes |  | |
| created_by_staff_id | bigint | Yes |  | FK -> `staff.id` (set null on delete) |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |
| archived_at | timestamptz | Yes |  | Soft delete marker |

Constraints:
- `medicines_name_non_empty`
- `medicines_qty_non_negative`

Indexes:
- `idx_medicines_name_lower_active` unique partial index on `lower(trim(name)) where archived_at is null`
- `idx_medicines_created_at` on `(created_at desc)`

Access model:
- RLS enabled
- Active staff read
- Insert by admin/doctor/specialist
- Update by admin/doctor/specialist/nurse
- Delete by admin only

---

### 2.8 `public.consultations`
Purpose: Consultation notes and diagnosis records.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| patient_identifier | text | No |  | Non-empty |
| patient_citizen_id | bigint | Yes |  | FK -> `citizens.id` (set null on delete) |
| doctor_staff_id | bigint | No |  | FK -> `staff.id` (restrict delete) |
| symptoms | text | Yes |  | |
| diagnosis | text | No |  | Non-empty |
| notes | text | Yes |  | |
| consulted_at | timestamptz | No | now() | |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |

Indexes:
- `idx_consultations_doctor_staff_id`
- `idx_consultations_consulted_at`

Access model:
- RLS enabled
- Active staff/admin select
- Insert restricted to active doctor matching `doctor_staff_id`

---

### 2.9 `public.prescription_headers`
Purpose: Prescription document header metadata.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| consultation_id | bigint | Yes |  | FK -> `consultations.id` (set null on delete) |
| patient_identifier | text | No |  | Non-empty |
| doctor_staff_id | bigint | No |  | FK -> `staff.id` (restrict delete) |
| issued_at | timestamptz | No | now() | |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |

Indexes:
- `idx_prescription_headers_doctor_staff_id`
- `idx_prescription_headers_issued_at`

Access model:
- RLS enabled
- Active staff/admin select
- Insert restricted to active doctor matching `doctor_staff_id`

---

### 2.10 `public.prescription_items`
Purpose: Line items for prescriptions.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| prescription_id | bigint | No |  | FK -> `prescription_headers.id` (cascade delete) |
| medicine_name | text | No |  | Non-empty |
| quantity | integer | No |  | Must be > 0 |
| unit | text | Yes |  | |
| created_at | timestamptz | No | now() | |

Indexes:
- `idx_prescription_items_prescription_id`

Access model:
- RLS enabled
- Active staff/admin select
- Insert allowed only when prescription belongs to current active doctor

---

### 2.11 `public.queue_tickets`
Purpose: Daily service queue tickets for citizens.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| queue_date | date | No | current_date | |
| service_key | text | No |  | Non-empty |
| service_label | text | No |  | Non-empty |
| queue_number | integer | No |  | Must be > 0 |
| ticket_code | text | No |  | Unique |
| citizen_id | bigint | No |  | FK -> `citizens.id` (cascade delete) |
| citizen_type | text | No |  | regular/pwd/pregnant |
| reason | text | Yes |  | |
| symptoms | text | Yes |  | |
| status | text | No | 'waiting' | waiting/on_call/serving/completed/cancelled |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |
| served_at | timestamptz | Yes |  | |
| completed_at | timestamptz | Yes |  | |

Constraints:
- `queue_tickets_service_key_non_empty`
- `queue_tickets_service_label_non_empty`
- `queue_tickets_queue_number_positive`
- `queue_tickets_citizen_type_valid`
- `queue_tickets_status_valid`

Indexes:
- Unique `idx_queue_tickets_unique_slot` on `(queue_date, service_key, queue_number)`
- `idx_queue_tickets_citizen_date`
- `idx_queue_tickets_service_status`

Access model:
- RLS enabled
- Citizen can read/insert own; can update under policy conditions
- Active staff/admin can read and update

---

### 2.12 `public.pending_citizen_signups`
Purpose: Pre-auth OTP signup staging table.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | bigint (identity, PK) | No | generated | Primary key |
| email | text | No |  | Unique |
| profile | jsonb | No |  | Captures citizen profile fields |
| otp_hash | text | No |  | SHA-256 hash |
| otp_expires_at | timestamptz | No |  | |
| attempts_left | integer | No | 5 | |
| verified_at | timestamptz | Yes |  | |
| consumed_at | timestamptz | Yes |  | |
| created_at | timestamptz | No | now() | |
| updated_at | timestamptz | No | now() | Trigger maintained |

Indexes:
- `idx_pending_citizen_signups_expires`

Access model:
- RLS enabled with block-all policy for authenticated clients
- Intended access path: service-role only (Edge Functions)

## 3. Relationship Map

- `doctor_schedules.doctor_staff_id` -> `staff.id`
- `doctor_schedules.created_by_staff_id` -> `staff.id`
- `appointments.citizen_id` -> `citizens.id`
- `appointments.doctor_staff_id` -> `staff.id`
- `announcements.created_by_staff_id` -> `staff.id`
- `feedbacks.citizen_id` -> `citizens.id`
- `medicines.created_by_staff_id` -> `staff.id`
- `consultations.patient_citizen_id` -> `citizens.id`
- `consultations.doctor_staff_id` -> `staff.id`
- `prescription_headers.consultation_id` -> `consultations.id`
- `prescription_headers.doctor_staff_id` -> `staff.id`
- `prescription_items.prescription_id` -> `prescription_headers.id`
- `queue_tickets.citizen_id` -> `citizens.id`

## 4. Domain Value Dictionaries

### 4.1 Appointment Status (`appointments.status`)
- `pending`
- `confirmed`
- `completed`
- `cancelled`
- `no-show`

### 4.2 Queue Status (`queue_tickets.status`)
- `waiting`
- `on_call`
- `serving`
- `completed`
- `cancelled`

### 4.3 Queue Citizen Type (`queue_tickets.citizen_type`)
- `regular`
- `pwd`
- `pregnant`

### 4.4 Announcement Visibility (`announcements.visibility`)
- `all`
- `staff`
- `citizen`

## 5. Database RPC / Function Dictionary

Functions below are those defined in migrations and intended for application or internal DB workflows.

### 5.1 Auth/Identity and Staff
- `is_admin()` -> bool
  - Checks if current auth user maps to active admin in `staff`.
- `get_staff_role()` -> text
  - Returns active staff role for current auth user; includes email-based auto-link behavior.
- `get_staff_profile()` -> json
  - Returns active staff profile for current auth user.
- `set_staff_presence(p_is_online bool default true)` -> bool
  - Updates current staff `is_online` and `last_seen`.
- `link_staff_to_auth(p_email text, p_auth_user_id uuid)` -> json
  - Links staff row to auth user id.
- `create_staff_account_admin(...)` -> json
  - Admin-only staff creation flow with validations.
- `reset_staff_password_admin(...)` -> json
  - Admin-only password reset RPC (see migration for exact signature).
- `set_staff_specialization_admin(...)` -> json
  - Admin-only specialization update.
- `set_my_doctor_specialization(p_specialization text)` -> json
  - Self-service specialization update for doctor.
- `update_my_staff_profile(...)` -> json
  - Staff self profile update.
- `delete_staff_member(target_staff_id bigint)` -> json
  - Admin-only staff delete workflow.

### 5.2 Directory/Schedule
- `list_staff_accounts()` -> setof records
- `list_doctor_schedules()` -> setof records
- `list_available_doctor_schedules(...)` -> setof records
- `upsert_doctor_schedule_admin(...)` -> json/table
- `delete_doctor_schedule_admin(p_id bigint)` -> json
- `purge_expired_doctor_schedules()` -> json/int result

### 5.3 Appointments
- `get_available_doctor_slots(p_doctor_staff_id, p_date_from, p_date_to)` -> table
- `book_appointment(p_citizen_id, p_doctor_staff_id, p_appointment_date, p_appointment_time, p_patient_notes)` -> json
- `list_my_appointments()` -> table
- `list_doctor_appointments(p_status, p_date_from, p_date_to)` -> table
- `list_all_appointments(p_status, p_date_from, p_date_to, p_doctor_staff_id)` -> table

### 5.4 Queue
- `list_available_queue_services(p_date)` -> table
- `create_queue_ticket(p_service_key, p_service_label, p_citizen_type, p_reason, p_symptoms)` -> table
- `get_my_queue_dashboard()` -> table
- `set_queue_current_serving(p_queue_ticket_id)` -> jsonb
- `advance_queue_ticket(p_queue_date, p_service_key)` -> jsonb
- `purge_completed_queue_tickets(p_queue_date, p_service_key, p_grace_seconds)` -> jsonb

### 5.5 Consultation/Prescription
- `get_my_prescribed_medicines(p_limit)` -> table

### 5.6 Triggers/Maintenance
- `set_doctor_schedule_updated_at()`
- `set_announcements_updated_at()`
- `set_feedbacks_updated_at()`
- `set_medicines_updated_at()`
- `set_consultations_updated_at()`
- `set_prescription_headers_updated_at()`
- `set_queue_tickets_updated_at()`
- `set_pending_citizen_signups_updated_at()`
- `handle_new_user()`

## 6. Edge Function Contract Dictionary

### 6.1 `citizen-request-otp` (POST)
Request payload:
- `email` (required)
- `firstname`, `surname` (required in profile validation)
- Optional profile fields: `middle_initial`, `date_of_birth`, `age`, `contact_number`, `sex`, `complete_address`, `emergency_contact_complete_name`, `emergency_contact_contact_number`, `relation`

Behavior:
- Rejects if email already exists in `citizens` or `staff`
- Upserts `pending_citizen_signups`
- Sends Supabase OTP email via `signInWithOtp`

Response:
- `200 { ok: true }` on success
- Error payload `{ error: string }` otherwise

### 6.2 `citizen-verify-otp` (POST)
Request payload:
- `email` (required)
- `otp` (required)

Behavior:
- Validates pending signup record
- Enforces expiry and attempts
- Decrements attempts on mismatch
- Sets `verified_at` on success

Response:
- `200 { ok: true }` on success
- Error payload `{ error: string }` otherwise

### 6.3 `citizen-complete-signup` (POST)
Request payload:
- `email` (required)
- `username` (required)
- `password` (required, min 8 chars)

Behavior:
- Requires verified pending signup
- Creates Supabase Auth user via admin endpoint
- Marks pending signup `consumed_at`
- User metadata carries citizen profile + username

Response:
- `200 { ok: true }` on success
- Error payload `{ error: string }` otherwise

## 7. Web Data Shape Dictionary (Queue Module)

From web queue module usage (`frontend/web/js/appointments.js`), `queue_tickets` is loaded with:
- `id`
- `queue_date`
- `service_key`
- `reason`
- `symptoms`
- `queue_number`
- `ticket_code`
- `service_label`
- `citizen_type`
- `status`
- `created_at`
- `served_at`
- `completed_at`
- nested `citizen: { id, firstname, surname, email }`

UI lanes are status-driven:
- Waiting lane: `status = waiting`
- On-call lane: `status = on_call`
- Serving lane: `status = serving`

## 8. Removed/Deprecated Entities (Historical)

These existed in early migrations but are removed in current model:
- `public.staff_email_verifications` (dropped)
- `public.citizen_otps` (dropped)
- `public.pending_staff` (dropped)
- RPCs dropped with pending-staff cleanup:
  - `check_pending_staff_status`
  - `approve_pending_staff`
  - `reject_pending_staff`

## 9. Notes and Caveats

- Supabase project table introspection was unavailable in this environment due auth, so this dictionary is derived from repository migrations and code contracts.
- Because migrations redefine some functions multiple times, section 5 lists effective function names and purposes. For exact argument signatures, consult the latest migration that redefines each function.
- The queue and appointment workflows rely heavily on normalized lowercase/trimmed comparisons of role/status values in policy and RPC logic.
