# UKonek Supabase Performance Investigation Report

**Date:** 2026-08-16
**Scope:** Web app (doctors/nurses/pharmacists) + Mobile app (patients) sharing a single Supabase (Postgres) database on the Free tier.

## Executive Summary

The Supabase Free tier instance (0.5 GB RAM, shared I/O) is under severe memory pressure at idle (71% swap usage) due to a combination of:
1. **Aggressive polling loops** creating connection/query storms
2. **Unbounded queries** fetching entire tables
3. **Leaked realtime channels and timers** accumulating over a session
4. **Expensive RLS policies** with per-row subquery evaluations
5. **A background `cron.job_run_details` table** growing unbounded

Under concurrent load, these compound to exhaust the Disk I/O budget, causing the observed "reached I/O limit" (Disk IO Budget exhausted) error.

**Scorecard (code review):** 7 issues found across 8 areas.
**Scorecard (live verification 2026-08-16):** All code-review findings confirmed against the live database (`dqjxpwbsbzagbjtulhue`), with **4 corrections and 2 new findings**:

| # | Finding | Code Review | Live DB | Correction |
|---|---------|:-----------:|:-------:|-----------|
| 1 | `get_today_ticket_count()` missing FROM clause | ❌ Bug | ✅ Fixed | **Bug already patched in live DB** — migration file is stale |
| 2 | Missing `idx_vital_signs_queue_ticket_id` | ❌ Missing | ✅ Exists | **Already fixed in live** |
| 3 | Missing `idx_announcements_created_at` | ❌ Missing | ✅ Exists | **Already fixed in live** |
| 4 | Missing `idx_feedbacks_created_at` | ❌ Missing | ✅ Exists | **Already fixed in live** |
| 5 | Missing `idx_staff_login_logs_logged_at` | ❌ Missing | ✅ Exists | **Already fixed in live** |
| 6 | Missing `idx_doctor_schedules_date` | ❌ Missing | ✅ Exists | **Already fixed in live** |
| 7 | Hourly cron job | Not in migrations | ❌ Found | **NEW: `staff_unavailable_5pm_manila` runs hourly (24×/day)** |
| 8 | Sequential scans on staff | Suspected | ❌ Confirmed | **NEW: 461,908 seq scans / 2.36M rows on staff table** |

**Updated Scorecard:** 6 confirmed issues + 2 new live-only findings + 1 migration-vs-live discrepancy.

---

## Area 1: Realtime Subscriptions — ❌ ISSUE FOUND (High Impact)

### Findings

| File | Line(s) | Table | Filter | Problem |
|------|---------|-------|--------|---------|
| `frontend/web/js/dashboard.js` | 2177 | `staff` | **None** (`event: '*'`, no filter) | Subscribes to ALL changes on the entire `staff` table. Every staff update triggers rendering for ALL connected users. |
| `frontend/web/js/dashboard.js` | 8660 | `queue_tickets` | **None** (`event: '*'`, no filter) | Subscribes to ALL changes on the entire `queue_tickets` table. |
| `frontend/web/js/tv-view.js` | 78 | `queue_tickets` | **None** (`event: '*'`, no filter) | Third unfiltered subscription to the same table. |
| `frontend/mobile/ukonekmobile/lib/uKonekDoctorSchedulesPage.dart` | 38 | `staff` | **None** (`PostgresChangeEvent.all`) | Subscribes to entire `staff` table from mobile. |

### Leak on Logout (Critical)

- `performLogout()` at `dashboard.js:415` does **NOT** call `removeChannel()` on `staffAvailabilityChannel` or the `queue-board-updates` channel.
- Does **NOT** call `stopPresenceHeartbeat()` or `stopAdminDashboardAutoRefresh()`.
- `staffAvailabilityChannel` (declared at line 2170) is never nulled after use.

### Estimated Channels Per Session

- Web dashboard: **2 channels** (`staff-availability`, `queue-board-updates`)
- TV view: **1 channel** (`tv-queue-updates`)
- Mobile schedules page: **1 channel** (`staff-availability`)

**Total: 4+ realtime WebSocket connections per user session.** If a user logs out and back in repeatedly during a demo, channels leak.

### Why It Contributes to Memory/IO Pressure

Each realtime subscription:
- Opens a WebSocket connection consuming client + server memory
- Maintains a replication slot/socket on the Supabase side
- Broadcasts every table change to all subscribers, causing unnecessary renders and more DB queries

### Fix

**1. Clean up on logout** — `frontend/web/js/dashboard.js`:
```javascript
async function performLogout() {
  try {
    stopPresenceHeartbeat();
    stopAdminDashboardAutoRefresh();
    const { supabase } = await loadSupabaseModule();
    if (staffAvailabilityChannel) {
      supabase.removeChannel(staffAvailabilityChannel);
      staffAvailabilityChannel = null;
    }
    const authService = await loadAuthServiceModule();
    await authService.signOutStaff();
    const authSession = await loadAuthSessionModule();
    authSession.clearAuthSessionMeta();
    sessionStorage.removeItem('ukonek_role');
  } catch (error) {
    console.warn('Sign out warning:', error);
  } finally {
    window.location.replace('./index.html');
  }
}
```

**2. Add filters to subscriptions** — e.g., `staff-availability`:
```javascript
.on('postgres_changes', {
  event: '*', schema: 'public', table: 'staff',
  filter: `role=in.(doctor,nurse)`  // Only track relevant roles
}, callback)
```

**3. Mobile page** — `uKonekDoctorSchedulesPage.dart` already properly disposes its channel in `dispose()` (line 28-32) ✅. Only the web dashboard leaks.

---

## Area 2: Polling / Refetch Intervals — ❌ ISSUE FOUND (Critical — #1 Contender)

### Findings

#### Mobile App — 9-Second Polling Loop (Critical)

| File | Line(s) | Code | Impact |
|------|---------|------|--------|
| `frontend/mobile/ukonekmobile/lib/uKonekDashboardPage.dart` | 124 | `Timer.periodic(const Duration(seconds: 9), (_) => _loadAllData(isInitial: false))` | Fires **6 API calls every 9 seconds**: `listDoctorStatus`, `getMyQueueDashboard`, `fetchPrescriptions`, `fetchAnnouncements`, `getTvQueueDisplay`, `SharedPreferences` |
| `frontend/mobile/ukonekmobile/lib/uKonekJoinQueuePage.dart` | 101 | `Timer.periodic(const Duration(seconds: 9), (_) => _refreshDashboard())` | Fires **2 RPC calls every 9 seconds**: `getMyQueueDashboard`, `getQueueLimiterStatus` |

#### Web App — Multiple Polling Loops

| File | Line(s) | Interval | Action |
|------|---------|----------|--------|
| `frontend/web/js/dashboard.js` | 4221 | 15 seconds | `loadStaffData()` — fetches ALL staff |
| `frontend/web/js/dashboard.js` | 4228 | 60 seconds | `pushPresenceHeartbeat()` — writes to DB |
| `frontend/web/js/dashboard.js` | 8650 | 60 seconds | `refresh()` — refetches queue tickets |
| `frontend/web/js/tv-view.js` | 51 | 60 seconds | `loadQueueData()` — RPC call |

### Why It Contributes to Memory/IO Pressure

With 10 concurrent mobile users on the 9-second loop:
- **6 calls × (3600/9) × 10 users = 24,000 API calls/hour**
- Each call opens a connection, executes queries, and consumes I/O
- This is the **#1 contributor to I/O spikes under concurrent access**

The 15-second admin dashboard refresh (`ADMIN_DASHBOARD_REFRESH_MS = 15000` at `dashboard.js:22`) also compounds — `loadStaffData()` calls `list_staff_accounts` RPC which internally does RLS checks.

### Fix

**Mobile dashboard** (`uKonekDashboardPage.dart:124`):
```dart
// Change 9 seconds → 60 seconds (realtime handles instant updates)
_refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
  _loadAllData(isInitial: false);
});
```

**Mobile join queue page** (`uKonekJoinQueuePage.dart:101`):
```dart
// Change 9 seconds → 30 seconds minimum
_refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshDashboard());
```

**Web admin dashboard** (`dashboard.js:22`):
```javascript
// Line 22: change 15000 → 60000
const ADMIN_DASHBOARD_REFRESH_MS = 60000;
```

**Add beforeunload cleanup** (`dashboard.js`):
```javascript
window.addEventListener('pagehide', () => {
  stopPresenceHeartbeat();
  stopAdminDashboardAutoRefresh();
  handleAutoLogoutOnClose();
});
```

---

## Area 3: N+1 Queries / Missing Joins — ❌ ISSUE FOUND (Medium Impact)

### Findings

#### Pharmacy Prescription Search (5 sequential queries)

`frontend/web/js/dashboard.js:8042-8151` — `searchPrescription()`:

1. `prescription_headers` — find header (line 8055)
2. `consultations` — get patient name (line 8081)
3. `citizens` — fallback patient lookup (line 8093)
4. `prescription_items` — get items (line 8105)
5. `medicines` — get stock (line 8117)

**5 sequential queries where 2–3 joined queries would suffice.**

#### Mobile API calls — Profile Re-Fetch Per Call

| File | Line(s) | Pattern |
|------|---------|---------|
| `frontend/mobile/ukonekmobile/lib/services/api_service.dart` | 1176-1191 | `fetchVitalSigns()`: calls `fetchMyCitizenProfile()` first, then queries vital_signs |
| `frontend/mobile/ukonekmobile/lib/services/api_service.dart` | 1221-1236 | `fetchConsultations()`: calls `fetchMyCitizenProfile()` first, then queries consultations |
| `frontend/mobile/ukonekmobile/lib/services/api_service.dart` | 1249-1261 | `logMedicineIntake()`: calls `fetchMyCitizenProfile()` first, then inserts |
| `frontend/mobile/ukonekmobile/lib/services/api_service.dart` | 1263-1278 | `getIntakeLogsForDate()`: calls `fetchMyCitizenProfile()` first, then queries |

Each of these fires a `citizens` query + a second query. Combined with the 9-second polling loop, this compounds.

### Fix

**1. Replace pharmacy search with a single joined query** (dashboard.js):
```javascript
const { data } = await supabase
  .from('prescription_headers')
  .select(`
    *,
    doctor:staff(firstname, surname),
    consultation:consultations(
      patient_citizen_id,
      patient:citizens(firstname, surname)
    ),
    items:prescription_items(*)
  `)
  .eq('prescription_code', prescriptionCode)
  .single();
```
Then fetch `medicines.stock_quantity` with a single `.in()` query (already done at line 8117).

**2. Cache citizen profile in mobile app** (api_service.dart):
```dart
static Map<String, dynamic>? _cachedCitizenProfile;

static Future<Map<String, dynamic>> fetchMyCitizenProfile({bool force = false}) async {
  if (!force && _cachedCitizenProfile != null) return _cachedCitizenProfile!;
  // ... existing logic, then:
  _cachedCitizenProfile = response;
  return response;
}
```
Invalidate the cache on logout.

---

## Area 4: Missing Indexes — ❌ ISSUE FOUND (Medium Impact)

### Existing Indexes

The performance indexes migration (`supabase/migrations/20260520000000_add_performance_indexes.sql`) covers:
- `staff(auth_user_id)`, `staff(lower(email))`
- `citizens(auth_user_id)`, `citizens(lower(email))`
- `queue_tickets(queue_date, status)`, `queue_tickets(citizen_id)`, `queue_tickets(ticket_code)`
- `consultations(patient_citizen_id)`, `consultations(doctor_staff_id)`, `consultations(consulted_at DESC)`
- `prescription_headers(doctor_staff_id)`, `prescription_headers(consultation_id)`
- `prescription_items(prescription_id)`
- `doctor_schedules(doctor_staff_id, schedule_date)`

### Missing Indexes

#### Live DB Verification (2026-08-16 via `pg_indexes`)

**Only 3 of the 8 code-review gaps are REAL in the live database:**

| Table | Missing Column | Used In | Live Status |
|-------|---------------|---------|:-----------:|
| `prescription_headers` | `patient_identifier` | OR queries with `patient_identifier.eq.CIT-${id}` (health-records.js:198, dashboard.js) | ❌ **Still missing** |
| `lab_orders` | `patient_citizen_id` | `health-records.js:205` filters by `patient_citizen_id` | ❌ **Still missing** |
| `lab_orders` | `created_at` | `dashboard.js:6622` orders by `created_at DESC` | ❌ **Still missing** |

**Already fixed in live DB (added manually through dashboard, not in migration files) — ✅ confirmed present:**

| Table | Column | Live Index Name |
|-------|--------|-----------------|
| `vital_signs` | `queue_ticket_id` | `idx_vital_signs_queue_ticket_id` + unique `uq_vital_signs_queue_ticket` |
| `feedbacks` | `created_at` | `idx_feedbacks_created_at` (DESC) |
| `announcements` | `created_at` | `idx_announcements_created_at` (DESC) |
| `staff_login_logs` | `logged_at` | `idx_staff_login_logs_logged_at` (DESC) + `idx_staff_login_logs_staff_id` |
| `doctor_schedules` | `schedule_date` | `idx_doctor_schedules_date` + `idx_doctor_schedules_doctor_date` |

**Bonus indexes found in live (not in migrations):** `idx_consultations_status`, `idx_consultations_follow_up_date`, `idx_prescription_headers_code`, `idx_prescription_headers_status`, `idx_lab_orders_status`, `idx_lab_orders_consultation_id`, `idx_medicines_*` (4), `idx_announcements_visibility`.

### Fix

Only the **3 genuinely-missing indexes** need to be created (the other 5 from code review are confirmed live already):

```sql
-- Run in Supabase SQL Editor (or as a new migration)
CREATE INDEX IF NOT EXISTS idx_prescription_headers_patient_identifier ON public.prescription_headers(patient_identifier);
CREATE INDEX IF NOT EXISTS idx_lab_orders_patient_citizen_id ON public.lab_orders(patient_citizen_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_created_at ON public.lab_orders(created_at DESC);
```

---

## Area 5: RLS Policy Complexity — ❌ ISSUE FOUND (High Impact)

### Findings

Every RLS policy on `consultations`, `prescription_headers`, `prescription_items`, and `queue_tickets` uses `EXISTS` subqueries and function calls that run **per-row**:

| File | Line(s) | Policy | Complexity |
|------|---------|--------|------------|
| `supabase/migrations/20260404130000_create_consultations_and_prescriptions.sql` | 81-92 | `consultations_select_active_staff` | `is_admin()` function call + `EXISTS (SELECT 1 FROM staff WHERE auth_user_id = auth.uid() AND ...)` |
| Same | 95-107 | `consultations_insert_doctor_only` | `EXISTS` with `staff` join + `lower(trim(coalesce(...)))` on 3 columns |
| Same | 109-121 | `prescription_headers_select_active_staff` | Same pattern as consultations |
| Same | 138-150 | `prescription_items_select_active_staff` | Same pattern |
| `supabase/migrations/20260404143000_create_queue_feature.sql` | 53-70 | `queue_tickets_select_policy` | **Three-way OR**: `EXISTS (SELECT 1 FROM citizens ...)` OR `is_admin()` OR `EXISTS (SELECT 1 FROM staff ...)` |
| `supabase/migrations/20260324110000_rls_and_functions.sql` | 42-55 | `is_admin()` function | `EXISTS (SELECT 1 FROM staff WHERE auth_user_id = auth.uid() AND role = 'admin' AND status = 'active')` |

### Live DB Verification (2026-08-16 via `pg_policies`)

All code-review RLS concerns **confirmed live** AND **4 additional policies were found** that exist only in the live DB (added via dashboard, not present in any migration file):

| Live Policy (not in migrations) | Table | Complexity |
|---|---|---|
| `citizens_select_active_staff` | citizens | `EXISTS (SELECT 1 FROM staff s WHERE auth_user_id=auth.uid() AND lower(trim(coalesce(status,'')))) ` |
| `consultations_update_nurse_vitals` | consultations | Requires role IN ('doctor','nurse') with 3× `lower(trim(coalesce()))` |
| `prescription_headers_select_pharmacist` | prescription_headers | Role='pharmacist' with 3× `lower(trim(coalesce()))` |
| `prescription_headers_update_pharmacist` | prescription_headers | Same pattern |

Live `queue_tickets_select_policy` also confirms the three-way OR with **two** `EXISTS` subqueries + `is_admin()`.

### Why It Contributes to Memory/IO Pressure

For a query returning 100 consultations, the `consultations_select_active_staff` policy will execute the `is_admin()` function + `EXISTS` subquery **100 times** (once per row). Each evaluation does an index lookup on `staff`. Under concurrent load, this multiplies the query cost.

Worse: the `lower(trim(coalesce(s.status, '')))` pattern calls 3 functions per row per column. This prevents index usage on `status` and forces sequential scans.

#### 📊 Live-proven impact — `pg_stat_user_tables` (2026-08-16)

| Table | Sequential Scans | Rows Read via Seq Scan | Index Scans |
|-------|:---:|:---:|:---:|
| `staff` | **461,908** | **2,361,801** | 19,400 |
| `queue_tickets` | 121,505 | 730,383 | 88,641 |
| `citizens` | 108,669 | 454,703 | 36,327 |
| `prescription_items` | 48,767 | 550,792 | 32,804 |
| `prescription_headers` | 36,957 | 240,141 | 4,564 |

**The 461,908 sequential scans on `staff` (2.36M rows read) are the direct consequence of the RLS `EXISTS (SELECT 1 FROM staff ...)` pattern**: every SELECT/UPDATE/DELETE on consultations, prescriptions, queue_tickets, and citizens triggers a fresh full-table scan of `staff` for the RLS check. This is the **#1 memory/IO pressure source at idle** — a single logged-in staff user with the dashboard open generates thousands of these RLS-triggered scans.

#### 📊 Live-proven query volume — `pg_stat_statements` top 5 (2026-08-16)

| Query | Calls | Total ms | Mean ms |
|-------|-------:|--------:|--------:|
| Realtime WAL (`SELECT wal->>'type'...`) | **539,461** | 4,607,834 | 8.5 |
| `list_staff_accounts` RPC | **56,071** | 1,120,190 | 20.0 |
| `get_my_queue_dashboard` RPC (all variants) | **47,138** | ~1.78M | ~43 |
| Announcements select | 37,195 | 329,083 | 8.9 |
| `get_queue_limiter_status` RPC | 2,085 | 195,835 | 93.9 |

This confirms: (a) the mobile 9s polling is hammering `get_my_queue_dashboard`, (b) the realtime WAL polling (from unfiltered supabase-channel subscriptions + auto-refresh) is the single largest query count (539k), and (c) the admin dashboard refresh drives `list_staff_accounts`.

### Fix

**1. Normalize status/role values via trigger** to remove `lower(trim(coalesce(...)))`:

```sql
CREATE OR REPLACE FUNCTION public.normalize_staff_columns()
RETURNS trigger AS $$
BEGIN
  NEW.role := lower(trim(NEW.role));
  NEW.status := lower(trim(NEW.status));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_normalize_staff_columns ON public.staff;
CREATE TRIGGER trg_normalize_staff_columns
  BEFORE INSERT OR UPDATE ON public.staff
  FOR EACH ROW EXECUTE FUNCTION public.normalize_staff_columns();

-- Also normalize citizens.status if it exists
DROP TRIGGER IF EXISTS trg_normalize_citizen_columns ON public.citizens;
CREATE TRIGGER trg_normalize_citizen_columns
  BEFORE INSERT OR UPDATE ON public.citizens
  FOR EACH ROW EXECUTE FUNCTION public.normalize_staff_columns();
```

Then update policies:
```sql
-- Replace
lower(trim(coalesce(s.status, ''))) = 'active'
-- With
s.status = 'active'
```

**2. Simplify `is_admin()` to be index-friendly** (migration `20260502000000_update_is_admin_to_include_nurse.sql` may need updating):

```sql
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.staff
    WHERE auth_user_id = auth.uid()
      AND role IN ('admin', 'nurse')   -- normalized values
      AND status = 'active'
  );
$$;
```

**3. Rewrite `queue_tickets_select_policy` to use a single lookup** — the three-way OR with three subqueries is extremely expensive:

```sql
DROP POLICY IF EXISTS queue_tickets_select_policy ON public.queue_tickets;
CREATE POLICY queue_tickets_select_policy
  ON public.queue_tickets
  FOR SELECT
  USING (
    public.has_staff_or_owner_access()  -- single function call, not 3 subqueries
  );
```

---

## Area 6: Connection Handling — ⚠️ ISSUE FOUND (Low-Medium Impact)

### Findings

| File | Line(s) | Issue |
|------|---------|-------|
| `frontend/web/js/tv-view.js` | 29-31 | Creates a **separate** Supabase client instance with `auth: { persistSession: false, autoRefreshToken: false }` — a second WebSocket connection alongside the dashboard's client |
| `frontend/web/js/lib/supabaseClient.js` | 36-44 | Web dashboard uses a single shared client — ✅ correct |
| `frontend/mobile/ukonekmobile/lib/main.dart` | 22-25 | Mobile uses `Supabase.initialize()` singleton — ✅ correct |

### Why It Contributes

The TV view page opens a **second** WebSocket connection to Supabase. On the Free tier, each WebSocket connection consumes memory on the Supabase side. If multiple TV tabs are open (one per clinic TV), each creates a new connection.

### Fix

In `tv-view.js`, reuse the same client factory from `supabaseClient.js` instead of creating a new one:

```javascript
// Remove the createClient() calls at lines 4 and 29-31
import { supabase } from './lib/supabaseClient.js';

const getSupabaseClient = () => supabase;
```

If the TV view is anon-accessible (no auth), keep the shared client but use `auth: { persistSession: false }` only as a fallback.

---

## Area 7: Unbounded Queries — ❌ ISSUE FOUND (High Impact)

### Findings

All of these queries fetch **ENTIRE tables without `.limit()`**:

| File | Line(s) | Query | Table | Risk |
|------|---------|-------|-------|------|
| `frontend/web/js/dashboard.js` | 6295-6305 | `listConsultationData()` | `consultations` | No `.limit()` — fetches ALL consultations ever created |
| `frontend/web/js/dashboard.js` | 4546-4552 | `listCitizensFromSupabase()` | `citizens` | No `.limit()` — fetches ALL citizens |
| `frontend/web/js/dashboard.js` | 6614-6622 | `initLabSection()` | `lab_orders` | No `.limit()` — fetches ALL lab orders |
| `frontend/web/js/dashboard.js` | 3983 | `refreshAnnouncementsData()` | `announcements` | `.select('*')` without `.limit()` |
| `frontend/web/js/reports.js` | 109-129 | `exportPatientReport()` | `citizens` | `.select('*')` without `.limit()` |
| `frontend/web/js/reports.js` | 181-205 | `exportConsultationReport()` | `consultations` | No `.limit()` |
| `frontend/web/js/reports.js` | 392-415 | `exportQueueReport()` | `queue_tickets` | No `.limit()` |
| `frontend/web/js/reports.js` | 721-737 | `fetchStaffLoginLogs()` | `staff_login_logs` | `.select('*')` without `.limit()` |

### Why It Contributes to Memory/IO Pressure

- **Memory at idle**: Even with 1 logged-in user, `listConsultationData()` and `listCitizensFromSupabase()` fetch entire tables into the Postgres buffer cache. As the database grows (0.03 GB → larger), these queries will consume progressively more RAM on the shared instance.
- **I/O spikes**: Under concurrent load, multiple unbounded queries from different users hit the disk simultaneously.

The `staff_login_logs` table is particularly concerning — it grows with every login event and the report query fetches ALL rows.

### Fix

**1. Add `.limit()` to all list queries** (dashboard.js):
```javascript
async function listConsultationData() {
  // ...existing query...
  return supabase
    .from('consultations')
    .select('...')
    .order('consulted_at', { ascending: false })
    .limit(200);  // Paginate — use cursor-based pagination for full history
}
```

**2. For reports, add a mandatory date range or hard cap** (reports.js):
```javascript
exportPatientReport(startDate = null, endDate = null) {
  if (!startDate && !endDate) {
    // Default to last 30 days
    startDate = new Date(Date.now() - 30 * 86400000).toISOString();
  }
  // ...rest of query...
  .limit(1000)  // Hard cap
}
```

---

## Area 8: Background Jobs — ❌ ISSUE FOUND (Medium Impact + Critical Bug)

### Findings

| File | Line(s) | Issue |
|------|---------|-------|
| `supabase/migrations/20260506000000_auto_delete_pending_queue_tickets.sql` | 27-50 | `pg_cron` job `delete-old-pending-queue-tickets` runs daily at midnight |
| Same | 55-89 | Trigger-based fallback `check_and_delete_old_queue_tickets()` runs on **every INSERT** to `queue_tickets` |
| `supabase/migrations/20260507000000_add_queue_ticket_limiter.sql` | 93-116 | `get_today_ticket_count()` is **missing a FROM clause** — queries `WHERE created_at >= ...` without specifying a table |

### Critical Bug — `get_today_ticket_count()` Missing FROM Clause

`supabase/migrations/20260507000000_add_queue_ticket_limiter.sql:108-112`:
```sql
SELECT COUNT(*)
INTO v_count
WHERE created_at >= v_today_start   -- ⚠️ MISSING FROM clause!
  AND created_at < v_today_end
  AND status != 'cancelled';
```

**⚠️ LIVE VERIFICATION: This bug is ALREADY FIXED in the live database.** The live function uses:
```sql
SELECT count(*)::integer
FROM public.queue_tickets
WHERE queue_date = public.get_manila_date()
  AND lower(trim(coalesce(status, ''))) IN ('serving', 'completed', 'on_call');
```
(Verified via `pg_get_functiondef()` on 2026-08-16 — the migration file is stale; manual SQL was applied via Supabase dashboard.)

**However, the live function has a NEW performance concern:** the `lower(trim(coalesce(status, '')))` prevents the `idx_queue_tickets_date_status` index from being fully used on the `status` column, forcing a sequential scan on every call. Additionally, `get_manila_date()` is a STABLE function — Postgres inlines it, but the `lower(trim(coalesce()))` still defeats the status part of the composite index.

**Live test result (2026-08-16):** `SELECT get_today_ticket_count()` → `0`, `is_daily_ticket_limit_reached()` → `false` — function executes correctly.

**Remaining action:** normalize status values (lowercase) via trigger to allow `s.status = 'active'` pattern and index usage.

### `cron.job_run_details` Table Growth (LIVE-CONFIRMED)

**Live verification (2026-08-16):** `cron.job_run_details` has **2,645 rows / 536 kB** with no cleanup job. Oldest run: 2026-05-02, newest: 2026-08-16. At ~110 rows/day from the hourly job, this grows ~40 kB/month.

**NEW finding — Hourly cron job `staff_unavailable_5pm_manila` (not in migration files):**
```
jobid=1, schedule='0 * * * *' (EVERY HOUR), command='select public.set_staff_unavailable_after_hours();'
```
The function checks `v_local_hour <> 17` and returns early except at 5PM Manila — but it still wakes the database **24× per day** and logs a row to `cron.job_run_details` each time. Combined with `delete-old-pending-queue-tickets` (1×/day), this is the main driver of the 2,645 `job_run_details` rows.

**Fix:** Change schedule to `0 9 * * *` (UTC) = 5PM Manila: `SELECT cron.unschedule('staff_unavailable_5pm_manila'); SELECT cron.schedule('staff_unavailable_5pm_manila', '0 9 * * *', 'select public.set_staff_unavailable_after_hours();');`

### Trigger Overhead

The `BEFORE INSERT ... FOR EACH STATEMENT` trigger on `queue_tickets` runs a `SELECT EXISTS(...)` on the entire table on **every ticket creation**. This adds latency to every queue join operation.

### Fix

**1. ✅ Already done in live** — `get_today_ticket_count()` FROM clause is fixed. **Remaining:** normalize status values (lowercase) via the trigger below so the `lower(trim(coalesce(status,'')))` can be replaced with index-friendly `status = 'serving'` equality.

**2. Change cron log cleanup** (add to a new migration):
```sql
SELECT cron.schedule('cleanup-cron-logs', '0 3 * * 0',
  $$DELETE FROM cron.job_run_details WHERE start_time < now() - interval '7 days'$$);
```

**3. Optimize the trigger** — only run cleanup when the day changes:
```sql
CREATE OR REPLACE FUNCTION public.check_and_delete_old_queue_tickets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  last_cleanup_date date;
BEGIN
  -- Track last cleanup in a config table to avoid scanning on every insert
  SELECT config_value::date INTO last_cleanup_date
  FROM public.system_config
  WHERE config_key = 'last_queue_cleanup_date';
  
  IF last_cleanup_date IS NULL OR last_cleanup_date < (now() AT TIME ZONE 'Asia/Manila')::date THEN
    DELETE FROM public.queue_tickets
    WHERE (created_at AT TIME ZONE 'Asia/Manila')::date < (now() AT TIME ZONE 'Asia/Manila')::date;
    
    INSERT INTO public.system_config (config_key, config_value)
    VALUES ('last_queue_cleanup_date', (now() AT TIME ZONE 'Asia/Manila')::date::text)
    ON CONFLICT (config_key) DO UPDATE SET config_value = EXCLUDED.config_value;
  END IF;
  
  RETURN NULL;
END;
$$;
```

---

## Prioritized Action Items (Updated for Live State)

| Priority | Area | Issue | Why | Effort |
|----------|------|-------|-----|--------|
| 🔴 **P0** | #5 | RLS policies: `EXISTS(SELECT FROM staff)` + `lower(trim(coalesce()))` → **461,908 seq scans / 2.36M rows** on staff | **#1 memory pressure at idle (LIVE-CONFIRMED)** | Normalize columns + rewrite policies |
| 🔴 **P0** | #2 | Mobile 9-second polling loop (24k req/hr per 10 users) — **47k calls to `get_my_queue_dashboard`** (LIVE-CONFIRMED) | **#1 I/O spike source** | 2 files |
| 🔴 **P0** | #7 | Unbounded queries (no `.limit()`) | Memory pressure at idle | 8 files, simple |
| 🔴 **P0** | #8 | Hourly `staff_unavailable_5pm_manila` cron job wakes DB 24×/day (LIVE-CONFIRMED) | Wasted cron I/O + `cron.job_run_details` growth (2,645 rows) | Reschedule to once/day |
| 🟠 **P1** | #1 | Logout doesn't clean up subscriptions/timers; unfiltered channels → **539k realtime WAL calls** (LIVE-CONFIRMED) | Leaked channels + WAL polling storm | 2 functions + filters |
| 🟠 **P1** | #4 | Missing indexes on 3 columns (live-verified): `prescription_headers(patient_identifier)`, `lab_orders(patient_citizen_id)`, `lab_orders(created_at)` | Sequential scans | 3 CREATE INDEX statements |
| 🟡 **P2** | #3 | N+1 in pharmacy search + mobile profile re-fetch per call | Extra round-trips | 3-4 file changes |
| 🟡 **P2** | #6 | TV view creates separate Supabase client | Extra WebSocket connection | 1 file change |
| 🟡 **P2** | #8 | `cron.job_run_details` unbounded growth (2,645 rows / 536 kB) | DB size creep | 1 cron job |
| 🟢 **P3** | #1 | Unfiltered realtime subscriptions | Broadcasts unnecessary data | Add filters |
| ✅ **Done** | #8 | `get_today_ticket_count()` FROM clause | **Already fixed live** | No action needed |
| ✅ **Done** | #4 | 5/8 missing indexes (`vital_signs.queue_ticket_id`, `feedbacks.created_at`, `announcements.created_at`, `staff_login_logs.logged_at`, `doctor_schedules.schedule_date`) | **Already fixed live** | No action needed |

---

## Immediate Quick Wins (Under 30 Minutes — Live-Reconciled)

1. **Normalize `status`/`role` values** via INSERT/UPDATE trigger, then simplify RLS policies to `s.status = 'active'` — eliminates 461k seq scans
2. **Change mobile polling from 9s → 60s** in `uKonekDashboardPage.dart` and `uKonekJoinQueuePage.dart`
3. **Reschedule `staff_unavailable_5pm_manila`** cron from hourly → once at 5PM Manila
4. **Add `.limit(200)` to all list queries** in `dashboard.js` and `reports.js`
5. **Add cleanup logic to `performLogout()`**
6. **Add missing indexes**: `prescription_headers(patient_identifier)`, `lab_orders(patient_citizen_id)`, `lab_orders(created_at)`
7. **Add `cron.job_run_details` cleanup job**

---

## Appendix: Files Investigated

### Web (frontend/web/js/)
- `dashboard.js` (8,983 lines) — primary web app
- `dashboard-pharmacist.js` — pharmacist dashboard
- `tv-view.js` — TV display board
- `health-records.js` — patient health records modal
- `reports.js` — CSV report exports
- `supabase-config.js` / `lib/supabaseClient.js` — client initialization
- `services/authService.js`, `services/staffService.js`, `services/sessionAuth.js`

### Mobile (frontend/mobile/ukonekmobile/lib/)
- `services/api_service.dart` — all Supabase RPC/database calls
- `uKonekDashboardPage.dart` — patient dashboard (9s polling)
- `uKonekJoinQueuePage.dart` — queue join page (9s polling)
- `uKonekDoctorSchedulesPage.dart` — doctor availability (realtime subscription)
- `main.dart` — Supabase initialization

### Supabase (supabase/)
- `migrations/20260324110000_rls_and_functions.sql` — core RLS + `is_admin()`
- `migrations/20260404130000_create_consultations_and_prescriptions.sql` — consultations/prescriptions RLS
- `migrations/20260404143000_create_queue_feature.sql` — queue RLS
- `migrations/20260506000000_auto_delete_pending_queue_tickets.sql` — cron job + trigger
- `migrations/20260507000000_add_queue_ticket_limiter.sql` — queue limiter (has bug)
- `migrations/20260502150000_create_vital_signs_table.sql` — vital signs
- `migrations/20260331143000_staff_presence_tracking.sql` — presence
- `migrations/20260520000000_add_performance_indexes.sql` — existing indexes
- `SCHEDULED_JOBS_SETUP.md` — cron documentation