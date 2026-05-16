# Authentication Concurrent Login Investigation

## Issue Summary
**Problem**: Only two staff accounts can stay logged in concurrently. When a third staff member attempts to log in, the system returns an "Invalid Credentials" error even with correct credentials.

**Temporary Workaround**: Manually changing the affected user's password in staff management allows login again until concurrent users reach two accounts.

## Investigation Findings

## Investigation Findings - UPDATE

### CRITICAL DISCOVERY: System Already Uses Tab-Isolated Sessions!

**The authentication system is ALREADY properly configured for concurrent multi-user access:**

1. **sessionStorage** is used (not localStorage) - tab-isolated by default
2. **Unique tab IDs** are generated per browser tab via `crypto.randomUUID()`
3. **Tab-specific storage keys**: `sb-${projectRef}-auth-tab-${tabId}`
4. Each tab maintains its own independent Supabase auth session

**This means the "2 concurrent users" issue is NOT caused by browser storage conflicts.**

### Revised Root Cause Analysis

Since the system is properly configured for concurrent sessions, the issue must be:

#### A. Supabase Project Configuration (MOST LIKELY)
**Hypothesis**: The Supabase project has a session limit configured at the project level.

**Check Required**:
1. Log into Supabase Dashboard → Project Settings → Auth
2. Look for "Maximum number of sessions per user" or similar setting
3. Check if there's a limit of 2 sessions per user
4. This would be a Supabase Auth configuration, not a code issue

**Solution**: Increase or remove the session limit in Supabase project settings.

#### B. Database Connection Pool Limits
**Hypothesis**: The database connection pool might be limiting concurrent connections.

**Evidence**:
- Supabase has connection pool limits
- Default pool size varies by plan (Free tier: 60 connections)
- Each active session uses a connection

**Check Required**:
1. Review Supabase Dashboard → Database → Connection Pooling
2. Check current connection usage
3. Check if connection limit is being reached

**Solution**: Upgrade Supabase plan or optimize connection usage.

#### C. RPC Function Constraints
**Hypothesis**: The `get_staff_role()` or `set_staff_presence()` RPC functions might have constraints.

**Evidence from login flow**:
```javascript
// During login:
1. supabase.auth.signInWithPassword() - Creates auth session
2. supabase.rpc('get_staff_role') - Checks staff status
3. supabase.rpc('set_staff_presence', { p_is_online: true }) - Updates presence
```

**Possible Issues**:
- `set_staff_presence` might be using a transaction lock
- Multiple concurrent calls might be causing deadlocks
- The `is_online` flag might have a constraint

**Check Required**:
1. Review the RPC function definitions in migrations
2. Check for any locks or constraints on `staff.is_online`
3. Test if removing presence update allows more concurrent logins

#### D. Auth Provider Rate Limiting
**Hypothesis**: Supabase Auth might be rate-limiting login attempts.

**Evidence**:
- Supabase has built-in rate limiting for auth endpoints
- Default: 30 requests per hour per IP for password auth
- Exceeding this returns "Invalid Credentials" error

**Check Required**:
1. Review Supabase Dashboard → Auth → Rate Limits
2. Check if rate limit is being hit
3. Review auth logs for rate limit errors

**Solution**: Adjust rate limits in Supabase settings.

### 1. Current Authentication Architecture

#### Frontend Authentication Flow (`frontend/web/js/services/authService.js`)
```javascript
// Login process:
1. Resolve email from identifier
2. Call supabase.auth.signInWithPassword({ email, password })
3. Check staff role via RPC: supabase.rpc('get_staff_role')
4. If not staff, sign out immediately
5. Update staff presence: supabase.rpc('set_staff_presence', { p_is_online: true })
6. Store role in sessionStorage
7. Redirect to dashboard
```

#### Session Storage
- Uses `sessionStorage.setItem('ukonek_role', role)`
- Session data is browser-tab specific (not shared across tabs/windows)
- Each browser tab maintains its own session

#### Supabase Auth
- Uses Supabase's built-in authentication (`supabase.auth.signInWithPassword`)
- Supabase Auth manages JWT tokens and sessions
- Tokens are stored in browser localStorage by default
- Each login creates a new auth session

### 2. Potential Root Causes

#### A. Supabase Auth Session Limits (MOST LIKELY)
**Hypothesis**: Supabase may have a default concurrent session limit per user.

**Evidence**:
- Supabase Auth allows multiple sessions per user by default
- However, some Supabase projects may have session limits configured
- The "2 concurrent users" pattern suggests a hard limit

**Check Required**:
1. Review Supabase project settings for session limits
2. Check if "Limit number of sessions per user" is enabled
3. Review Supabase Auth configuration in dashboard

#### B. Database Constraint on auth_user_id
**Hypothesis**: The `staff.auth_user_id` column might have constraints causing conflicts.

**Evidence from DATA_DICTIONARY.md**:
```sql
auth_user_id uuid unique  -- Links to auth.users.id
```

**Analysis**:
- The `auth_user_id` is UNIQUE per staff member (correct)
- This should NOT prevent concurrent logins
- Each staff member has their own unique auth_user_id
- Multiple sessions for the same user should share the same auth_user_id

**Conclusion**: This is NOT the root cause.

#### C. RLS (Row Level Security) Policies
**Hypothesis**: RLS policies might be blocking authentication after 2 concurrent sessions.

**Evidence**:
- RLS is enabled on staff table
- Policies check for active staff status
- `get_staff_role()` RPC is called during login

**Analysis**:
- RLS policies affect data access, not authentication
- If RLS was the issue, users would get "permission denied" not "invalid credentials"
- The error message "Invalid Credentials" comes from `signInWithPassword`, not RLS

**Conclusion**: This is NOT the root cause.

#### D. Browser Storage Conflicts
**Hypothesis**: localStorage conflicts when multiple users log in from the same browser.

**Evidence**:
- Supabase stores auth tokens in localStorage
- localStorage is shared across all tabs in the same browser
- When User A logs in, their token is stored
- When User B logs in from another tab, User B's token overwrites User A's token
- User A's session becomes invalid

**Analysis**:
- This would explain why only 2 users can be logged in
- If users are testing from the same browser/computer, this is the issue
- Each new login overwrites the previous user's token in localStorage

**Test**: Have users log in from completely different computers/browsers

#### E. Password Reset Token Conflicts
**Hypothesis**: The password reset mechanism might be interfering with active sessions.

**Evidence from staff table**:
```sql
password_reset_token_hash varchar(64)
password_reset_token_expires timestamptz
password_reset_otp_hash varchar(64)
password_reset_otp_expires timestamptz
password_reset_otp_attempts_left integer default 5
```

**Analysis**:
- These fields are for password reset functionality
- They should NOT affect normal login
- The workaround (changing password) might be clearing these fields

**Conclusion**: Unlikely to be the root cause.

#### F. Presence System Conflicts
**Hypothesis**: The `set_staff_presence` RPC might be causing issues.

**Evidence**:
```javascript
// Called on login
await supabase.rpc('set_staff_presence', { p_is_online: true });

// Staff table has:
is_online boolean default false
last_seen timestamptz
```

**Analysis**:
- Presence system tracks who is online
- Should NOT prevent login
- Errors in presence update are caught and logged as warnings
- If presence RPC failed, login would still succeed

**Conclusion**: This is NOT the root cause.

### 3. Most Likely Root Cause: Browser Storage Isolation

**The Issue**:
When multiple staff members log in from the same browser (different tabs), Supabase Auth stores the session token in localStorage, which is shared across all tabs. Each new login overwrites the previous session token, invalidating the previous user's session.

**Why "Invalid Credentials" Error**:
1. User A logs in → Token A stored in localStorage
2. User B logs in from another tab → Token B overwrites Token A in localStorage
3. User A tries to access dashboard → Uses Token B (wrong user) → Auth fails
4. User A tries to log in again → Supabase sees an active session for User B → Returns "Invalid Credentials"

**Why Password Reset Works**:
Changing the password forces a complete session reset, clearing all tokens and allowing a fresh login.

### 4. Recommended Solutions

#### Solution 1: Use Different Browsers/Devices (Immediate)
**Action**: Ensure each staff member logs in from their own device or browser profile.

**Implementation**:
- Staff should NOT share computers for concurrent work
- If sharing is necessary, use different browser profiles (Chrome profiles, Firefox containers)
- Each browser profile has isolated localStorage

#### Solution 2: Implement Proper Multi-User Support (Long-term)
**Action**: Modify the authentication system to support multiple concurrent users on the same device.

**Implementation Options**:

**Option A: Use Supabase's Multi-Session Support**
```javascript
// Configure Supabase client to use sessionStorage instead of localStorage
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: window.sessionStorage, // Tab-isolated storage
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false
  }
});
```

**Option B: Implement Session Namespacing**
```javascript
// Create a custom storage adapter that namespaces by user
class NamespacedStorage {
  constructor(userId) {
    this.prefix = `ukonek_${userId}_`;
  }
  
  getItem(key) {
    return localStorage.getItem(this.prefix + key);
  }
  
  setItem(key, value) {
    localStorage.setItem(this.prefix + key, value);
  }
  
  removeItem(key) {
    localStorage.removeItem(this.prefix + key);
  }
}
```

**Option C: Server-Side Session Management**
- Implement the backend examples in `backend/examples/`
- Use httpOnly cookies for session tokens
- Server validates sessions on each request
- Multiple users can have separate cookie-based sessions

#### Solution 3: Add Session Conflict Detection
**Action**: Detect when a session conflict occurs and provide a clear error message.

**Implementation**:
```javascript
// In authService.js
export async function signInStaff({ identifier, password }) {
  // Check if another user is already logged in
  const existingSession = await supabase.auth.getSession();
  if (existingSession?.data?.session) {
    const existingProfile = await getAuthenticatedStaffProfile();
    if (existingProfile && existingProfile.email !== email) {
      throw new Error(
        `Another user (${existingProfile.email}) is currently logged in. ` +
        `Please log them out first or use a different browser/profile.`
      );
    }
  }
  
  // Continue with normal login...
}
```

### 5. Testing Plan

#### Test 1: Confirm Browser Storage Issue
1. Open Browser A (Chrome)
2. Log in as User A
3. Open Browser B (Firefox) on the same computer
4. Log in as User B
5. Open Browser C (Edge) on the same computer
6. Log in as User C
7. **Expected**: All three users should remain logged in
8. **If this works**: The issue is browser storage isolation

#### Test 2: Confirm Same-Browser Conflict
1. Open Chrome
2. Log in as User A in Tab 1
3. Open Tab 2 in the same Chrome window
4. Log in as User B in Tab 2
5. Go back to Tab 1 and try to use the dashboard
6. **Expected**: User A's session should be invalid
7. **If this happens**: Confirms localStorage conflict

#### Test 3: Test sessionStorage Solution
1. Modify `supabaseClient.js` to use sessionStorage
2. Repeat Test 2
3. **Expected**: Both users should remain logged in in their respective tabs

### 6. Immediate Action Items

1. **Verify the issue is browser-related**:
   - Have users test from completely different devices
   - If this works, the issue is confirmed as browser storage

2. **Implement sessionStorage solution**:
   - Modify `frontend/web/js/lib/supabaseClient.js`
   - Change auth storage from localStorage to sessionStorage
   - Test with multiple concurrent logins

3. **Add session conflict detection**:
   - Update `authService.js` to detect existing sessions
   - Provide clear error messages to users

4. **Document best practices**:
   - Create user guide for staff
   - Explain that each staff member should use their own device/browser profile

### 7. Files to Modify

1. `frontend/web/js/lib/supabaseClient.js` - Change auth storage
2. `frontend/web/js/services/authService.js` - Add session conflict detection
3. `frontend/web/js/script.js` - Update error messages
4. `docs/STAFF_LOGIN_GUIDE.md` - Create user documentation

## Conclusion

The most likely root cause is **browser localStorage conflicts** when multiple users attempt to log in from the same browser. The solution is to either:
1. Use sessionStorage for tab-isolated sessions (recommended)
2. Ensure each staff member uses their own device/browser profile
3. Implement server-side session management with httpOnly cookies

The "2 concurrent users" limit is likely an artifact of testing with 2 browser tabs, then trying a 3rd tab which overwrites one of the previous sessions.
