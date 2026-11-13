# U-Konek System Defense & Live Demonstration Guide

**System Name:** **U-Konek** (Web Clinical Workstation & Pharmacy/Admin Consoles + TV Queue Display) / **U-Konek+** (Flutter Citizen Mobile App)  
**Target Facility:** AFM Roquero Medical Clinic (Outpatient Department)  
**Target Demo Duration:** **14 minutes 00 seconds** (designed for a 12–15 minute demonstration slot, followed by Panel Q&A)

---

## Multi-Platform Side-by-Side Presentation Setup

Although the web app has **3 role-oriented web console pages** (`dashboard.html`, `dashboard-pharmacist.html`, `dashboard-admin.html`) plus a public **TV Queue Display** (`tv-view.html`), `dashboard.html` enforces distinct permissions for **Doctor** and **Nurse**. Because [`web/src/js/lib/supabaseClient.js`](web/src/js/lib/supabaseClient.js) isolates Supabase Auth sessions per browser tab using `sessionStorage['ukonek.auth.tab_id']` (storage key `sb-${projectRef}-auth-tab-${tabId}`), you can run **all web roles simultaneously in side-by-side windows/tabs in the same browser** alongside your mirrored phone:

| Pane / Display | Platform / Entrypoint | Active Role | Primary Purpose in Demo |
| :--- | :--- | :--- | :--- |
| **Pane 1 (Phone Mirror)** | Mobile (`uKonekMainShellPage`) | **Citizen (Patient)** | Queue booking, live status, Patient Digital ID QR, E-Rx, Medicine Scheduler, Records, Feedback |
| **Pane 2 (Web Window A)** | Web (`dashboard.html`) | **Nurse** | Queue triage (`On Call` -> `Vitals` -> `Serve`), vitals risk scoring, read-only pharmacy, promo posters |
| **Pane 3 (Web Window B)** | Web (`dashboard.html`) | **Doctor** | Consultation EHR (`3-tab wizard`), lab orders, E-Prescription + allergy block, review moderation |
| **Pane 4 (Web Window C)** | Web (`dashboard-pharmacist.html` -> Tab 1)<br>Web (`dashboard-admin.html` -> Tab 2) | **Pharmacist** & **Admin** | Rx/QR lookup, atomic Rx & OTC dispensing, inventory CRUD; Admin KPIs, CSV exports, Census, User/Schedule/Backup admin |
| **Pane 5 / Toggle Tab** | Web (`tv-view.html`, unauthenticated) | **Public TV Display** | Unauthenticated waiting-room display (`NOW SERVING`, `On Call`, `Waiting`) + Web Audio chime |

> [!WARNING]
> **Critical Deployment Route Note:** Root [`vercel.json`](vercel.json) rewrites `/`, `/login`, `/dashboard`, `/dashboard-pharmacist`, and `/tv-view`, **but omits `/dashboard-admin`**. Both [`web/vercel.json`](web/vercel.json) and [`web/public/vercel.json`](web/public/vercel.json) include `/dashboard-admin`. Before going on stage, verify your deployment root or test `./dashboard-admin.html` / `/web/public/dashboard-admin.html` directly.

---

## 1. Codebase Audit & Feature Inventory

### 1.1 User Roles, Authentication, Guards & Database Access (RLS)

| Role | Entrypoint / App | Frontend Auth & Role Guards | Allowed Actions | Restricted / Blocked Actions |
| :--- | :--- | :--- | :--- | :--- |
| **Admin** | Web (`dashboard-admin.html`) | `ensureAdminSession()` (`dashboard-admin.js:44-109`): `auth.getUser()` + active `staff` row where `role === 'admin'`. | View executive analytics & 7-day trends; generate/print Clinic Census & 5 CSV reports; create/edit/disable/reset-password staff accounts; CRUD doctor schedules & announcements; JSON backup/restore; change own password. | No clinical triage/consultation/pharmacy dispense forms on admin console; audit CSV functions check `sessionStorage['ukonek_role']`. |
| **Doctor** | Web (`dashboard.html`) | `ensureAuthenticatedSession()` (`dashboard.js:101-164`) + `navigationController.js` + `canConsultPatients()` (`queueController.js:25`). | View dashboard KPIs & Chart.js charts; manage own availability (`Available`/`Break`/`Off Duty`); advance/delete queue tickets; assess/view vitals; conduct 3-tab consultations; order lab tests; issue prescriptions (`prescription_headers`/`items`); upload Promo Posters; view Citizens & full EHR modal; view/delete patient feedback; update own profile & password. | Blocked by RLS from adding new medicines (`20260913160000` restricts `medicines` INSERT to `pharmacist` only), dispensing/returning pharmacy stock, or managing staff/schedules. |
| **Nurse** | Web (`dashboard.html`) | `dashboard.js` + `navigationController.js` + `queueController.js` (`!canConsultPatients()` hides Doctor controls). | View dashboard KPIs & charts; toggle own availability; call patients (`On Call`), record vitals/BMI (`upsert_vital_assessment` & Walk-In Triage + QR scanner), move to `Now Serving`; view read-only consultation history, read-only pharmacy stock & Citizen EHR modal; publish/delete Promo Posters; view feedback. | Blocked in UI & RLS from starting/saving consultations (`consultations` INSERT = `doctor` only), creating prescriptions (`prescription_headers` INSERT = `doctor` only), deleting feedback in UI (`canUserDeleteReviews()` = `doctor`/`admin`), adding medicines, or creating/editing staff (`20260910000000`). |
| **Pharmacist** | Web (`dashboard-pharmacist.html`) | `guardAccess()` (`ukonek_role === 'pharmacist'`, `dashboard-pharmacist.js:931-939`) + `ensurePharmacistSession()` (`lines 286-314`). | Look up Rx by `RX-` code or QR scan (`lookup_prescription_by_code`); partial/full Rx dispense (`dispense_prescription_items`); process Rx returns/restock (`return_dispensed_prescription_item`); OTC walk-in & citizen-linked dispense (`dispense_otc_medicines`); add/edit/soft-delete (`archived_at`) medicines; CSV bulk medicine import (`csv-import.js`). | Cannot access `dashboard.html` clinical EHR, `dashboard-admin.html`, doctor schedules, or consultations/vitals (RLS & route redirects). |
| **Citizen (Patient)** | Mobile (`U-Konek+` Flutter) | `RootHandler` (`main.dart`) restores Supabase Auth session + `fetchMyCitizenProfile()`; optional local 4-digit PIN lock (`PinSecurityWrapper`). | Sign in / forgot password (`ukonekmobile://reset-password`); check live doctors & clinic promo banners; show Patient Digital Pass QR; join queue (`create_queue_ticket`) & cancel while `waiting`; receive real-time queue/Rx/dispense alerts & local notifications; view E-Prescriptions, Dispense Logs & Medical Timeline; mark/reschedule daily doses (`medicine_intake_logs`); submit feedback (`feedbacks`); edit personal/contact/emergency profile fields. | Cannot access web portals or other citizens' records (`auth_user_id = auth.uid()` RLS on `citizens`, `queue_tickets`, `consultations`, `prescription_headers`, `vital_signs`, `medicine_intake_logs`). |
| **Public / Unauthenticated** | Web (`tv-view.html`) | None (`persistSession: false` in `tv-view.js`). | View real-time `NOW SERVING`, `On Call`, `Waiting` lists (`get_tv_queue_display` RPC + `queue_tickets` Realtime) and hear Web Audio / MP3 chime (`Audio Chime On`). | No patient PII beyond queue number/service/status; cannot mutate any record (Note minor RLS/grant caveats in Section 1.7). |

### 1.2 Pages, Routes & Screens Inventory

#### Web Application (`web/public/` & `web/src/`)
1. **`index.html` (`/` or `/login`)**: Unified staff sign-in supporting email, username, or employee ID (`resolve_staff_login_email` RPC), 15s login timeout, and 3-attempt 5-minute client lockout (`ukonek_login_lock_state`, bypassed on `localhost`/`127.0.0.1`).
2. **`dashboard.html` (`/dashboard`) — Doctor & Nurse Workstation**:
   - **Sidebar Sections (9)**: `Dashboard` (`#dashboard-section`: 4 KPIs, 3 Chart.js charts, 6 Launchpad cards), `Availability Schedule` (`#schedule-section`), `Live Patient Queue` (`#queue-section`: 3 Kanban lanes `Waiting`/`On Call`/`Now Serving` + drag-and-drop), `Vitals Triage` (`#vitals-section`: QR scanner `#start-scanner-btn` + `New Walk-In Intake` + KPIs + alerts filter), `Consultations` (`#consultation-section`: Doctor `"New Consultation"` + searchable history), `Pharmacy & Stock` (`#medicine-section`: read-only inventory + low-stock/expiring telemetry), `Personnel & Citizens` (`#users-section`: Staff read-only directory + Citizens table opening 4-tab `#citizen-health-modal` EHR), `Reports & Analytics` (`#reports-section`: `Promo Posters & Announcements`, `Patient Reviews & Feedback`, `Clinical Statistics`), `Profile` (`#profile-section`: profile details + password update).
   - **Active Modals**: `#vital-assessment-modal`, `#vitals-form-container`, `#consultation-modal` (3-step wizard: `1. History & Subjective`, `2. Physical Exam`, `3. Assessment & Plan`), `#prescription-modal`, `#queue-ticket-detail-modal`, `#citizen-health-modal` (`Consultations`, `Vitals`, `Prescriptions`, `Lab Orders`), `#promo-poster-modal`, `#feedback-detail-modal`, `#data-detail-modal`, `#account-modal`, `#logout-confirm-modal`, `#dialog-modal`.
3. **`dashboard-pharmacist.html` (`/dashboard-pharmacist`) — Pharmacist Console**:
   - **KPIs**: Total Medicines, In Stock, Low Stock (`<= 10` here vs `<= 5` in `dashboard.html`), Expiring Soon + Expired.
   - **Panels**: `Dispense Prescription` (`RX-` lookup, `Scan QR`, `OTC Dispense` modal, partial/full dispense qty confirmation, `Return` modal), `Add New Medicine`, `Medicine Inventory` (search, sort, filter tabs `All`/`OTC Only`/`Low Stock`/`Expired`/`Expiring Soon`, CSV Import modal `#csv-import-modal`, Edit/Soft-Delete modals).
4. **`dashboard-admin.html` (`/dashboard-admin`) — Administrator Command Console**:
   - **7 Top Navigation Tabs**: `Dashboard & Analytics`, `System Reports & Exports` (5 CSV downloads + `Print Official Clinic Census`), `Users Management` (Create/Enable-Disable/Reset-Password Staff), `Doctor Schedules & Roster`, `Announcements & Broadcasts`, `Backup & Restore` (JSON export/import across 12 tables), `Account Security` (Admin password change).
5. **`tv-view.html` (`/tv-view`) — Waiting-Room TV Queue Display**:
   - Real-time `NOW SERVING` hero number, `On Call` and `Waiting` lanes, `Audio Chime On` toggle, scrolling clinic advisory ticker, double-click fullscreen.

#### Mobile Application (`mobile/lib/` — Flutter)
- **Pre-Auth / Auth Flow**: `uKonekMenuPage` (`CREATE ACCOUNT` / `SIGN IN`) -> `uKonekLoginPage` (Email/Password, Forgot Password dialog, 3-attempt local lock) / Multi-step Registration (`uKonekRegisterWrapper` -> `RegisterStep2Page` -> `OtpPage` -> `CredentialsPage`) -> `uKonekChangePasswordPage` (deep link `ukonekmobile://reset-password`).
- **Authenticated Persistent Shell (`uKonekMainShellPage`)** with 4 Tabs + Center QR FAB + Pop-up Modals:
  1. **Tab 0 — `uKonekDashboardPage` (Home)**: Greeting, Notification Bell -> `uKonekNotificationPage`, Live Queue Status Card, `DOCTORS ON DUTY` real-time row, Active Prescriptions preview, 6 Quick Actions (`MY PATIENT ID`, `JOIN QUEUE`, `E-PRESCRIPTION`, `RECORDS`, `SCHEDULER`, `FEEDBACK`), Clinic Promo Carousel (`announcements`).
  2. **Tab 1 — `uKonekMedicineSchedulerPage` (Medicine Scheduler)**: Date strip, Daily Adherence Progress card, Scheduled Dose Cards (`"I've taken it"` / `"Take all X meds"` / checkmark icon / `"Mark all as taken"` / PRN `"Take dose"` + Undo), Reschedule Intake & Time Pickers, `Consultation History` tab, local reminder scheduling (`flutter_local_notifications`).
  3. **Center QR Button**: `Patient Digital Pass` bottom sheet (scannable Citizen ID QR for nurse triage / reception check-in).
  4. **Tab 2 — `uKonekJoinQueuePage` (Queue Tracker)**: Daily slot availability banner (`get_queue_limiter_status`), Service Picker (17 services), Priority Category (`Regular` / `PWD` / `Pregnant`), Reason/Symptoms -> `GET QUEUE NUMBER`; Active Ticket Card (`#00X`, QR ticket code, 3-step `QueueStepTracker` [`Ticket -> Vitals -> Consult`], `LEAVE QUEUE`).
  5. **Tab 3 — `uKonekProfilePage` (Profile)**: Digital ID preview, editable `Personal Information`, `Contact & Address`, `Emergency Contact`, `Security PIN` (`PinSetupSheet` + `Require PIN on App Open` toggle), `LOG OUT ACCOUNT`.
- **Pushed Feature Screens**: `PrescriptionPage` (E-Prescription QR cards, status filters `All`/`Pending`/`Partial`/`Dispensed`, `Dispense History Log` incl. OTC), `uKonekHealthRecordsPage` (`Consultations` & `Vitals Timeline`), `uKonekFeedbackPage` (1–5 star rating + comment), `uKonekNotificationPage`.

### 1.3 Active Database Schema (20 `public` Tables, 0 Views) & Storage

- **People & Auth**: `staff`, `citizens`, `pending_citizen_signups`, `staff_login_logs`
- **Scheduling & Engagement**: `doctor_schedules`, `announcements`, `feedbacks`, `system_config` (`daily_queue_ticket_limit`, `queue_limiter_enabled`)
- **Queue & Triage**: `queue_tickets`, `vital_signs`
- **Clinical EHR & Labs**: `consultations`, `lab_orders`
- **Prescriptions, Pharmacy & Adherence**: `medicines`, `prescription_headers`, `prescription_items`, `prescription_item_dispenses`, `otc_dispenses`, `otc_dispense_items`, `dispense_returns`, `medicine_intake_logs`
- **Storage Bucket**: `promo-banners` (`public: true`, max 10 MiB, `jpeg/jpg/png/webp/gif`)
- **Main Business Transactions**:
  1. **Outpatient Queue Lifecycle**: Citizen creates ticket (`waiting`) -> Nurse moves `on_call` -> Nurse records `vital_signs` -> Nurse moves `serving` -> Doctor saves `consultations` & auto-completes ticket (`completed`).
  2. **E-Prescription & Fulfillment**: Doctor inserts `prescription_headers` (`RX-000XXX` generated by trigger) + `prescription_items` -> Pharmacist runs `dispense_prescription_items` RPC (atomically decrements `medicines.qty`, records `prescription_item_dispenses`, sets status `partial`/`dispensed`).
  3. **OTC Walk-In & Return/Restock**: Pharmacist calls `dispense_otc_medicines` (optionally linked to `CIT-<id>`) or `return_dispensed_prescription_item` / `return_otc_dispensed_item` (writes `dispense_returns` & restores stock).
  4. **Patient Adherence Loop**: Dispensed Rx & citizen-linked OTC items appear in `get_my_medicine_schedule`; patient logs doses in `medicine_intake_logs`.
  5. **Clinic Administration & Governance**: Admin staff CRUD (`create_staff_account_admin`, `toggle_staff_status_admin`, `reset_staff_password_admin`), duty schedules, broadcasts, CSV exports, JSON backup/restore.

### 1.4 Backend Logic (RPCs, Triggers, Cron Jobs, Edge Functions)

- **Key Active `SECURITY DEFINER` RPCs**:
  - *Auth/Staff*: `resolve_staff_login_email`, `get_staff_role`, `get_staff_profile`, `create_staff_account_admin`, `update_staff_account_admin`, `toggle_staff_status_admin`, `delete_staff_member`, `reset_staff_password_admin`, `update_my_staff_profile`, `set_staff_presence`, `set_staff_availability`, `set_staff_unavailable_after_hours`, `list_staff_accounts`, `list_all_staff_admin`, `log_staff_action`.
  - *Citizen & Queue*: `complete_my_citizen_profile`, `list_available_doctor_schedules`, `list_available_queue_services`, `create_queue_ticket` (uses `pg_advisory_xact_lock` + multi-word service abbreviations), `get_my_queue_dashboard`, `cancel_my_queue_ticket`, `list_queue_tickets_for_staff`, `get_tv_queue_display`, `get_queue_limiter_status`.
  - *Clinical & Pharmacy*: `upsert_vital_assessment`, `get_vitals_for_ticket`, `lookup_prescription_by_code`, `dispense_prescription_items`, `return_dispensed_prescription_item`, `dispense_otc_medicines`, `return_otc_dispensed_item`, `pharmacist_get_medicines`, `pharmacist_upsert_medicine`, `get_my_consultations`, `get_my_prescribed_medicines`, `get_my_medicine_schedule`, `get_my_prescription_dispense_logs`.
  - *Reports & Ops*: `get_dashboard_bootstrap_data`, `get_clinical_operations_metrics`, `get_system_reports_summary`, `delete_feedback`, `delete_feedback_admin`, `refresh_operational_test_data`.
- **Triggers (14 active)**: `on_auth_user_created` (`handle_new_user` no-op), 8 `set_updated_at` triggers, `trg_generate_prescription_code` (`RX-` padding), `trg_sync_prescription_item_quantities`, 3 `sanitize_*_input` triggers (`citizens`, `staff`, `queue_tickets`), `trg_normalize_staff_columns`, `trg_normalize_queue_ticket_columns`. *(Note: `trigger_cleanup_old_queue_tickets` was dropped in `20261011193000` to speed up ticket inserts.)*
- **Scheduled Jobs (`pg_cron`, 3 active)**:
  1. `delete-old-pending-queue-tickets`: Daily `0 16 * * *` (00:00 Manila) -> batched 500-row deletion of stale tickets.
  2. `staff_unavailable_5pm_manila`: Daily `0 9 * * *` (17:00 Manila) -> calls `set_staff_unavailable_after_hours()`.
  3. `cleanup-cron-logs`: Weekly `0 3 * * 0` -> purges `cron.job_run_details` > 7 days.
- **Supabase Edge Functions (`supabase/functions/`, 3 Deno functions — UNUSED BY LIVE CLIENTS)**: `citizen-request-otp`, `citizen-verify-otp`, `citizen-complete-signup`. *(Mobile uses native Supabase Auth `signInWithOtp` / `verifyOTP` + `complete_my_citizen_profile` RPC instead; Web makes 0 Edge Function calls.)*

### 1.5 Integrations

- **Authentication**: Supabase Auth (email/password for staff & citizen; `signInWithOtp` for citizen onboarding; deep link `ukonekmobile://reset-password` for password reset).
- **Real-Time Sync**: Postgres CDC via Supabase Realtime on `queue_tickets` (`tv-queue-updates`, `queue-board-updates`, mobile dashboard & queue tracker), `prescription_headers` (mobile Rx & Dispense pop-ups), and `staff` (`staff-availability` on web schedule & mobile Doctors On Duty).
- **Storage**: Supabase Storage bucket `promo-banners` (client-side canvas JPEG compression before upload).
- **Notifications & Audio**: `flutter_local_notifications` + `timezone` (queue alerts `888/889/890/891`, Rx `777`, medicine schedule `1000-1099`, follow-up `2000-2199`); TV View external MP3 + Web Audio API chime synthesizer (`audio-chime.js`).
- **QR & Scanning**: `qr_flutter` (Mobile Digital ID, Queue Ticket, E-Prescription QR) + `html5-qrcode` (Web Nurse Triage & Pharmacist Rx lookup).
- **Reporting & Visualization**: Chart.js (Dashboard & Admin charts), CSV export (`reports.js` with `sanitizeCsvCell` formula-injection guard), CSV bulk medicine import (`csv-import.js`), Printable Census sheet (`window.print()`), Full JSON Backup/Restore.

### 1.6 Feature Classification

| Classification | Feature | Platform / Roles |
| :--- | :--- | :--- |
| **CORE** | Staff Multi-Role Auth & Per-Tab Isolation + Citizen Mobile Auth | Web (All Staff) + Mobile (Citizen) |
| **CORE** | Mobile Queue Ticket Booking & Real-Time Status Tracker (`Ticket -> Vitals -> Consult`) | Mobile (Citizen) |
| **CORE** | Live Kanban Queue Board (`Waiting -> On Call -> Now Serving`) & TV Display Sync | Web (Nurse, Doctor, TV Display) |
| **CORE** | Clinical Vitals Triage Assessment + Auto BMI & Red/Amber Risk Alerting | Web (Nurse, Doctor) |
| **CORE** | 3-Step Physician Consultation EHR + Diagnostic Lab Orders + Consultation History | Web (Doctor write / Nurse read) + Mobile (Citizen read) |
| **CORE** | E-Prescription Issuance + Real-Time Drug Allergy Safety Block | Web (Doctor) + Mobile (Citizen alert & QR pass) |
| **CORE** | Pharmacy Rx Lookup & Atomic Partial/Full Dispensing (Stock & Expiry Guarded) | Web (Pharmacist) + Mobile (Real-time Dispense Alert & Logs) |
| **CORE** | Mobile Medicine Adherence Scheduler & Dose Intake Logging | Mobile (Citizen) |
| **CORE** | Role-Based Access Enforcement (UI Gating + Postgres RLS + Console Isolation) | Web + Mobile + DB |
| **CORE** | Administrative Reporting, Analytics Charts & 5 Official CSV Exports | Web (Admin) + Web (Clinical telemetry) |
| **SUPPORTING** | Citizen Directory & 4-Tab Health Records Modal (`Consultations`, `Vitals`, `Rx`, `Lab Orders`) | Web (Doctor, Nurse) |
| **SUPPORTING** | Staff On-Duty Availability Toggling & Physician Duty Roster (`doctor_schedules`) | Web (Admin CRUD / Nurse & Doctor self-toggle) + Mobile (`DOCTORS ON DUTY`) |
| **SUPPORTING** | Pharmacy Inventory CRUD, Classification (`rx`/`otc`), Soft Delete (`archived_at`) & OTC Walk-In/Citizen-Linked Dispensing + Rx Return/Restock | Web (Pharmacist) + Mobile (Citizen OTC schedule sync) |
| **SUPPORTING** | Admin Staff Personnel Management (Create, Enable/Disable, Password Reset) | Web (Admin) |
| **SUPPORTING** | Clinic Promo Posters (`promo-banners` Storage) & Citizen Notifications/Carousel | Web (Doctor, Nurse, Admin) + Mobile |
| **SUPPORTING** | Patient Feedback Submission & Clinic Review Hub (Doctor/Admin moderation) | Mobile (Citizen) + Web (Doctor, Nurse, Admin) |
| **SUPPORTING** | Database JSON Backup & Restore + Printable Official Clinic Census Modal | Web (Admin) |
| **OPTIONAL** | Patient Digital ID QR Sheet & Web Camera QR Scanner (`Html5Qrcode`) | Mobile + Web (Nurse, Pharmacist) |
| **OPTIONAL** | Mobile 4-Digit Security PIN App Lock (`PinSecurityWrapper`) | Mobile (Citizen) |
| **OPTIONAL** | Bulk Medicine CSV Import (`csv-import.js`) & `pg_cron` Overnight Hygiene | Web (Pharmacist) + DB |

### 1.7 Incomplete, Risky, Stubbed, or Security-Gap Features (Keep Out of Live Happy Path!)

1. **Mobile Change Password in `ProfilePage` is a UI Stub (`profile_page.dart:887-942`)**: Validates `length >= 6` and displays `'Password updated successfully!'` **without calling Supabase** (real password change works only via email Forgot Password deep link).
2. **Mobile `"DOWNLOAD ID CARD"` Button is a Stub (`profile_page.dart:238-246`)**: Shows a fake SnackBar without saving to device storage.
3. **Mobile `Name Extension` Edit Not Persisted (`profile_page.dart:496` vs `138-154`)**: Missing in `_mapLabelToDbKey`; reverts on reload.
4. **Live Citizen Email OTP Registration**: Uses `signInWithOtp` directly (`auth_service.dart`), while `supabase/functions/citizen-*` Edge Functions are **dead/broken** (Edge function generates an unused OTP in `pending_citizen_signups` while calling `signInWithOtp`). Live demo signup also risks SMTP delays, 55s rate limits, and orphaned `auth.users` rows if exited mid-flow.
5. **Unreachable Mobile Screens & Copy Bug**: `OnboardingPage` and `uKonekDoctorSchedulesPage` are never navigated to; `feedback_page.dart:68` still says *"improve our dental services"*; `"Open Settings"` banner in `medicine_scheduler_page.dart:1161` only shows a SnackBar; offline cold-start signs the citizen out (`main.dart:301-334`); duplicate `queue_tickets` Realtime channels in `MainShellPage` can double-fire notifications `888-891`.
6. **Orphaned HTML/JS Targets in `dashboard.html`**: `consultationController.js` targets missing `#triaged-waiting-tbody` and `#lab-orders-tbody`; `systemReportController.js` targets missing `#system-census-modal`/`#system-trend-chart` (moved to `dashboard-admin.html`); `dashboard.html` retains unused stubs (`#non-admin-section`, `#security-section`, `#notification-list`, `#registration-pane`, 8 unused modals). Also there is **no standalone Web UI to update `lab_orders.status` from `Pending` to `Completed`** after creation.
7. **Admin Print Census Layout Clipping (`dashboard-admin.html` / `admin.css`)**: `dashboard-admin.html` doesn't include `print.css` and targets `#modal-census-sheet` (while `style.css` print rules only style `#system-census-modal`), so printing directly clips inside `.admin-modal-body`'s scroll box. **Show the modal on screen, do not trigger physical Print.**
8. **Admin Backup/Restore & Employee ID Caveats (`dashboard-admin.js`)**: `#cs-employee-id` input is read but dropped in `create_staff_account_admin`; Admin Logout skips `log_staff_action('logout')`; Backup caps tables at 500–2000 rows; Restore swallows `{ error }` silently and cannot recreate `auth.users`.
9. **Web Triage QR Walk-in Race & Filter Risk (`triageController.js`)**: Walk-in queue numbers compute `MAX + 1` client-side (unlike Mobile/RPC `pg_advisory_xact_lock`), and QR lookup skips `sanitizeSearchTerm`.
10. **DB Regressions & RLS Gaps (Honest Awareness for Q&A)**:
    - `create_queue_ticket` (`20260517020000`) dropped DB-level `daily_queue_ticket_limit` (`system_config` = `20`) & 1-ticket/day enforcement (limit is currently UI-enforced via `QueueLimiterStatus` in `queue_join_form.dart`).
    - Legacy permissive RLS policies were not dropped on `vital_signs` (UPDATE) and `system_config` (SELECT/UPDATE by authenticated users), `feedbacks` DELETE policy includes `is_active_staff()`, and `get_dashboard_bootstrap_data()` is callable by `anon`.
    - Broken unused DB RPCs exist (`restock_prescription_item` references missing `medicine_return_logs`; `approve_pending_staff` references dropped `pending_staff`; overloaded signatures exist on `update_staff_account_admin` and `dispense_otc_medicines`). Pharmacist returns in UI safely use `return_dispensed_prescription_item` instead.

---

## 2. Demo Coverage Matrix (`Feature x Role x Platform`)

| Feature | Priority | Citizen (Mobile) | Nurse (Web) | Doctor (Web) | Pharmacist (Web) | Admin (Web) | TV Display (Web) | Covered in Demo Step |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Auth & Tab-Isolated RBAC Routing** | CORE | Signed In | `dashboard.html` | `dashboard.html` | `dashboard-pharmacist.html` | `dashboard-admin.html` | Public | **Step 2** |
| **Queue Ticket Booking (`create_queue_ticket`)** | CORE | Request `#00X` | Views `Waiting` | Views `Waiting` | — | — | Live Update | **Step 3.1** |
| **Live Queue Advancement & TV Sync** | CORE | Live Tracker & Push | `On Call` -> `Serve` | Sees `Now Serving` | — | — | Chime + `NOW SERVING` | **Step 3.2** |
| **Nurse Clinical Vitals & BMI / Risk Scoring** | CORE | Tracker `Vitals` Done | Assess & Save Vitals | Sees Triage Summary | — | — | — | **Step 3.2** |
| **Physician 3-Tab Consultation EHR & Lab Order** | CORE | `Consultation Completed!` | Read-only History | Complete 3-Tab EHR | — | — | — | **Step 3.3** |
| **E-Prescription & Allergy Safety Safeguard** | CORE | Rx Alert + QR Card | Read-only | Issues Rx + Allergy Block | Looks up `RX-` | — | — | **Step 3.3 & Step 6** |
| **Atomic Pharmacy Dispense & Inventory Sync** | CORE | Dispensed Modal + Logs | Stock Decrements | Stock Decrements | Dispenses `RX-` | KPI Updates | — | **Step 3.4** |
| **Medicine Scheduler & Dose Intake Logging** | CORE | Mark `"I've taken it"` | — | — | — | — | — | **Step 3.5** |
| **Clinical Safety & Role Guard Validation** | CORE | — | Blocked from Consult | Allergy Block Tested | Bad Rx / Over-Stock Block | — | — | **Step 6** |
| **Reports, Analytics Charts & CSV Exports** | CORE | — | Clinic Stats Charts | Clinic Stats Charts | — | KPIs + Charts + 5 CSVs + Census | — | **Step 5** |
| **Staff Availability & Doctors On Duty Sync** | SUPPORTING | Sees Live Dot | Toggles Status | Toggles Status | — | Manages Duty Roster | — | **Step 4.1** |
| **Promo Posters (`promo-banners` Storage)** | SUPPORTING | Sees Carousel & Notif | Uploads Poster | Can Upload/Delete | — | Can Broadcast | — | **Step 4.1** |
| **Patient Feedback & Clinic Review Hub** | SUPPORTING | Submits Rating | View-Only Reviews | View + Delete Reviews | — | Moderate Reviews | — | **Step 4.2** |
| **Citizen Directory & 4-Tab EHR Modal** | SUPPORTING | Views Own Timeline | Views All 4 EHR Tabs | Views All 4 EHR Tabs | — | — | — | **Step 4.2** |
| **Walk-In / Citizen-Linked OTC Dispense & CRUD** | SUPPORTING | Syncs to Scheduler | — | — | OTC Dispense + Inv | — | — | **Step 4.3** |
| **Admin Staff Management & JSON Backup** | SUPPORTING | — | — | — | — | Staff Directory + JSON Export | — | **Step 5** |
| **Patient Digital Pass QR / Web Scanner** | OPTIONAL | Opens Digital ID QR | Optional Scan Note | — | Optional Scan Note | — | — | **Step 4.2 (Mentioned)** |
| **Citizen Live Email OTP Signup / Forgot Pwd** | CORE (Onboarding) | *Pre-seeded* | — | — | — | — | — | **Excluded (Risky SMTP)** |
| **Mobile Stubs (`Download ID`, `Profile ChgPwd`)** | N/A (Broken) | *Avoid* | — | — | — | — | — | **Excluded (Stub)** |
| **Admin Physical Print & Live JSON Restore** | OPTIONAL (Risky) | — | — | — | — | *Preview Census / Export JSON only* | — | **Excluded (Layout/Restore Risk)** |

### Coverage Gaps & Stage Exclusions
- **100% of active CORE operational features appear live** in Steps 2–6.
- **Deliberate Stage Exclusions:**
  1. **Live Email OTP Signup (`OtpPage`)**: Avoided on stage due to email delivery latency, 55s resend rate-limits, and `pending_citizen_signups` Edge Function mismatch; instead, show an already verified citizen account and explain how `signInWithOtp` -> `verifyOTP` -> `complete_my_citizen_profile` onboards users.
  2. **Camera QR Scanning (`Html5Qrcode`)**: Kept as an optional fallback-safe feature; projector glare/webcam focus often stalls demos, so we type `RX-000XXX` directly on Pharmacy and show the QR visual side by side.
  3. **Stubbed Buttons (`ProfilePage` Change Password / Download ID Card) & Missing Lab Result Entry UI**: Excluded from clicks and disclosed cleanly under Limitations in Step 7.

---

## 3. End-to-End Live Demo Flow (`14:00` Storyline)

**Story Premise:** Citizen **Maria Santos** (`demo.citizen`) checks clinic capacity from home on **U-Konek+** mobile, joins the outpatient queue with a documented **Amoxicillin allergy**, gets triaged by the **Nurse**, consulted & prescribed by the **Doctor**, dispensed medication by the **Pharmacist**, tracks adherence on her phone, leaves clinic feedback, and appears in the **Administrator's** live analytics and exports.

---

### Step 1: Opening — Problem, Solution & Architecture (`0:00 – 0:45`, 45 sec)

- **Role + Platform / Pane:** Presenter Overview (All 4 panes visible side-by-side: Mobile Mirror + Nurse + Doctor + Pharmacist/Admin + TV Display).
- **Exact Click Path:** Keep screens steady on the pre-arranged grid (`Pane 1`: Mobile Home, `Pane 2`: Nurse `Live Patient Queue`, `Pane 3`: Doctor `Dashboard`, `Pane 4`: Pharmacist `Dispense Prescription`, `TV Tab`: `tv-view.html` visible/ready). No clicking yet.
- **Talking Points:**
  > "Good afternoon, panelists. Outpatient clinics like AFM Roquero Medical Clinic struggle with manual paper queueing, disconnected nurse-to-doctor handoffs, paper prescriptions prone to allergy errors, and patients forgetting medication schedules once they leave. Today we present **U-Konek**, a multi-platform clinical ecosystem connecting a Flutter patient mobile app (**U-Konek+**), a public waiting-room TV display, and role-based web workstations for Nurses, Doctors, Pharmacists, and Administrators — all synchronized in real time via Supabase PostgreSQL, Row-Level Security, and Postgres Change Data Capture."
- **Expected Result on Screen:** Clean side-by-side layout showing active clinic workspaces ready to process a live patient encounter.
- **Objective / Requirement Proved:** Demonstrates cohesive problem-solution fit, multi-platform system architecture, and deployment readiness.
- **Fallback If It Fails:** If screen mirroring hasn't rendered yet, introduce the architecture slide/diagram while scrcpy reconnects in the background.

---

### Step 2: Authentication & Role-Based Access Isolation (`0:45 – 2:15`, 1 min 30 sec)

- **Role + Platform / Pane:** Pane 2 (`Nurse` on `dashboard.html`), Pane 3 (`Doctor` on `dashboard.html`), Pane 4 (`Pharmacist` on `dashboard-pharmacist.html` & `Admin` on `dashboard-admin.html`), Pane 1 (`Mobile Citizen`).
- **Exact Click Path:**
  1. Briefly display `index.html` (or open a fresh incognito/login tab if demonstrating live sign-in — otherwise show the pre-logged role headers) and sign in as **Nurse** (or point to Pane 2 already on `dashboard.html`).
  2. On **Pane 2 (Nurse)** -> click `Live Patient Queue` in the left sidebar -> point to the top action bar (notice **NO** `Consultation` quick-action button on the top bar and **NO** `Consultation` button on cards); click `Consultations` -> verify **NO** `New Consultation Form` button.
  3. On **Pane 3 (Doctor)** -> click `Live Patient Queue` & `Consultations` -> point out Doctor-exclusive `Consultation` / `Consult Serving` button on the Queue board, `New Consultation Form` on Consultations, and Doctor profile badge.
  4. Glance at **Pane 4 Tab 1 (`dashboard-pharmacist.html`)** -> show Pharmacy Dispense & Inventory workspace, and **Pane 4 Tab 2 (`dashboard-admin.html`)** -> show Administrator 7-tab Command Console.
- **Talking Points:**
  > "Security starts with strict role isolation. One login portal routes staff via email, username, or employee ID into dedicated workspaces — Administrators into `dashboard-admin`, Pharmacists into `dashboard-pharmacist`, and Doctors and Nurses into a shared clinical workstation where UI controls dynamically adapt per role. Every browser tab also isolates its own Supabase Auth token in `sessionStorage`, while Postgres Row-Level Security enforces these same permissions at the database layer."
- **Expected Result on Screen:** Nurse cannot see Doctor consultation triggers; Pharmacist sees only dispensing and stock; Admin sees executive controls; Citizens use mobile only.
- **Objective / Requirement Proved:** Proves multi-tier Role-Based Access Control (RBAC), per-tab session isolation, and defense-in-depth (UI guards + DB RLS).
- **Fallback If It Fails:** If a live login hangs on 15s timeout, use the already authenticated tabs (`Pane 2–4`) and explain `resolve_staff_login_email` + `get_staff_role()`. *(Never intentionally fail login 3 times on deployed URL — triggers a 5-min client lockout.)*

---

### Step 3: Main Outpatient Transaction End-to-End (`2:15 – 8:15`, 6 min 00 sec)

#### Step 3.1: Citizen Books Queue Ticket on Mobile (`2:15 – 3:15`, 1 min 00 sec)
- **Role + Platform / Pane:** **Citizen** on **Pane 1 (Mobile)** -> watched live on **TV Display Tab** & **Pane 2 (Nurse)**.
- **Exact Click Path (Mobile):**
  1. On `uKonekDashboardPage` (Home), tap quick action **`JOIN QUEUE`** (or the ticket icon on the bottom navigation bar).
  2. Point out the green daily slot banner (`X of 20 consultation slots available`).
  3. Under **`HEALTHCARE SERVICE`**, select **`Medical Consultation`**.
  4. Under **`PRIORITY CATEGORY`**, tap **`Regular`** (or `PWD` / `Pregnant`).
  5. Type **`Persistent fever and dry cough for 2 days`** in **`Reason for Visit *`** and **`Mild headache, fatigue`** in **`Symptoms (Optional)`**.
  6. Tap **`GET QUEUE NUMBER`**.
- **Talking Points:**
  > "Our patient starts on the **U-Konek+** mobile app. Before requesting a ticket, the app checks clinic capacity via our `queue_limiter` configuration and lets the patient select their service and priority lane. Behind the scenes, `create_queue_ticket` uses a Postgres advisory transaction lock (`pg_advisory_xact_lock`) so concurrent requests never produce duplicate ticket numbers — and watch the Nurse's board and TV monitor update immediately."
- **Expected Result on Screen:**
  - **Mobile:** `ActiveTicketCard` renders ticket **`#001`**, `Q-YYYYMMDD-MC-001` QR code, **`LEAVE QUEUE`** button, and `QueueStepTracker` at **`Step 1 of 3 (Ticket Issued)`**.
  - **Web Nurse (`Pane 2`) & TV Display:** Ticket `#001` appears automatically in **`Waiting`** within ~1 second via Supabase Realtime (`queue_tickets`).
- **Objective / Requirement Proved:** Proves concurrency-safe mobile ticketing and real-time cross-platform Mobile -> Web/TV synchronization.
- **Fallback If It Fails:** If Realtime lags beyond 3 seconds, click **`Refresh`** (`#queue-refresh-btn`) on the Nurse board or pull down to refresh on Mobile (`_refreshDashboard`); if `create_queue_ticket` reports a duplicate date/service, refresh queue or switch service to `Family Preventive Care & Wellness`.

#### Step 3.2: Nurse Calls Patient, Records Vitals & Advances to Serving (`3:15 – 4:45`, 1 min 30 sec)
- **Role + Platform / Pane:** **Nurse** on **Pane 2 (`dashboard.html` -> `Live Patient Queue`)** -> observed on **Pane 1 (Mobile)** & **TV Display Tab**.
- **Exact Click Path (Nurse Web):**
  1. In **`Waiting`** lane on `#001`, click **`On Call`**.
  2. *(Pause 1s to show Mobile & TV change)* -> On the card now in **`On Call`**, click **`Vitals`** (opens `Vital Signs Assessment` modal `#vital-assessment-modal`).
  3. Enter:
     - Chief Complaint: keep prefilled / confirm `Persistent fever and dry cough`
     - Blood Pressure: **`130/85`**
     - Heart Rate: **`92`**
     - Respiratory Rate: **`20`**
     - Temperature: **`38.4`** *(triggers live amber/red fever risk indicator!)*
     - Oxygen Saturation: **`97`**
     - Height (`cm`): **`165`**, Weight (`kg`): **`62`** *(watch **`Calculated BMI`** auto-compute!)*
     - Current Medications: **`None`**
     - Nurse Notes: **`Febrile on presentation, alert and ambulatory.`**
  4. Click **`Save Assessment`**.
  5. Notice the **`Vitals Assessed`** badge and newly unlocked **`Serve`** button on the `On Call` card -> click **`Serve`**.
- **Talking Points:**
  > "At triage, the Nurse moves ticket `#001` to **On Call**, triggering an instant mobile alert and updating the TV monitor. Notice the Nurse cannot push a patient straight to the doctor without vitals — once we enter a 38.4°C temperature, the system automatically flags clinical risk and computes BMI. Clicking **Save Assessment** unlocks **Serve**, advancing the ticket to **Now Serving** and sounding the clinic chime on the TV display."
- **Expected Result on Screen:**
  - When **`On Call`** is clicked: Mobile shows orange **`YOU ARE ON CALL`** banner (`Step 2 of 3 (On Call)`) + local notification; TV shows `#001` in **`On Call`**.
  - When **`Save Assessment`** is clicked: `upsert_vital_assessment` persists vitals; **`Serve`** button appears.
  - When **`Serve`** is clicked: Web moves card to **`Now Serving`**; TV plays audio chime (`Audio Chime On`) & highlights `#001` in **`NOW SERVING`**; Mobile turns green **`YOU ARE NOW SERVING`** (`Step 3 of 3 (Now Serving)`).
- **Objective / Requirement Proved:** Enforces mandatory nursing triage workflow before physician consult, automated anthropometric/risk calculation, and real-time multi-device queue state transitions.
- **Fallback If It Fails:** If QR scanning or modal fails to open from Queue card, go to left sidebar **`Vitals Triage`** -> click **`New Walk-In Intake`** to record vitals, then click **`Serve`** via Queue card status; if TV chime is silent, verify **`Audio Chime On`** was clicked once to unlock browser audio context.

#### Step 3.3: Doctor Conducts 3-Step EHR Consultation, Lab Order & E-Prescription (`4:45 – 6:30`, 1 min 45 sec)
- **Role + Platform / Pane:** **Doctor** on **Pane 3 (`dashboard.html` -> `Live Patient Queue`)** -> observed on **Pane 1 (Mobile)**.
- **Exact Click Path (Doctor Web):**
  1. On Pane 3 (`Live Patient Queue`), click **`Consultation`** on card `#001` (or **`Consult Serving`** at top right).
  2. Point to the left EHR sidebar inside `Clinical Consultation & EHR Workspace`: patient demographics, **`CRITICAL DRUG ALLERGIES`** box (from prior visit or noted in history), and the Nurse's **`TRIAGE VITALS SUMMARY`** banner (`BP 130/85`, `Temp 38.4°C`, `BMI`).
  3. **Tab `1. History & Subjective`**: Type HPI **`2-day fever, non-productive cough`**, PMH **`None`**, Known Drug Allergies **`Amoxicillin`**, click **`Next Step`**.
  4. **Tab `2. Physical Exam`**: Leave defaults or type Chest/Lungs **`Mild bronchial wheezes, clear bilaterally`**, click **`Next Step`**.
  5. **Tab `3. Assessment & Plan`**:
     - Primary Diagnosis *: **`Acute Upper Respiratory Tract Infection (URTI)`**
     - Laboratory & Diagnostic Orders: **`CBC, Chest X-ray`**
     - Follow-up Schedule: pick date **7 days from today**
     - Clinical Instructions: **`Increase oral fluid intake, complete prescribed antibiotics, return if fever persists >48h.`**
  6. Click **`SAVE & PROCEED TO RX`**.
  7. In **`New Prescription`** modal (`#prescription-modal`):
     - Confirm `#prescription-allergy-banner` visibly warns **`Patient is allergic to: AMOXICILLIN`**. *(Note: We will test the hard block on Amoxicillin cleanly in Step 6!)*
     - Select/type safe medicine **`Paracetamol`** (or **`Paracetamol 500mg`** matching inventory), Dosage **`500mg`**, Frequency **`Every 8 hours (TID)`**, Duration **`5 days`** (watch auto-calculated qty!), Instructions **`Take after meals for fever`**.
     - Click **`Add Medicine`** if adding a second safe drug (e.g., **`Azithromycin 500mg`**, `Once daily`, `3 days`), then click **`Create Prescription`**.
  8. Copy / note the generated **`RX-000XXX`** code shown in the toast / Prescription history (or visible immediately on Citizen's Mobile!).
- **Talking Points:**
  > "Inside the Doctor's EHR workspace, there's no re-asking vitals — the Nurse's assessment and critical allergies load automatically beside the 3-step consultation form. Saving the encounter creates diagnostic lab orders, schedules the patient's 7-day follow-up reminder, completes queue ticket `#001`, and launches the E-Prescription generator. Issuing `RX-` immediately alerts the patient's mobile phone via Supabase Realtime."
- **Expected Result on Screen:**
  - **Web Doctor (`Pane 3`):** Consultation & pending `lab_orders` saved, ticket `#001` completes off the queue board, `RX-000XXX` created.
  - **TV Display:** Returns `NOW SERVING` to `---`.
  - **Mobile (`Pane 1`):** Shows **`Consultation Completed!`** (`Back to Main Menu`) AND **`New E-Prescription Issued!`** alert dialog (`prescription_headers` Realtime) with **`View E-Prescription`** button -> tap it (or later) to show scannable E-Prescription QR + doctor signature & regimen.
- **Objective / Requirement Proved:** Proves seamless EHR handoff, structured clinical documentation, diagnostic order persistence, automated ticket closure, and instant Mobile E-Prescription delivery.
- **Fallback If It Fails:** If `New E-Prescription Issued!` modal doesn't pop automatically on Mobile within 3 seconds, tap **`Dismiss`** on `Consultation Completed!` and tap the **`E-PRESCRIPTION`** tile on Mobile Home to pull the new `RX-` record directly.

#### Step 3.4: Pharmacist Verifies & Atomically Dispenses Prescription (`6:30 – 7:30`, 1 min 00 sec)
- **Role + Platform / Pane:** **Pharmacist** on **Pane 4 Tab 1 (`dashboard-pharmacist.html`)** -> observed on **Pane 1 (Mobile)**.
- **Exact Click Path (Pharmacist Web):**
  1. In **`Dispense Prescription`**, type the digits of **`RX-000XXX`** into **`Prescription ID`** (`#rx-code-input`) -> click **`Look Up`** (mention **`Scan QR`** is available to scan the patient's phone QR directly via camera).
  2. Point out stock badges (`In Stock`) and expiry dates, and note per-item quantity controls allowing **partial dispensing** when stock is low.
  3. Verify selected items -> click **`Confirm Selected Amount`** (`#rx-confirm-dispense-btn`) -> in the confirmation modal, click **`Confirm & Dispense`**.
- **Talking Points:**
  > "At the pharmacy counter, the Pharmacist looks up `RX-000XXX` by code or camera QR. Our server-side `dispense_prescription_items` RPC locks inventory rows, blocks expired batches, supports partial dispensing, and atomically deducts stock. Immediately, the patient's mobile phone receives a dispense confirmation and unlocks their interactive medication schedule."
- **Expected Result on Screen:**
  - **Web Pharmacist (`Pane 4`):** Stock quantity on `Medicine Inventory` drops by the dispensed amount, status turns `Dispensed` (`#rx-dispensed-notice`), and **`Return`** button appears for post-dispense returns if needed.
  - **Mobile (`Pane 1`):** Pops **`Medication Dispensed!`** modal + notification `888` (`View Purchase` / `Dismiss`).
- **Objective / Requirement Proved:** Proves atomic pharmacy fulfillment, stock/expiry integrity, and closed-loop clinical-to-pharmacy-to-patient sync.
- **Fallback If It Fails:** If `RX-` code lookup says `'Medicine not found'` due to text mismatch, ensure the prescribed medicine name in Step 3.3 matches an active non-expired row in `medicines` (case/fuzzy normalized by `normalize_medicine_name`); if Mobile alert lags, tap **`SCHEDULER`** on Mobile Home and pull down to invalidate cache and reload.

#### Step 3.5: Patient Medication Adherence & Digital Records Loop (`7:30 – 8:15`, 45 sec)
- **Role + Platform / Pane:** **Citizen** on **Pane 1 (Mobile)**.
- **Exact Click Path (Mobile):**
  1. From the Dispensed modal tap **`Dismiss`** (or tap **`View Purchase`** briefly to show **`Dispense History Log`**, then back).
  2. Tap the **Calendar icon** (`Medicine Scheduler`) in the bottom bar.
  3. Show the newly dispensed medicine on today's timeline (if `Setup Required` appears for custom intervals, tap **`Current Time`** or tap **`"I've taken it"`** / the **checkmark circle** icon on a scheduled dose).
  4. Point to the **Daily Adherence Progress** card incrementing, plus the **`Undo`** snackbar safety window and **`Consultation History`** tab.
- **Talking Points:**
  > "Closing the patient journey, dispensed medications automatically populate the patient's **Medicine Scheduler** with local push-notification reminders and follow-up alerts. Tapping **I've taken it** logs adherence to `medicine_intake_logs` with a quick undo safeguard — keeping patients compliant after they leave the clinic."
- **Expected Result on Screen:** Dose transitions to **`TAKEN`** with timestamp, Adherence progress bar updates, and `medicine_intake_logs` persists.
- **Objective / Requirement Proved:** Proves post-visit patient adherence tracking driven directly by pharmacy fulfillment data.
- **Fallback If It Fails:** If newly dispensed Rx shows under `Setup Required`, simply tap **`Current Time`** to assign the first dose slot and mark it taken cleanly.

---

### Step 4: Supporting Core Features (`8:15 – 10:15`, 2 min 00 sec)

#### Step 4.1: Staff Availability Sync & Mobile Promo Poster Upload (`8:15 – 9:00`, 45 sec)
- **Role + Platform / Pane:** **Doctor** on **Pane 3 (`dashboard.html`)** -> observed on **Pane 1 (Mobile)**.
- **Exact Click Path:**
  1. On **Pane 3 (Doctor)**, open **`Availability Schedule`** -> click **`Break`** (then back to **`Available`**) on the Doctor's own availability card (`set_staff_availability` RPC). Watch the green/gray status dot update live under **`DOCTORS ON DUTY`** on **Pane 1 (Mobile)**.
  2. On **Pane 3 (Doctor)**, click **`Reports & Analytics`** -> **`Promo Posters & Announcements`** -> click **`New Promo Poster`**.
  3. Enter Title **`Free Flu Vaccination Drive`**, Content **`Available Mon–Fri 8 AM to 5 PM for clinic patients.`**, upload a small sample clinic banner image (or paste URL under `Image URL` tab) -> click **`Publish Promo Poster`**.
  4. On **Pane 1 (Mobile Home)**, pull down to refresh -> swipe the Promo Carousel to show the live banner uploaded to Supabase Storage `promo-banners`.
- **Talking Points:**
  > "For real-time clinic operations, doctors and nurses manage their own availability, which updates the mobile **Doctors On Duty** strip live so patients know who is in. Clinical staff can also publish compressed promotional banners stored in Supabase Storage directly to the mobile home carousel."
- **Expected Result on Screen:** Mobile `DOCTORS ON DUTY` dot toggles in real time; new Promo banner displays in Mobile Home carousel & Notifications.
- **Objective / Requirement Proved:** Demonstrates live staff presence (`staff-availability` Realtime) and Supabase Storage media integration (`promo-banners`).
- **Fallback If It Fails:** Skip image file picker if slow and use the **`Image URL`** tab with a pre-tested HTTPS image URL, or create a text-only announcement.

#### Step 4.2: Citizen Feedback, Clinic Review Hub & 4-Tab EHR Viewer (`9:00 – 9:45`, 45 sec)
- **Role + Platform / Pane:** **Citizen** on **Pane 1 (Mobile)** + **Doctor (`Pane 3`)** & **Nurse (`Pane 2`)**.
- **Exact Click Path:**
  1. On **Pane 1 (Mobile Home)** -> swipe Quick Actions and tap **`FEEDBACK`** -> tap **5 stars**, enter Subject **`Fast Triage`**, message **`Smooth digital queue and clear prescription.`**, tap **`SUBMIT FEEDBACK`** -> tap **`GREAT`**.
  2. On **Pane 3 (Doctor)** -> **`Reports & Analytics`** -> **`Patient Reviews & Feedback`** tab -> click **`Refresh`** -> point out the new 5-star review (with **`Delete`** button visible for Doctor, while **Pane 2 (Nurse)** viewing the same tab sees **no Delete button**!).
  3. On **Pane 3 (Doctor)** -> click **`Personnel & Citizens`** -> **`Citizens`** tab -> search **`Maria`** (demo patient) and click her row -> opens `#citizen-health-modal` showing all **4 EHR tabs**: **`Consultations`**, **`Vitals`**, **`Prescriptions`**, and **`Lab Orders`** (confirming **`CBC` & `Chest X-ray` `Pending`** from Step 3.3!).
- **Talking Points:**
  > "Patient experience closes through the mobile **Feedback** module, which surfaces inside the clinic hub where Doctors and Admins can moderate reviews while Nurses have read-only visibility. Clinicians can also pull up any citizen's unified 4-tab longitudinal EHR — linking vitals, consultations, prescriptions, and laboratory orders in one screen."
- **Expected Result on Screen:** New 5-star feedback appears in Web table; `#citizen-health-modal` shows all 4 clinical tabs populated from Step 3's encounter.
- **Objective / Requirement Proved:** Proves patient engagement loop, granular moderation RBAC, and unified longitudinal EHR retrieval.
- **Fallback If It Fails:** If search lags, click the top recent row in `Citizens`; verify `health-records.js` tabs with any pre-seeded citizen record if needed.

#### Step 4.3: Pharmacist OTC Dispense Linked to Citizen ID (`9:45 – 10:15`, 30 sec)
- **Role + Platform / Pane:** **Pharmacist** on **Pane 4 Tab 1 (`dashboard-pharmacist.html`)**.
- **Exact Click Path (Pharmacist Web):**
  1. Click **`Dispense OTC (Walk-in)`** (`#open-otc-dispense-btn`).
  2. In **`Patient Name / Identifier`**, type **`CIT-<demo_citizen_id>`** (e.g., `CIT-1`, shown under Citizen's **Center QR Button -> Patient Digital Pass**!), select an OTC medicine (e.g., **`Vitamin C 500mg`** / **`Cetirizine 10mg`**), Qty **`5`**, Notes **`Daily immunity support`** -> click **`Confirm & Dispense`** -> close **`OTC Dispense Confirmed`** receipt (`OTC-...` reference).
- **Talking Points:**
  > "Beyond doctor prescriptions, Pharmacists can also process over-the-counter dispenses. Passing the patient's Citizen ID (`CIT-#`) automatically links the OTC purchase into their Mobile Scheduler and Purchase History alongside prescribed drugs."
- **Expected Result on Screen:** OTC receipt displays reference number; OTC inventory decreases; linked Citizen sees it in Mobile Records/Scheduler on refresh.
- **Objective / Requirement Proved:** Proves non-Rx OTC workflow, stock integrity, and cross-role citizen linking.
- **Fallback If It Fails:** Leave `Patient Name / Identifier` as default **`Walk-in Patient`** if Citizen ID isn't handy — `dispense_otc_medicines` still logs the walk-in sale cleanly.

---

### Step 5: Reports, Analytics & Admin Governance (`10:15 – 12:00`, 1 min 45 sec)

- **Role + Platform / Pane:** **Administrator** on **Pane 4 Tab 2 (`dashboard-admin.html`)**.
- **Exact Click Path (Admin Web):**
  1. Click top tab **`Dashboard & Analytics`** -> click **`Refresh`** (`#btn-refresh-analytics`) -> highlight the KPI cards (`Total Citizens`, `Total Consultations`, `Queue Tickets`, `Active Staff`, `Online Staff`) and Chart.js **`Clinical Activity Trends`** + **`Departmental Service Load`** charts.
  2. Click top tab **`System Reports & Exports`** -> select preset **`Today`** -> click **`Export CSV`** on the **`Queue Report`** card (verify `.csv` downloads with Excel formula-injection sanitization) -> click **`Print Official Clinic Census`** (`#btn-open-census-modal`) to preview the formatted **AFM Roquero Medical Clinic Health Census Document** on screen -> click **`Close`** *(do NOT launch browser print dialog here due to modal scroll-clipping in CSS)*.
  3. Briefly click **`Users Management`** (show Staff directory, **`Create Staff Account`**, **`Reset Password`**, **`Enable/Disable`** buttons) -> click **`Doctor Schedules & Roster`** (show today's scheduled physician shift that powers mobile queue availability) -> click **`Backup & Restore`** and click **`Download Full Backup Snapshot (.json)`** (downloads `.json` snapshot of 12 tables).
- **Talking Points:**
  > "At the administrative level, the standalone Admin Console aggregates clinic-wide KPIs, service utilization charts, and an audit-ready Clinic Health Census. Every operational table exports to sanitized CSV spreadsheets, administrators manage staff accounts and physician duty rosters, and one-click JSON snapshots provide disaster-recovery backups."
- **Expected Result on Screen:** Live KPIs reflect Step 3's new consultation/queue/dispense counts; `.csv` and `.json` files download cleanly; Census modal displays formatted operational & top-morbidity totals.
- **Objective / Requirement Proved:** Proves executive reporting, exportability, staff/schedule governance, and backup capability.
- **Fallback If It Fails:** If Census takes >3s to compile or `.csv` download is blocked by popup blocker, allow downloads in browser or display a pre-downloaded CSV/JSON sample ready in your demo folder.

---

### Step 6: Validation, Security & Error Handling (`12:00 – 13:00`, 1 min 00 sec)

- **Role + Platform / Pane:** **Nurse (`Pane 2`)**, **Doctor (`Pane 3`)**, and **Pharmacist (`Pane 4 Tab 1`)**.
- **Exact Click Path (2 Quick, Safe Safeguard Proofs — zero data corruption):**
  1. **Real-Time Clinical Drug Allergy Block (`Pane 3` Doctor)**:
     - **Cleanest zero-junk live path**: Keep a pre-seeded secondary patient (`Test Allergy Patient`) with a prior consultation listing `Allergies: Amoxicillin` (or click **`New Consultation Form`** -> search a dedicated demo allergy test citizen, Tab 1 Allergies **`Amoxicillin`**, Tab 3 Diagnosis **`Validation Check`**, click **`SAVE & PROCEED TO RX`**). Notice `#prescription-allergy-banner` immediately displays **`Patient is allergic to: AMOXICILLIN`**. Type **`Amoxicillin 500mg`** *(matches substring check cleanly in `prescriptionController.js`)* -> show inline red alert **`ALLERGY DETECTED: Patient has documented allergy to "AMOXICILLIN"!`**, then click **`Create Prescription`** -> observe hard block **`CRITICAL ALLERGY ALERT: Patient is allergic to "AMOXICILLIN". Cannot prescribe "Amoxicillin 500mg".`**, then click **`Cancel`**! *(Alternatively, type `Amoxicillin` momentarily during Step 3.3 before switching to `Paracetamol` so zero extra test consultations are created — note that allergy matching uses direct substring matching, so documented allergy must include the drug name e.g. `Amoxicillin` rather than drug class `Penicillin`.)*
  2. **Pharmacist Invalid Rx & Over-Stock Guard (`Pane 4` Pharmacist)**:
     - Type **`999999`** (`RX-999999`) -> click **`Look Up`** -> shows clean **`Prescription not found`** alert.
     - Or click **`Dispense OTC (Walk-in)`**, enter Qty **`99999`** -> click **`Confirm & Dispense`** -> shows **`Requested 99999 ..., but only X is in stock.`** without deducting stock -> click **`Cancel`**.
- **Talking Points:**
  > "Finally, let's verify defensive validation without risking data integrity. Even if a doctor accidentally types **Amoxicillin** for a patient with a documented **Amoxicillin** allergy, our clinical rules engine warns inline immediately and hard-blocks prescription submission (`CRITICAL ALLERGY ALERT`). Similarly, at the pharmacy counter, unknown prescription codes and quantities exceeding available batch stock are safely rejected before touching the database."
- **Expected Result on Screen:** Explicit error alerts appear; zero invalid prescriptions or negative inventory rows are committed.
- **Objective / Requirement Proved:** Proves patient-safety validation, business-rule enforcement, and graceful error handling.
- **Fallback If It Fails:** Show the Pharmacy over-stock block and Nurse role-restriction toast (`'Only doctors can conduct consultations.'` — or explain the client-side 3-attempt auth lockout) if the test allergy modal isn't open.

---

### Step 7: Closing — Objectives Met, Limitations & Future Work (`13:00 – 14:00`, 1 min 00 sec)

- **Role + Platform / Pane:** All panes visible on screen (Dashboard/Mobile/TV).
- **Exact Click Path:** Keep views static on Mobile Scheduler + Doctor Analytics + Admin Dashboard.
- **Talking Points:**
  > "To summarize, **U-Konek** fulfills every core objective: paperless mobile queueing with live TV and nurse synchronization, enforced nursing triage before doctor consults, unified EHR with allergy-checked E-Prescriptions, atomic inventory-safe pharmacy fulfillment, patient adherence tracking, and executive clinic reporting. In keeping with good engineering transparency, we also identified current limitations — such as lab order result entry being display-only on web, two stubbed profile shortcuts on mobile (`Download ID Card` and in-profile `Change Password`), and server-side daily queue limit checks needing restoration in `create_queue_ticket`. Future phases will harden those RLS/RPC edges, integrate lab technician result entry, and enable multi-branch clinic configuration. Thank you — we are ready for your questions."
- **Expected Result on Screen:** Clean, composed multi-platform summary view ready for Q&A.
- **Objective / Requirement Proved:** Demonstrates engineering maturity, honest scope awareness, and clear roadmap vision.
- **Fallback If It Fails:** N/A (verbal wrap-up).

---

## 4. Demo Data, Reset Procedure & Pre-Demo Checklist

### 4.1 Required Test Accounts (1 per Role)

Ensure the following active accounts exist in both Supabase `auth.users` and `public.staff` / `public.citizens` before the defense (never create demo passwords on stage):

| Role | Platform | Demo Identity / Creds Note | Required DB State |
| :--- | :--- | :--- | :--- |
| **Administrator** | Web (`dashboard-admin.html`) | E.g. `admin@ukonek.local` / `ukonek123` *(bootstrap credential from migration `20260505000000` — change or verify before live deploy!)* | `staff.role = 'admin'`, `status = 'active'`, linked `auth_user_id` |
| **Doctor** | Web (`dashboard.html`) | Your demo doctor account (e.g., `doctor@ukonek.local`) | `staff.role = 'doctor'`, `status = 'active'`, `availability_status = 'available'`, **AND at least 1 `doctor_schedules` row for TODAY's Manila date** (`list_available_queue_services` counts scheduled doctors) |
| **Nurse** | Web (`dashboard.html`) | Your demo nurse account (e.g., `nurse@ukonek.local`) | `staff.role = 'nurse'`, `status = 'active'`, `availability_status = 'available'` |
| **Pharmacist** | Web (`dashboard-pharmacist.html`) | Your demo pharmacist account (e.g., `pharmacist@ukonek.local`) | `staff.role = 'pharmacist'`, `status = 'active'` |
| **Citizen (Primary)** | Mobile (`U-Konek+`) | Registered citizen (e.g., Maria Santos, `CIT-X`) | `citizens.auth_user_id` linked, NO active `waiting`/`on_call`/`serving` queue ticket today; optionally 1 prior completed consultation listing `allergies = 'Amoxicillin'` so allergy alert shows automatically |
| **Citizen (Step 6 Allergy Test)** *(Optional)* | Web Doctor | Secondary citizen row (with `allergies = 'Amoxicillin'` on a historical consultation) | Used cleanly in Step 6 without touching primary citizen's ticket |

### 4.2 Required Sample Data So No Screen Looks Empty

1. **Today's Physician Roster (`doctor_schedules`)**: At least **1 schedule slot** for today's date (`Asia/Manila`) assigned to your active demo Doctor.
2. **Pharmacy Catalog (`medicines`)**: At least **4–6 active, non-archived medicines** with future `expiry_date` (`> today + 60 days`) and `qty >= 20` — specifically including **`Paracetamol 500mg`** (`rx` or `otc`), **`Azithromycin 500mg`** (`rx`), **`Amoxicillin 500mg`** (`rx`, for Step 6 allergy check), **`Vitamin C 500mg`** (`otc`, for Step 4.3), plus **1 low-stock (`qty = 3`)** and **1 expired** sample item so Pharmacist filter badges (`Low Stock`, `Expired`) show realistic metrics.
3. **Historical Baseline Encounters (1–2 past days)**: At least 2 completed `consultations` + `vital_signs` + `queue_tickets` from yesterday/earlier this week so Chart.js 7-day trend graphs and `Top Diagnoses` doughnut aren't blank on initial login.
4. **Config (`system_config`)**: `queue_limiter_enabled = 'true'`, `daily_queue_ticket_limit = '20'`.

### 4.3 Reset Procedure (Returning to Clean Demo State)

1. **Database Operational Reset (Existing Script):**  
   Run [`supabase/refresh_operational_data.sql`](supabase/refresh_operational_data.sql) in the **Supabase Dashboard SQL Editor**.  
   - *What it preserves:* `auth.users`, `staff`, `citizens`, `medicines`, `doctor_schedules`, `system_config` (plus it resets active staff `availability_status = 'available'`).  
   - *What it clears (`TRUNCATE ... CASCADE`):* `queue_tickets`, `vital_signs`, `consultations`, `lab_orders`, `prescription_headers`, `prescription_items`, `prescription_item_dispenses`, `otc_dispenses`, `otc_dispense_items`, `dispense_returns`, `medicine_intake_logs`, `staff_login_logs` (note: check `announcements` and `feedbacks` separately if you want old demo banners/reviews cleared too).
2. **Mobile Local Cache Reset:**  
   Because `MainShellPage` saves acknowledged Rx IDs & dispense keys in `SharedPreferences` and `MedicineCacheService`, **Log Out and Log Back In** on the Mobile app (or clear app storage in Android settings) after resetting the DB so pop-up modals (`New E-Prescription Issued!`, `Medication Dispensed!`) trigger cleanly on stage.
3. **Proposed Seed & Clean-Reset Script (Awaiting Your Approval):**  
   *(Per instructions, no SQL script was written yet.)* If you would like, upon your approval I can add a safe, idempotent **`supabase/demo_seed.sql`** script that runs `refresh_operational_data.sql` logic + clears demo `announcements`/`feedbacks` + ensures today's `doctor_schedules` row, 6 sample Rx/OTC/low-stock/expired `medicines`, 2 historical consultations for populated charts, and a documented `Amoxicillin` allergy on a test patient.

### 4.4 Pre-Demo Checklist (T-Minus 30 Minutes)

- [ ] **Connectivity & Supabase Proxy**: Open your hosted Web URL (or local static server on `http://127.0.0.1:5500/web/public/`) and verify Login succeeds (confirm `runtime-config.js` reaches Supabase via `/api/supabase` on Vercel or directly locally; verify `/dashboard-admin.html` loads cleanly!).
- [ ] **Idle Timeout Timer Reset (< 14 mins before defense)**: Sign into all 4 browser tabs (`Nurse`, `Doctor`, `Pharmacist`, `Admin`) **within 5–10 minutes of starting**, because `utils/sessionTimeout.js` enforces a **15-minute inactivity timeout** (`DEFAULT_IDLE_TIMEOUT_MS`) across shared `localStorage['ukonek_last_active_ts']` — moving/clicking once resets it.
- [ ] **TV Queue Display Armed**: Open `tv-view.html` in its tab/window and **click `Audio Chime On`** once so browser autoplay policies allow the notification chime when Nurse clicks `Serve`.
- [ ] **Mobile Screen Mirroring & Permissions**: Connect phone via USB/Wi-Fi (`scrcpy` / Vysor), disable OS Do-Not-Disturb, verify **Notifications permission = Allowed**, and ensure **`Require PIN on App Open` is toggled OFF** in Mobile `Profile -> Security PIN` so unlocking doesn't delay the demo.
- [ ] **Mobile Signed In & Warmed**: Sign in as Citizen on `U-Konek+`, tap `Queue Tracker` once to verify `20` slots available banner and `Medical Consultation` service appear (confirming today's `doctor_schedules` row exists!).
- [ ] **Promo Test Asset Ready**: Keep one crisp clinic PNG/JPG banner (< 1 MB) on Desktop for Step 4.1 (`New Promo Poster`).
- [ ] **Offline Backup Materials Ready**: Pre-recorded screen-capture MP4 clips + high-res screenshots folder + 1 sample CSV & JSON backup saved locally.

### 4.5 Slow or Unreliable Features to Avoid Live on Stage

| Feature | Why Avoid Live | Safer Stage Approach |
| :--- | :--- | :--- |
| **Live Citizen Signup / OTP Email (`OtpPage`)** | Dependent on SMTP inbox latency, 55s Supabase resend throttles, and unused Edge Functions (`citizen-*`) | Use pre-verified Citizen account; verbally walk through the 4-step onboarding UI/RPC architecture |
| **Live Webcam QR Scanning (`Html5Qrcode`)** | Projector/stage glare & webcam autofocus lag frequently stall scanning | Type `RX-000XXX` directly in Pharmacist `Look Up`, and enter vitals from Nurse Queue `Vitals` button |
| **Admin Physical Print (`window.print()`)** | `dashboard-admin.html` lacks `print.css`; `.admin-modal-body` clips printed Census pages | Open `Print Official Clinic Census` modal and showcase the formatted document cleanly on screen |
| **Admin JSON Restore Button** | Swallows chunk errors silently (`{ error }` ignored) & cannot recreate `auth.users` | Demo **Download Full JSON Backup** only; explain restore ordering & constraints verbally |
| **Triggering Wrong Password 3x (Deployed URL)** | Triggers 5-minute client lockout (`LOGIN_LOCK_DURATION_MS = 300000`) | Demo validation safely via Nurse role guard + Drug Allergy block + Invalid `RX-` lookup instead |

---

## 5. Panel Q&A Cheat Sheet (15 Anticipated Questions)

1. **Why did you choose Static HTML/ES Modules + Flutter + Supabase instead of a custom Express/Node backend?**  
   *Answer:* Note that an exploratory Express starter still sits in `web/backend/` as unused reference code, but moving directly to Supabase (`PostgREST`, `Auth`, `Realtime`, `Storage`, and PL/pgSQL RPCs) eliminated redundant API boilerplate, let us enforce authorization inside Postgres Row-Level Security (RLS) close to the data, and gave Web (`supabase-js`) and Mobile (`supabase_flutter`) instant real-time Change Data Capture out of the box.

2. **How do you show 4 staff dashboards simultaneously if Supabase normally stores one Auth session per browser?**  
   *Answer:* By default Supabase uses shared `localStorage`, which would overwrite sessions across tabs. In `web/src/js/lib/supabaseClient.js`, we engineered a per-tab `sessionStorage` adapter (`ukonek.auth.tab_id`) that scopes tokens under `sb-${projectRef}-auth-tab-${tabId}`. That lets Nurse, Doctor, Pharmacist, and Admin stay cleanly isolated side by side in separate tabs of one browser. *(Note: `sessionTimeout.js` intentionally coordinates inactivity logouts across tabs via `localStorage['ukonek_last_active_ts']`.)*

3. **How do you guarantee security if the Web frontend is static JavaScript visible in DevTools?**  
   *Answer:* UI hiding (such as hiding `Consult Serving` from Nurses) is strictly UX convenience. True authorization lives in Postgres RLS policies (`consultations_insert_doctor_only`, `medicines_insert_pharmacist`, etc.) and `SECURITY DEFINER` RPCs using helper checks (`is_admin()`, `is_clinical_staff()`, `is_doctor_or_admin()`). Even if someone calls the API directly, Postgres rejects unauthorized writes.

4. **How do you prevent duplicate queue numbers if multiple citizens click "Get Queue Number" at the exact same millisecond?**  
   *Answer:* Inside `create_queue_ticket`, we acquire a transaction-scoped Postgres advisory lock (`pg_advisory_xact_lock(hashtext(service_key || '::' || date))`), compute `MAX(queue_number) + 1`, generate a unique collision-proof multi-word service prefix (`Q-YYYYMMDD-ABBR-NNN`), and enforce a database unique index (`idx_queue_tickets_unique_slot`) backed by a 5-retry loop on `unique_violation`.

5. **Why does Vercel proxy `/api/supabase/:path*` in `vercel.json` and `runtime-config.js`?**  
   *Answer:* In local environments on some Philippine ISPs/clinic networks, direct connections to `*.supabase.co` experienced TLS 1.3 filtering issues. When hosted on Vercel, `runtime-config.js` automatically routes API traffic same-origin through `/api/supabase/*` via Vercel's edge rewrites to `dqjxpwbsbzagbjtulhue.supabase.co`.

6. **What happens if Realtime WebSockets drop on the clinic Wi-Fi or waiting-room TV?**  
   *Answer:* Both the Nurse/Doctor queue board (`queueController.js`) and TV Display (`tv-view.js`) attach error/close listeners that automatically schedule a 5-second reconnect and activate a 60-second fallback polling interval. Users can also manually click Refresh without losing state.

7. **How does the system protect patient safety during prescribing and dispensing?**  
   *Answer:* Two checkpoints protect the patient: (1) During Doctor E-Prescribing (`prescriptionController.js`), documented allergies from the consultation/history trigger a live inline warning as the doctor types and a hard submission block (`CRITICAL ALLERGY ALERT`) if a match is found; (2) During Pharmacy dispensing (`dispense_prescription_items` RPC), Postgres atomically validates stock quantities, blocks expired medicine batches, supports partial dispensing, and reconciles returns in `dispense_returns`.

8. **What happens if a clinic runs low on stock for a 30-tablet prescription?**  
   *Answer:* Pharmacists aren't forced into an all-or-nothing dispense. `dashboard-pharmacist.html` allows selecting exact quantities per line item. The RPC marks the item/header as `'partial'` while computing `remaining_quantity` via trigger (`trg_sync_prescription_item_quantities`), allowing the patient to return for the remaining balance later.

9. **How did you address performance and concurrency on Supabase's Free Tier?**  
   *Answer:* Earlier performance audits identified swap/IO spikes caused by parallel dashboard queries and unindexed `queue_date`/`created_at` scans. We consolidated dashboard startup into one RPC (`get_dashboard_bootstrap_data`), added covering & `pg_trgm` GIN indexes (`20261011193000`, `20261101120000`), detached hot delete triggers from `queue_tickets` in favor of a nightly `pg_cron` job, and deferred heavy directory/schedule loads until tabs are opened.

10. **How do you prevent CSV spreadsheet formula injection and XSS in exported/rendered data?**  
    *Answer:* All CSV exports in `reports.js` pass fields through `sanitizeCsvCell()` (`utils/querySanitizer.js`), neutralizing leading `=`, `+`, `-`, or `@` characters before Excel opens them. On database writes, `sanitize_*_input` triggers clean text inputs, and clinical renderers HTML-escape strings (though our audit flagged 2 announcement image `onclick` attributes to sanitize further).

11. **What automated maintenance runs in the background?**  
    *Answer:* Three `pg_cron` jobs run automatically in Postgres: (1) `delete-old-pending-queue-tickets` at midnight Manila (`0 16 * * *` UTC) deletes stale pending tickets in 500-row batches; (2) `staff_unavailable_5pm_manila` at 5:00 PM Manila (`0 9 * * *` UTC) sets clinic staff `availability_status = 'unavailable'` after hours; (3) `cleanup-cron-logs` prunes `cron.job_run_details` weekly.

12. **How did you test and verify the system across platforms?**  
    *Answer:* Verification relied on static analysis, SQL schema/migration verification against the hosted Supabase project, and end-to-end manual cross-platform walkthroughs (Mobile <-> TV <-> Nurse <-> Doctor <-> Pharmacist <-> Admin) checking RLS denial for unauthorized roles, Realtime latency, and inventory reconciliation. *(Be honest if asked about unit tests: note `web/` has no automated test suite configured yet, so adding automated integration/RLS tests is part of future work.)*

13. **What are the known security or functional limitations in the current codebase?**  
    *Answer:* Transparency builds panel credibility: (1) Legacy permissive RLS policies on `vital_signs` UPDATE and `system_config` SELECT/UPDATE still need dropping via migration; (2) Server-side `daily_queue_ticket_limit` enforcement in `create_queue_ticket` was accidentally overwritten in a later collision-fix migration (`20260517020000`) and currently relies on the Mobile UI guard; (3) Lab orders are ordered cleanly by the doctor (`Pending`), but updating results to `Completed` lacks a dedicated Lab Tech UI; (4) Mobile `ProfilePage` has two non-persistent shortcuts (`Download ID Card` and in-profile `Change Password`, though Forgot Password email reset works end-to-end).

14. **What happens if a citizen uses the app completely offline or loses internet mid-consultation?**  
    *Answer:* `MedicineCacheService` caches the citizen's medicine schedule locally in `SharedPreferences` so patients can still view doses temporarily, and local scheduled notifications continue firing without internet. However, queue/EHR mutations require Supabase connectivity, and an offline cold launch throws during profile fetch (`main.dart:301-334`), redirecting to Login — something we plan to guard with offline-tolerant session caching.

15. **Who are the actual end-users, and how does U-Konek fit clinic reality (walk-ins vs mobile users)?**  
    *Answer:* The primary users are **Outpatient Citizens**, **Nurses**, **Doctors**, **Pharmacists**, and **Clinic Administrators** at **AFM Roquero Medical Clinic**. Crucially, clinics still serve walk-in patients without smartphones — which is why Nurse Triage supports **New Walk-In Intake** (nullable `citizen_id` + `walkin_patient_name` on `queue_tickets`), and if that patient later downloads U-Konek+, `complete_my_citizen_profile` safely auto-links exact matching historical records.

---

## 6. Mid-Demo Backup Plan (Contingency Playbook)

| Failure Scenario | Immediate Presenter Action (Stay Calm, < 10 sec) | How You Complete the Story |
| :--- | :--- | :--- |
| **Internet / Clinic Wi-Fi Drops** | Switch laptop & phone to a **pre-tested 4G/5G mobile hotspot** immediately. | If hotspot is unavailable or blocked, smoothly switch to **pre-recorded MP4 walkthrough clips** + static **Screenshots Folder** showing each role transition and DB results. |
| **Vercel Proxy or Direct Supabase Timeout** | If deployed URL hangs on login/fetch, switch tab to your **local static server** (`127.0.0.1:5500/web/public/`, which connects directly to `dqjxpwbsbzagbjtulhue.supabase.co` bypassing `/api/supabase`), or vice versa. | Use pre-authenticated tabs (do NOT refresh if data is already visible) or switch to recorded backup video if Supabase itself is unreachable. |
| **Mobile Screen Mirroring Freezes / Disconnects** | Hold the physical phone toward the projector/camera briefly OR toggle ADB/scrcpy reconnect without pausing your Web steps. | Use **Android Emulator running alongside the browser** (pre-launched & logged in before starting!) OR show the pre-captured **Mobile Clip / Screenshots** synced to each Web step. |
| **Realtime Pop-Up Modal Doesn't Fire on Stage** | Tell the panel *"Supabase Realtime falls back gracefully to manual sync"* and hit **Refresh** (`#queue-refresh-btn` on Web / Pull-to-refresh or tap **`E-PRESCRIPTION`** / **`SCHEDULER`** on Mobile). | Never stare waiting for a toast beyond 3 seconds — pulling immediately proves the Postgres data persisted cleanly. |
| **Browser Tab Triggers 15-Minute Inactivity Logout** | Explain that this actually proves the clinic's HIPAA-inspired **15-minute idle lock** (`sessionTimeout.js`), then click into a tab that hasn't timed out — or log back in once using saved browser credentials (< 5 sec). | Keep a second browser profile or pre-copied credentials text file minimized off-screen for instant paste. |
| **Webcam QR Scanner Fails Under Room Lighting** | Do **not** retry camera focus repeatedly; immediately switch to **Manual `RX-000XXX` lookup** (Pharmacist) or Queue Card **`Vitals`** button (Nurse). | Mention camera scanning uses `html5-qrcode` when lighting permits, with manual lookup built in for speed. |
