# UKonek Data Dictionary (Table Form)

Last updated: 2026-04-05

This is a normalized dictionary view with one row per column.

| Table | Column | Data Type | Nullable | Default | PK | FK | Unique | Domain or Check | Description |
|---|---|---|---|---|---|---|---|---|---|
| public.staff | id | bigint identity | No | generated | Yes |  | No |  | Staff row identifier |
| public.staff | first_name | varchar(100) | Yes |  | No |  | No |  | Staff first name |
| public.staff | middle_name | varchar(100) | Yes |  | No |  | No |  | Staff middle name |
| public.staff | last_name | varchar(100) | Yes |  | No |  | No |  | Staff last name |
| public.staff | birthday | date | Yes |  | No |  | No |  | Staff birth date |
| public.staff | gender | varchar(20) | Yes |  | No |  | No |  | Staff gender |
| public.staff | username | varchar(100) | No |  | No |  | Yes |  | Staff login username |
| public.staff | employee_id | varchar(100) | No |  | No |  | Yes |  | Staff employee identifier |
| public.staff | email | varchar(100) | Yes |  | No |  | Yes |  | Staff email |
| public.staff | role | varchar(100) | No |  | No |  | No | normalized by trim and lowercase comparisons in logic | Staff role |
| public.staff | consent_given | boolean | No | false | No |  | No |  | Consent capture flag |
| public.staff | status | varchar(50) | Yes | Active | No |  | No | normalized by trim and lowercase comparisons in logic | Account status |
| public.staff | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.staff | auth_user_id | uuid | Yes |  | No | auth.users.id logical | Yes |  | Supabase auth linkage |
| public.staff | is_online | boolean | No | false | No |  | No |  | Presence status |
| public.staff | last_seen | timestamptz | Yes |  | No |  | No |  | Last presence heartbeat |
| public.staff | doctor_specialization | text | Yes |  | No |  | No | required by RPC when role is doctor | Doctor specialization |
| public.citizens | id | bigint identity | No | generated | Yes |  | No |  | Citizen row identifier |
| public.citizens | firstname | varchar(100) | No |  | No |  | No |  | Citizen first name |
| public.citizens | surname | varchar(100) | No |  | No |  | No |  | Citizen surname |
| public.citizens | middle_initial | varchar(100) | Yes |  | No |  | No |  | Citizen middle initial |
| public.citizens | date_of_birth | date | Yes |  | No |  | No |  | Birth date |
| public.citizens | age | integer | Yes |  | No |  | No |  | Age snapshot |
| public.citizens | contact_number | varchar(30) | Yes |  | No |  | No |  | Contact number |
| public.citizens | sex | varchar(10) | Yes |  | No |  | No |  | Sex value |
| public.citizens | email | varchar(100) | No |  | No |  | Yes |  | Citizen email |
| public.citizens | complete_address | varchar(255) | Yes |  | No |  | No |  | Address |
| public.citizens | emergency_contact_complete_name | varchar(200) | Yes |  | No |  | No |  | Emergency contact name |
| public.citizens | emergency_contact_contact_number | varchar(30) | Yes |  | No |  | No |  | Emergency contact number |
| public.citizens | relation | varchar(100) | Yes |  | No |  | No |  | Emergency relation |
| public.citizens | username | varchar(100) | Yes |  | No |  | Yes |  | Citizen username |
| public.citizens | role | varchar(50) | No | citizen | No |  | No | typically citizen | App role |
| public.citizens | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.citizens | auth_user_id | uuid | Yes |  | No | auth.users.id logical | Yes |  | Supabase auth linkage |
| public.pending_citizen_signups | id | bigint identity | No | generated | Yes |  | No |  | Pending signup identifier |
| public.pending_citizen_signups | email | text | No |  | No |  | Yes |  | Pending signup email |
| public.pending_citizen_signups | profile | jsonb | No |  | No |  | No |  | Staged citizen profile payload |
| public.pending_citizen_signups | otp_hash | text | No |  | No |  | No |  | Hashed OTP |
| public.pending_citizen_signups | otp_expires_at | timestamptz | No |  | No |  | No |  | OTP expiration |
| public.pending_citizen_signups | attempts_left | integer | No | 5 | No |  | No |  | Remaining verify attempts |
| public.pending_citizen_signups | verified_at | timestamptz | Yes |  | No |  | No |  | OTP verified timestamp |
| public.pending_citizen_signups | consumed_at | timestamptz | Yes |  | No |  | No |  | Account completed timestamp |
| public.pending_citizen_signups | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.pending_citizen_signups | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.doctor_schedules | id | bigint identity | No | generated | Yes |  | No |  | Schedule row identifier |
| public.doctor_schedules | doctor_staff_id | bigint | No |  | No | public.staff.id | No |  | Assigned doctor |
| public.doctor_schedules | doctor_name | varchar(200) | Yes |  | No |  | No |  | Denormalized doctor name |
| public.doctor_schedules | schedule_date | date | No |  | No |  | No |  | Schedule date |
| public.doctor_schedules | start_time | time | No |  | No |  | No |  | Slot start time |
| public.doctor_schedules | end_time | time | No |  | No |  | No | end_time greater than start_time | Slot end time |
| public.doctor_schedules | notes | text | Yes |  | No |  | No |  | Schedule notes |
| public.doctor_schedules | created_by_staff_id | bigint | Yes |  | No | public.staff.id | No |  | Authoring staff |
| public.doctor_schedules | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.doctor_schedules | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.appointments | id | bigint identity | No | generated | Yes |  | No |  | Appointment identifier |
| public.appointments | citizen_id | bigint | No |  | No | public.citizens.id | No |  | Patient reference |
| public.appointments | doctor_staff_id | bigint | No |  | No | public.staff.id | No |  | Doctor reference |
| public.appointments | appointment_date | date | No |  | No |  | No |  | Appointment date |
| public.appointments | appointment_time | time | No |  | No |  | No |  | Appointment time |
| public.appointments | status | varchar(50) | No | pending | No |  | No | pending, confirmed, completed, cancelled, no-show | Appointment lifecycle status |
| public.appointments | patient_notes | text | Yes |  | No |  | No |  | Citizen notes |
| public.appointments | doctor_notes | text | Yes |  | No |  | No |  | Doctor notes |
| public.appointments | cancellation_reason | text | Yes |  | No |  | No |  | Cancellation reason |
| public.appointments | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.appointments | updated_at | timestamptz | No | now() | No |  | No |  | Updated timestamp |
| public.appointments | created_by | uuid | Yes |  | No |  | No |  | Auth actor who created |
| public.appointments | cancelled_by | uuid | Yes |  | No |  | No |  | Auth actor who cancelled |
| public.appointments | cancelled_at | timestamptz | Yes |  | No |  | No |  | Cancellation timestamp |
| public.queue_tickets | id | bigint identity | No | generated | Yes |  | No |  | Queue ticket identifier |
| public.queue_tickets | queue_date | date | No | current_date | No |  | No |  | Queue business date |
| public.queue_tickets | service_key | text | No |  | No |  | No | non-empty | Service key |
| public.queue_tickets | service_label | text | No |  | No |  | No | non-empty | Service display label |
| public.queue_tickets | queue_number | integer | No |  | No |  | No | positive integer | Sequential queue number |
| public.queue_tickets | ticket_code | text | No |  | No |  | Yes |  | Human-friendly ticket code |
| public.queue_tickets | citizen_id | bigint | No |  | No | public.citizens.id | No |  | Citizen owner |
| public.queue_tickets | citizen_type | text | No |  | No |  | No | regular, pwd, pregnant | Priority category |
| public.queue_tickets | reason | text | Yes |  | No |  | No |  | Visit reason |
| public.queue_tickets | symptoms | text | Yes |  | No |  | No |  | Symptom notes |
| public.queue_tickets | status | text | No | waiting | No |  | No | waiting, on_call, serving, completed, cancelled | Queue lane status |
| public.queue_tickets | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.queue_tickets | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.queue_tickets | served_at | timestamptz | Yes |  | No |  | No |  | Serving started timestamp |
| public.queue_tickets | completed_at | timestamptz | Yes |  | No |  | No |  | Completion timestamp |
| public.medicines | id | bigint identity | No | generated | Yes |  | No |  | Medicine row identifier |
| public.medicines | name | text | No |  | No |  | No | non-empty | Medicine name |
| public.medicines | qty | integer | No | 0 | No |  | No | zero or positive | Current stock quantity |
| public.medicines | unit | text | Yes |  | No |  | No |  | Unit of measure |
| public.medicines | created_by_staff_id | bigint | Yes |  | No | public.staff.id | No |  | Creator staff reference |
| public.medicines | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.medicines | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.medicines | archived_at | timestamptz | Yes |  | No |  | No | null means active | Soft delete marker |
| public.consultations | id | bigint identity | No | generated | Yes |  | No |  | Consultation identifier |
| public.consultations | patient_identifier | text | No |  | No |  | No | non-empty | Patient label used in notes |
| public.consultations | patient_citizen_id | bigint | Yes |  | No | public.citizens.id | No |  | Optional citizen reference |
| public.consultations | doctor_staff_id | bigint | No |  | No | public.staff.id | No |  | Doctor reference |
| public.consultations | symptoms | text | Yes |  | No |  | No |  | Symptoms |
| public.consultations | diagnosis | text | No |  | No |  | No | non-empty | Diagnosis |
| public.consultations | notes | text | Yes |  | No |  | No |  | Additional notes |
| public.consultations | consulted_at | timestamptz | No | now() | No |  | No |  | Consultation time |
| public.consultations | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.consultations | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.prescription_headers | id | bigint identity | No | generated | Yes |  | No |  | Prescription header identifier |
| public.prescription_headers | consultation_id | bigint | Yes |  | No | public.consultations.id | No |  | Related consultation |
| public.prescription_headers | patient_identifier | text | No |  | No |  | No | non-empty | Patient label |
| public.prescription_headers | doctor_staff_id | bigint | No |  | No | public.staff.id | No |  | Doctor reference |
| public.prescription_headers | issued_at | timestamptz | No | now() | No |  | No |  | Issued time |
| public.prescription_headers | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.prescription_headers | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.prescription_items | id | bigint identity | No | generated | Yes |  | No |  | Prescription item identifier |
| public.prescription_items | prescription_id | bigint | No |  | No | public.prescription_headers.id | No |  | Header reference |
| public.prescription_items | medicine_name | text | No |  | No |  | No | non-empty | Prescribed medicine |
| public.prescription_items | quantity | integer | No |  | No |  | No | greater than zero | Prescribed quantity |
| public.prescription_items | unit | text | Yes |  | No |  | No |  | Unit of measure |
| public.prescription_items | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.announcements | id | bigint identity | No | generated | Yes |  | No |  | Announcement identifier |
| public.announcements | title | text | No |  | No |  | No | non-empty trimmed | Announcement title |
| public.announcements | content | text | No |  | No |  | No | non-empty trimmed | Announcement body |
| public.announcements | created_by_staff_id | bigint | Yes |  | No | public.staff.id | No |  | Creator staff reference |
| public.announcements | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.announcements | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |
| public.announcements | visibility | varchar(20) | No | all | No |  | No | all, staff, citizen | Audience scope |
| public.feedbacks | id | bigint identity | No | generated | Yes |  | No |  | Feedback identifier |
| public.feedbacks | citizen_id | bigint | Yes |  | No | public.citizens.id | No |  | Optional citizen linkage |
| public.feedbacks | from_email | text | No |  | No |  | No |  | Sender email |
| public.feedbacks | subject | text | No |  | No |  | No | non-empty trimmed | Feedback subject |
| public.feedbacks | message | text | No |  | No |  | No | non-empty trimmed | Feedback message |
| public.feedbacks | rating | smallint | Yes |  | No |  | No | null or 1 to 5 | Optional rating |
| public.feedbacks | created_at | timestamptz | No | now() | No |  | No |  | Created timestamp |
| public.feedbacks | updated_at | timestamptz | No | now() | No |  | No | trigger maintained | Updated timestamp |

## Usage Notes

- This file is optimized for copy and paste into spreadsheets.
- It represents current active schema only.
- For policy and RPC details, see ../../DATA_DICTIONARY.md and docs/data-dictionary/README.md.
