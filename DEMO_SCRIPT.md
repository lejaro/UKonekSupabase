# U-Konek Live Demo Flow & Presenter Script (14 Minutes)

**System:** **U-Konek** (Web Clinical, Pharmacy & Admin Consoles + TV Display) & **U-Konek+** (Flutter Mobile App)  
**Clinic:** AFM Roquero Medical Clinic  
**Stage Layout:**
- **Pane 1 (Phone Mirror):** Mobile **Citizen** (`U-Konek+`)
- **Pane 2 (Web Tab A):** Web **Nurse** (`dashboard.html`)
- **Pane 3 (Web Tab B):** Web **Doctor** (`dashboard.html`)
- **Pane 4 (Web Tab C1 & C2):** Web **Pharmacist** (`dashboard-pharmacist.html`) & **Admin** (`dashboard-admin.html`)
- **Pane 5 (Toggle Tab):** Public **TV Display** (`tv-view.html` — click `Audio Chime On` before starting)

---

## Step 1: Opening — Problem & Architecture (`0:00 – 0:45`)
- **Where:** All panes visible on screen
- **Action:** Hold on the side-by-side grid (no clicking).
- **Say:**
  > "Good afternoon, panelists. Outpatient clinics often struggle with manual paper queues, disconnected nurse-to-doctor handoffs, paper prescriptions vulnerable to allergy mistakes, and patients forgetting their medication schedules once they leave. Today we present **U-Konek**, our multi-platform clinic system connecting the **U-Konek+** patient mobile app, a waiting-room TV display, and dedicated web workspaces for Nurses, Doctors, Pharmacists, and Administrators — all synced in real time through Supabase PostgreSQL, Row-Level Security, and Realtime updates."
- **Proves:** Problem-solution fit and multi-platform architecture.

---

## Step 2: Authentication & Role-Based Access (`0:45 – 2:15`)
- **Where:** Pane 2 (`Nurse`) -> Pane 3 (`Doctor`) -> Pane 4 (`Pharmacist` / `Admin`) -> Pane 1 (`Mobile`)
- **Click Path:**
  1. Show [`index.html`](web/public/index.html) briefly (or point to your pre-logged tabs — per-tab `sessionStorage` keeps all 4 staff roles signed in side by side).
  2. **Pane 2 (Nurse):** Click **`Live Patient Queue`** (point out no **`Consultation`** button at top or on cards), then click **`Consultations`** (point out no **`New Consultation Form`** button).
  3. **Pane 3 (Doctor):** Show **`Live Patient Queue`** (`Consultation` controls visible) and **`Consultations`** (**`New Consultation Form`** visible).
  4. **Pane 4:** Show **`dashboard-pharmacist.html`** (dispensing & stock only) and **`dashboard-admin.html`** (7 executive admin tabs).
- **Say:**
  > "Access starts with strict role isolation. One login portal routes staff via email, username, or employee ID directly to their workspace — Administrators to `dashboard-admin`, Pharmacists to `dashboard-pharmacist`, and Doctors and Nurses to a shared clinical board where controls adapt dynamically by role. Each browser tab isolates its session token locally, while Postgres Row-Level Security enforces those exact permissions at the database layer."
- **Proves:** Multi-tier RBAC and console/permission isolation.

---

## Step 3: Main Outpatient Transaction End-to-End (`2:15 – 8:15`)

### 3.1 Citizen Books Queue Ticket on Mobile (`2:15 – 3:15`)
- **Where:** **Pane 1 (Mobile)** -> watched live on **TV Display** & **Pane 2 (Nurse)**
- **Click Path:**
  1. On Mobile Home, tap **`JOIN QUEUE`**.
  2. Point to the green slot counter banner (`X of 20 consultation slots available`).
  3. Under **`HEALTHCARE SERVICE`**, tap **`Medical Consultation`**.
  4. Under **`PRIORITY CATEGORY`**, tap **`Regular`** *(or `PWD` / `Pregnant`)*.
  5. Type **`Persistent fever and dry cough for 2 days`** in **`Reason for Visit *`** and **`Mild headache, fatigue`** in **`Symptoms (Optional)`**.
  6. Tap **`GET QUEUE NUMBER`**.
- **Say:**
  > "Let's follow one patient visit from start to finish. On **U-Konek+**, our patient sees daily clinic slot availability, picks **Medical Consultation**, enters their reason for visiting, and taps **Get Queue Number**. Inside Postgres, an advisory lock prevents duplicate ticket numbers under concurrent load, and within a second, ticket `#001` appears live on both the Nurse's queue board and the clinic TV monitor."
- **See on Screen:** Mobile shows `#001`, QR ticket `Q-YYYYMMDD-MC-001`, and `Step 1 of 3 (Ticket Issued)`; Nurse & TV display `#001` in **`Waiting`**.

### 3.2 Nurse Calls Patient, Triages Vitals & Serves (`3:15 – 4:45`)
- **Where:** **Pane 2 (Nurse)** -> watched on **Pane 1 (Mobile)** & **TV Display**
- **Click Path:**
  1. In Nurse **`Live Patient Queue`** -> **`Waiting`**, click **`On Call`** on `#001`. *(Pause 1 sec for Mobile `YOU ARE ON CALL` & TV `On Call` update.)*
  2. On the card now in **`On Call`**, click **`Vitals`**.
  3. Fill vitals: BP **`130/85`**, HR **`92`**, RR **`20`**, Temp **`38.4`** *(triggers live fever alert)*, SpO2 **`97`**, Height **`165`**, Weight **`62`** *(auto-calculates BMI)*, Notes **`Febrile on presentation, alert and ambulatory.`**.
  4. Click **`Save Assessment`**.
  5. Note the **`Vitals Assessed`** badge and newly unlocked **`Serve`** button -> click **`Serve`**.
- **Say:**
  > "At triage, the Nurse calls ticket `#001`, immediately alerting the patient's phone and updating the TV monitor. Notice the Nurse cannot forward a patient straight to the doctor without vitals. Entering a 38.4°C temperature automatically flags clinical risk and computes BMI, and saving vitals unlocks the **Serve** button — sounding the clinic chime on the TV display and signaling **Now Serving** on the phone."
- **See on Screen:** TV chimes & moves `#001` to **`NOW SERVING`**; Mobile turns green **`YOU ARE NOW SERVING`** (`Step 3 of 3`).

### 3.3 Doctor Conducts 3-Step EHR, Lab Order & E-Prescription (`4:45 – 6:30`)
- **Where:** **Pane 3 (Doctor)** -> watched on **Pane 1 (Mobile)**
- **Click Path:**
  1. In Doctor **`Live Patient Queue`**, click **`Consultation`** on card `#001` (or top **`Consultation`** button).
  2. Point out left sidebar: Demographics, **`CRITICAL DRUG ALLERGIES`**, and Nurse's **`TRIAGE VITALS SUMMARY`**.
  3. **Tab `1. History & Subjective`:** HPI **`2-day fever, non-productive cough`**, Known Drug Allergies **`Amoxicillin`**, click **`Next Step`**.
  4. **Tab `2. Physical Exam`:** Chest/Lungs **`Mild bronchial wheezes, clear bilaterally`**, click **`Next Step`**.
  5. **Tab `3. Assessment & Plan`:** Primary Diagnosis **`Acute Upper Respiratory Tract Infection (URTI)`**, Lab Orders **`CBC, Chest X-ray`**, Follow-up **7 days from today**, Clinical Instructions **`Increase oral fluid intake, complete prescribed antibiotics, return if fever persists >48h.`** -> click **`SAVE & PROCEED TO RX`**.
  6. In **`New Prescription`:** Point out `#prescription-allergy-banner` (`Patient is allergic to: AMOXICILLIN`) -> enter safe medicine **`Paracetamol`** (or `Paracetamol 500mg`), Dosage **`500mg`**, Frequency **`Every 8 hours (TID)`**, Duration **`5 days`**, Instructions **`Take after meals for fever`** -> click **`Create Prescription`**. Note the **`RX-000XXX`** code.
- **Say:**
  > "In the Doctor's EHR workspace, the Nurse's vitals and documented allergies load beside the consultation steps so nothing is re-asked. Saving this encounter logs pending lab orders, schedules a 7-day follow-up reminder, completes queue ticket `#001`, and opens the E-Prescription builder. As soon as the doctor issues the Rx, the patient's phone pops a **`New E-Prescription Issued!`** alert with a scannable QR pass."
- **See on Screen:** Ticket `#001` completes; TV returns `NOW SERVING` to `---`; Mobile pops **`Consultation Completed!`** and **`New E-Prescription Issued!`** (`View E-Prescription` shows Rx QR).

### 3.4 Pharmacist Looks Up & Dispenses Prescription (`6:30 – 7:30`)
- **Where:** **Pane 4 Tab 1 (Pharmacist)** -> watched on **Pane 1 (Mobile)**
- **Click Path:**
  1. In **`Dispense Prescription`**, enter the digits of **`RX-000XXX`** -> click **`Look Up`** *(mention **`Scan QR`** works with camera too)*.
  2. Point out live stock badges, expiry dates, and partial-dispense quantity controls.
  3. Click **`Confirm Selected Amount`** -> click **`Confirm & Dispense`**.
- **Say:**
  > "At the pharmacy, the Pharmacist enters `RX-000XXX` — or scans the mobile QR — to verify stock levels and expiration dates. Confirming dispense triggers an atomic database RPC that locks inventory rows, supports partial fills if stock is low, deducts inventory, and pushes a **`Medication Dispensed!`** alert straight back to the patient's phone."
- **See on Screen:** Stock count decrements; Rx marks `Dispensed` with **`Return`** option available; Mobile receives dispense modal + notification.

### 3.5 Citizen Tracks Adherence in Mobile Scheduler (`7:30 – 8:15`)
- **Where:** **Pane 1 (Mobile)**
- **Click Path:**
  1. Tap **`Dismiss`** on the Dispensed modal (or **`View Purchase`** -> back).
  2. Tap the **Calendar icon** (`Medicine Scheduler`) in the bottom bar.
  3. On today's dose card, tap **`"I've taken it"`** / the **checkmark icon** *(if `Setup Required`, tap **`Current Time`** first)*.
  4. Point to the **Daily Adherence Progress** bar, **`UNDO`** toast, and **`Consultation History`** tab.
- **Say:**
  > "Once dispensed, those medicines automatically populate the patient's **Medicine Scheduler** alongside local dose reminders and follow-up alerts. Tapping **I've taken it** records intake adherence with a quick undo window, closing the loop between doctor, pharmacy, and patient."
- **See on Screen:** Dose shows **`TAKEN`** with timestamp and adherence % increases.

---

## Step 4: Supporting Core Features (`8:15 – 10:15`)

### 4.1 Availability Sync & Mobile Promo Poster (`8:15 – 9:00`)
- **Where:** **Pane 3 (Doctor)** -> **Pane 1 (Mobile)**
- **Click Path:**
  1. **Pane 3 (Doctor):** Open **`Availability Schedule`** -> click **`Break`**, then back to **`Available`** on the Doctor's card *(watch **`DOCTORS ON DUTY`** dot change live on Mobile Home)*.
  2. **Pane 3 (Doctor):** Open **`Reports & Analytics`** -> **`Promo Posters & Announcements`** -> **`New Promo Poster`** -> Title **`Free Flu Vaccination Drive`**, Content **`Available Mon–Fri 8 AM to 5 PM.`**, attach sample banner image (or `Image URL`) -> click **`Publish Promo Poster`**.
  3. **Pane 1 (Mobile):** Pull to refresh Home -> swipe Promo Carousel.
- **Say:**
  > "Clinicians also control real-time **Availability Status**, which updates the mobile **Doctors On Duty** indicator instantly, and can publish clinic announcements with compressed banners stored in Supabase Storage straight to the mobile home carousel."

### 4.2 Citizen Feedback & 4-Tab Citizen EHR Viewer (`9:00 – 9:45`)
- **Where:** **Pane 1 (Mobile)** + **Pane 3 (Doctor)** & **Pane 2 (Nurse)**
- **Click Path:**
  1. **Pane 1 (Mobile Home):** Tap **`FEEDBACK`** -> 5 stars -> Subject **`Fast Triage`**, message **`Smooth digital queue and clear prescription.`**, tap **`SUBMIT FEEDBACK`** -> **`GREAT`**.
  2. **Pane 3 (Doctor):** **`Reports & Analytics`** -> **`Patient Reviews & Feedback`** -> click **`Refresh`** *(point out Doctor sees **`Delete`**, while Nurse on Pane 2 is view-only)*.
  3. **Pane 3 (Doctor):** **`Personnel & Citizens`** -> **`Citizens`** -> click the citizen row -> open `#citizen-health-modal` showing **`Consultations`**, **`Vitals`**, **`Prescriptions`**, and **`Lab Orders`** (`CBC, Chest X-ray` `Pending`).
- **Say:**
  > "Patients can rate their visit inside the app, feeding the clinic review hub where Doctors can moderate feedback while Nurses remain read-only. Clinicians can also inspect any citizen's unified 4-tab longitudinal EHR — uniting vitals, consultations, prescriptions, and pending lab orders."

### 4.3 Citizen-Linked OTC Pharmacy Dispense (`9:45 – 10:15`)
- **Where:** **Pane 4 Tab 1 (Pharmacist)**
- **Click Path:** Click **`Dispense OTC (Walk-in)`** -> enter **`CIT-<id>`** in **`Patient Name / Identifier`** *(matching citizen's **Center QR Button -> Patient Digital Pass**)* -> choose OTC item (e.g., **`Vitamin C 500mg`**), Qty **`5`** -> click **`Confirm & Dispense`** -> close **`OTC Dispense Confirmed`** receipt.
- **Say:**
  > "For walk-in over-the-counter purchases, pharmacists can optionally attach a citizen's `CIT-#` ID so OTC medications sync into that patient's mobile purchase history and medicine scheduler as well."

---

## Step 5: Reports, Analytics & Admin Console (`10:15 – 12:00`)
- **Where:** **Pane 4 Tab 2 (`dashboard-admin.html` — Admin)**
- **Click Path:**
  1. **`Dashboard & Analytics`** -> click **`Refresh`** -> point to KPI cards (`Total Citizens`, `Total Consultations`, `Queue Tickets`, `Active Staff`, `Online Staff`) and both Chart.js graphs (`Clinical Activity Trends`, `Departmental Service Load`).
  2. **`System Reports & Exports`** -> select **`Today`** -> click **`Export CSV`** on **`Queue Report`** -> click **`Print Official Clinic Census`** to preview the **Clinic Health Census Document** on screen -> click **`Close`** *(do not open browser print dialog here)*.
  3. Click **`Users Management`** (`Create Staff Account`, `Reset Password`, `Enable/Disable`) -> click **`Doctor Schedules & Roster`** (shows today's shift enabling queue services) -> click **`Backup & Restore`** -> click **`Download Full Backup Snapshot (.json)`**.
- **Say:**
  > "On the administrative side, the Admin Console brings together clinic-wide KPIs, morbidity/department charts, and an audit-ready Clinic Health Census. Every report exports cleanly to formula-sanitized CSV files, admins control staff accounts and physician schedules, and full JSON snapshots can be downloaded anytime for disaster recovery."

---

## Step 6: Safety Validation & Error Handling (`12:00 – 13:00`)
- **Where:** **Pane 3 (Doctor)** & **Pane 4 Tab 1 (Pharmacist)**
- **Click Path:**
  1. **Clinical Drug Allergy Hard-Block (Doctor):** On a patient with documented Allergy **`Amoxicillin`** (e.g., pre-seeded `Test Allergy Patient` or inside **`New Prescription`**), type **`Amoxicillin 500mg`** -> highlight live red warning **`ALLERGY DETECTED: Patient has documented allergy to "AMOXICILLIN"!`** -> click **`Create Prescription`** -> show **`CRITICAL ALLERGY ALERT`** hard block -> click **`Cancel`**.
  2. **Pharmacy Guard (Pharmacist):** Look up **`999999`** (`Prescription not found`), or inside **`Dispense OTC (Walk-in)`** try Qty **`99999`** -> **`Confirm & Dispense`** -> shows insufficient-stock error cleanly -> click **`Cancel`**.
- **Say:**
  > "To verify safety guardrails without risking live data, suppose a doctor mistakenly attempts to prescribe **Amoxicillin** for a patient allergic to it — the system warns inline immediately and hard-blocks submission. At the pharmacy, invalid prescription IDs and quantities exceeding stock are likewise rejected before any inventory changes."
  *(Tip: Do not intentionally fail login 3x on a deployed URL — it triggers a 5-minute client lockout.)*

---

## Step 7: Closing (`13:00 – 14:00`)
- **Where:** All panes steady
- **Action:** Hold view cleanly across screens.
- **Say:**
  > "To recap, **U-Konek** delivers paperless mobile queueing with live TV and nurse sync, enforced triage before doctor consultation, unified EHR with allergy-checked E-Prescriptions, atomic pharmacy stock dispensing, mobile medication adherence, and executive reporting. For full transparency, current limitations include lab order results being display-only on web, two stubbed profile shortcuts on mobile, and restoring server-side daily queue cap checks in Postgres. Our roadmap covers lab-result entry, offline-resilient mobile caching, and multi-clinic configuration. Thank you — we are now ready for your questions."

---

## Quick Reminders Before Going Live (`T-10 Mins`)
1. Run [`supabase/refresh_operational_data.sql`](supabase/refresh_operational_data.sql) before starting, and log out/in once on Mobile to clear local alert caches.
2. Confirm today has a **`doctor_schedules`** row for your demo Doctor and stock `>= 20` on `Paracetamol 500mg` and an OTC medicine.
3. Log into all 4 web tabs **within 10 minutes of your presentation** (idle timeout logs tabs out at 15 minutes), click **`Audio Chime On`** on TV Display, and turn **OFF** Mobile `Require PIN on App Open`.
4. Fallback rule: If Realtime lags > 3 seconds, click **`Refresh`** (`Web`) or pull to refresh (`Mobile`); if internet drops, switch immediately to hotspot or pre-recorded MP4/screenshots.
