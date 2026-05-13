# System Check Report - Registration to Queue Ticket Flow

**Date**: May 11, 2026  
**Scope**: Full system validation from citizen registration to queue ticket creation  
**Status**: ⚠️ **ISSUES FOUND - REQUIRES FIXES**

---

## Executive Summary

Performed comprehensive analysis of the registration-to-queue-ticket flow across database schema, API functions, and mobile application. Found **3 critical issues** that will prevent the system from working correctly.

### Critical Issues Found:
1. ❌ **Database Schema Mismatch** - `queue_tickets.citizen_id` is BIGINT but functions expect UUID
2. ❌ **Multiple Function Definitions** - 4 different versions of `create_queue_ticket` function
3. ❌ **Registration Data Mismatch** - Mobile app collects `middle_initial` but database expects `middle_name`

---

## Detailed Analysis

### 1. Database Schema

#### Citizens Table ✅
```sql
CREATE TABLE public.citizens (
    id BIGINT PRIMARY KEY,                    -- ✅ Correct
    firstname VARCHAR(100) NOT NULL,          -- ✅ Correct
    surname VARCHAR(100) NOT NULL,            -- ✅ Correct
    middle_initial VARCHAR(100),              -- ⚠️ Mobile uses this
    date_of_birth DATE,                       -- ✅ Correct
    age INTEGER,                              -- ✅ Correct
    contact_number VARCHAR(30),               -- ✅ Correct
    sex VARCHAR(10),                          -- ✅ Correct
    email VARCHAR(100) NOT NULL UNIQUE,       -- ✅ Correct
    complete_address VARCHAR(255),            -- ✅ Correct
    emergency_contact_complete_name VARCHAR(200),  -- ✅ Correct
    emergency_contact_contact_number VARCHAR(30),  -- ✅ Correct
    relation VARCHAR(100),                    -- ✅ Correct
    username VARCHAR(100) UNIQUE,             -- ✅ Correct
    password_hash VARCHAR(255),               -- ✅ Correct
    role VARCHAR(50) DEFAULT 'citizen',       -- ✅ Correct
    auth_user_id UUID UNIQUE                  -- ✅ Correct
);
```

**Status**: ✅ Schema is correct

#### Queue Tickets Table ⚠️
```sql
CREATE TABLE public.queue_tickets (
    id BIGINT PRIMARY KEY,
    citizen_id BIGINT REFERENCES citizens(id),  -- ⚠️ BIGINT not UUID
    queue_number INTEGER NOT NULL,
    ticket_code TEXT NOT NULL UNIQUE,
    service_key TEXT NOT NULL,
    service_label TEXT NOT NULL,
    citizen_type TEXT NOT NULL,
    reason TEXT,
    symptoms TEXT,
    status TEXT DEFAULT 'waiting',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Status**: ⚠️ **ISSUE** - `citizen_id` is BIGINT (references citizens.id) but some function versions use UUID

---

### 2. Database Functions Analysis

#### Problem: Multiple Function Definitions

Found **4 different versions** of `create_queue_ticket` function across migrations:

1. **`20260507000000_add_queue_ticket_limiter.sql`** - Original with UUID (WRONG)
2. **`20260511000000_fix_create_queue_ticket_column.sql`** - Fixed column name but still UUID (WRONG)
3. **`20260511000001_fix_create_queue_ticket_types.sql`** - Fixed to BIGINT (CORRECT)
4. **`20260511000002_add_input_validation_system.sql`** - Added validation but reverted to UUID (WRONG)

#### Current Function Signature (Latest Migration)

```sql
-- From 20260511000002_add_input_validation_system.sql
CREATE OR REPLACE FUNCTION create_queue_ticket(
    p_service_key TEXT,
    p_service_label TEXT,
    p_citizen_type TEXT,
    p_reason TEXT,
    p_symptoms TEXT
)
RETURNS TABLE (
    id BIGINT,
    citizen_id UUID,  -- ❌ WRONG! Should be BIGINT
    ...
)
```

**Status**: ❌ **CRITICAL** - Latest migration reverted the fix and uses UUID instead of BIGINT

---

### 3. Mobile Application Flow

#### Registration Flow ✅

**Step 1: Personal Info Collection**
- ✅ First Name, Middle Name, Last Name, Name Extension
- ✅ Date of Birth, Age, Sex
- ✅ Collected in `uKonekRegisterWrapper.dart`

**Step 2: Contact & Address**
- ✅ Contact Number, Email
- ✅ House Number, Street Name, Barangay
- ✅ Emergency Contact Info

**Step 3: Preview & Verify**
- ✅ Shows all collected data
- ✅ Navigates to OTP verification

**Step 4: OTP Verification**
- ✅ Sends OTP via `startCitizenEmailVerification()`
- ✅ Verifies email using Supabase Auth

**Step 5: Complete Registration**
- ✅ Calls `completeCitizenRegistration()`
- ✅ Creates citizen profile via `complete_my_citizen_profile` RPC

**Status**: ✅ Registration flow is correct

#### Queue Ticket Creation Flow ⚠️

**Mobile App Call:**
```dart
await _client.rpc(
  'create_queue_ticket',
  params: {
    'p_service_key': request.serviceKey.trim(),
    'p_service_label': request.serviceLabel.trim(),
    'p_citizen_type': citizenType,
    'p_reason': request.reason.trim(),
    'p_symptoms': request.symptoms.trim(),
  },
);
```

**Expected Function Behavior:**
1. Get citizen_id (BIGINT) from auth.uid()
2. Validate daily limit
3. Generate queue number
4. Insert ticket
5. Return ticket data

**Status**: ⚠️ **WILL FAIL** - Function returns UUID but table expects BIGINT

---

## Issues Summary

### Issue #1: Data Type Mismatch ❌

**Problem**: `create_queue_ticket` function returns `citizen_id` as UUID but the table column is BIGINT.

**Impact**: 
- Queue ticket creation will fail with type mismatch error
- Mobile app cannot create tickets
- System is non-functional

**Location**: `supabase/migrations/20260511000002_add_input_validation_system.sql`

**Fix Required**: Update function to return BIGINT for citizen_id

---

### Issue #2: Multiple Function Versions ❌

**Problem**: 4 different versions of the same function across migrations, causing confusion and potential conflicts.

**Impact**:
- Last migration wins, but it has the wrong type
- Difficult to track which version is active
- Migration order matters

**Location**: Multiple migration files

**Fix Required**: Consolidate into single correct version

---

### Issue #3: Registration Field Name Inconsistency ⚠️

**Problem**: Mobile app collects `middle_initial` but some documentation refers to `middle_name`.

**Impact**: 
- Minor - both work since column is `middle_initial`
- Could cause confusion in future

**Location**: Mobile registration forms

**Fix Required**: Ensure consistency in naming

---

## Recommended Fixes

### Fix #1: Correct create_queue_ticket Function (CRITICAL)

Create a new migration that definitively fixes the function:

```sql
-- File: supabase/migrations/20260511000003_fix_queue_ticket_final.sql

DROP FUNCTION IF EXISTS create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_queue_ticket(
    p_service_key TEXT,
    p_service_label TEXT,
    p_citizen_type TEXT,
    p_reason TEXT,
    p_symptoms TEXT
)
RETURNS TABLE (
    id BIGINT,
    citizen_id BIGINT,  -- ✅ FIXED: Changed from UUID to BIGINT
    queue_number INTEGER,
    ticket_code TEXT,
    service_key TEXT,
    service_label TEXT,
    citizen_type TEXT,
    reason TEXT,
    symptoms TEXT,
    status TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_citizen_id BIGINT;  -- ✅ FIXED: Changed from UUID to BIGINT
    v_queue_number INTEGER;
    v_ticket_code TEXT;
    v_new_ticket_id BIGINT;
    v_limit_reached BOOLEAN;
    v_service_key TEXT;
    v_service_label TEXT;
    v_citizen_type TEXT;
    v_reason TEXT;
    v_symptoms TEXT;
BEGIN
    -- Validate and sanitize all inputs
    v_service_key := validate_required_text(p_service_key, 'Service key');
    v_service_label := validate_required_text(p_service_label, 'Service label');
    v_citizen_type := validate_required_text(p_citizen_type, 'Citizen type');
    v_reason := validate_text_input(p_reason);
    v_symptoms := validate_text_input(p_symptoms);

    -- Get the authenticated user's citizen_id (BIGINT)
    SELECT c.id INTO v_citizen_id
    FROM public.citizens c
    WHERE c.auth_user_id = auth.uid();

    IF v_citizen_id IS NULL THEN
        RAISE EXCEPTION 'Citizen profile not found for the authenticated user.';
    END IF;

    -- Check if citizen already has an active queue ticket today
    IF EXISTS (
        SELECT 1
        FROM public.queue_tickets qt
        WHERE qt.citizen_id = v_citizen_id
          AND qt.status IN ('waiting', 'on_call', 'serving')
          AND DATE(qt.created_at) = CURRENT_DATE
    ) THEN
        RAISE EXCEPTION 'You already have an active queue ticket for today.';
    END IF;

    -- Check if daily ticket limit is reached
    v_limit_reached := is_daily_ticket_limit_reached();
    
    IF v_limit_reached THEN
        RAISE EXCEPTION 'Daily queue ticket limit reached. Consultations for today are full. Please try again tomorrow or contact the clinic for assistance.';
    END IF;

    -- Generate the next queue number for today
    SELECT COALESCE(MAX(queue_number), 0) + 1
    INTO v_queue_number
    FROM public.queue_tickets
    WHERE DATE(created_at) = CURRENT_DATE;

    -- Generate a unique ticket code
    v_ticket_code := 'TKT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(v_queue_number::TEXT, 3, '0');

    -- Insert the new queue ticket
    INSERT INTO public.queue_tickets (
        citizen_id,
        queue_number,
        ticket_code,
        service_key,
        service_label,
        citizen_type,
        reason,
        symptoms,
        status
    )
    VALUES (
        v_citizen_id,
        v_queue_number,
        v_ticket_code,
        v_service_key,
        v_service_label,
        v_citizen_type,
        v_reason,
        v_symptoms,
        'waiting'
    )
    RETURNING queue_tickets.id INTO v_new_ticket_id;

    -- Return the newly created ticket
    RETURN QUERY
    SELECT
        qt.id,
        qt.citizen_id,
        qt.queue_number,
        qt.ticket_code,
        qt.service_key,
        qt.service_label,
        qt.citizen_type,
        qt.reason,
        qt.symptoms,
        qt.status,
        qt.created_at
    FROM public.queue_tickets qt
    WHERE qt.id = v_new_ticket_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION create_queue_ticket(TEXT, TEXT, TEXT, TEXT, TEXT) IS 
  'Creates a new queue ticket with validation and daily limit check. Returns BIGINT citizen_id to match table schema.';
```

### Fix #2: Verify complete_my_citizen_profile Function

Ensure this function exists and works correctly:

```sql
-- Check if function exists
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_name = 'complete_my_citizen_profile'
  AND routine_schema = 'public';
```

---

## Testing Checklist

### Database Tests

```sql
-- Test 1: Verify citizens table structure
\d public.citizens

-- Test 2: Verify queue_tickets table structure
\d public.queue_tickets

-- Test 3: Test create_queue_ticket function
SELECT * FROM create_queue_ticket(
    'consultation',
    'General Consultation',
    'regular',
    'Checkup',
    'None'
);

-- Test 4: Verify validation functions exist
SELECT routine_name FROM information_schema.routines
WHERE routine_name IN (
    'validate_text_input',
    'validate_required_text',
    'validate_email',
    'validate_phone_number'
);

-- Test 5: Check queue limiter functions
SELECT * FROM get_queue_limiter_status();
```

### Mobile App Tests

1. **Registration Flow**
   - [ ] Fill registration form with valid data
   - [ ] Submit and verify OTP sent
   - [ ] Enter OTP and complete registration
   - [ ] Verify citizen profile created
   - [ ] Verify can login with credentials

2. **Queue Ticket Creation**
   - [ ] Login as registered citizen
   - [ ] Navigate to queue ticket page
   - [ ] Select service type
   - [ ] Fill reason and symptoms
   - [ ] Submit ticket
   - [ ] Verify ticket created successfully
   - [ ] Verify ticket appears in dashboard

3. **Edge Cases**
   - [ ] Try creating second ticket same day (should fail)
   - [ ] Try with whitespace-only inputs (should fail)
   - [ ] Try when daily limit reached (should fail)
   - [ ] Try with invalid citizen type (should fail)

---

## Deployment Steps

1. **Apply Fix Migration**
   ```bash
   supabase db push
   ```

2. **Verify Functions**
   ```sql
   -- Check function signature
   \df create_queue_ticket
   
   -- Test function
   SELECT * FROM create_queue_ticket(
       'test', 'Test Service', 'regular', 'Test', 'None'
   );
   ```

3. **Test Mobile App**
   - Complete full registration flow
   - Create queue ticket
   - Verify data in database

4. **Monitor Logs**
   - Check Supabase logs for errors
   - Monitor mobile app error reports
   - Verify no type mismatch errors

---

## Conclusion

**Current Status**: ❌ **SYSTEM WILL NOT WORK**

**Reason**: Critical data type mismatch in `create_queue_ticket` function

**Action Required**: Apply Fix #1 immediately before testing

**Estimated Fix Time**: 5 minutes

**Risk Level**: HIGH - System is non-functional until fixed

---

## Next Steps

1. ✅ Create fix migration (20260511000003_fix_queue_ticket_final.sql)
2. ⏳ Apply migration (`supabase db push`)
3. ⏳ Test registration flow
4. ⏳ Test queue ticket creation
5. ⏳ Verify all validation rules work
6. ⏳ Deploy to production

---

**Report Generated**: May 11, 2026  
**Analyst**: System Check Automation  
**Priority**: CRITICAL
