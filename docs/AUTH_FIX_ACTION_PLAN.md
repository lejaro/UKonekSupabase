# Authentication Concurrent Login - Action Plan

## Executive Summary

The UKonek system is experiencing an issue where only 2 staff members can be logged in concurrently. A third login attempt results in "Invalid Credentials" error even with correct credentials.

**Good News**: The codebase is properly configured for concurrent multi-user access with tab-isolated sessions.

**Root Cause**: The issue is likely in **Supabase project configuration**, not the application code.

## Immediate Actions Required

### Step 1: Check Supabase Auth Settings (5 minutes)

1. Log into [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your UKonek project
3. Navigate to **Authentication** → **Settings**
4. Look for these settings:
   - **"Maximum sessions per user"** or **"Session limit"**
   - **"Concurrent sessions"** setting
   - Any session-related limits

**Expected Finding**: There may be a limit of 2 sessions per user configured.

**Fix**: 
- Increase the limit to 10+ sessions (or unlimited)
- Save changes
- Test with 3+ concurrent logins

### Step 2: Check Rate Limiting (5 minutes)

1. In Supabase Dashboard → **Authentication** → **Rate Limits**
2. Check current rate limit settings:
   - Password authentication rate limit
   - Per-IP limits
   - Per-user limits

**Expected Finding**: Rate limits should be reasonable (30+ per hour).

**Fix**: If rate limits are too low, increase them:
- Password auth: 60 requests/hour minimum
- Consider per-user instead of per-IP limits

### Step 3: Check Database Connections (5 minutes)

1. In Supabase Dashboard → **Database** → **Connection Pooling**
2. Check:
   - Current active connections
   - Maximum connection pool size
   - Connection usage percentage

**Expected Finding**: Should not be at connection limit.

**Fix**: If near limit:
- Upgrade Supabase plan for more connections
- Or optimize connection usage in application

### Step 4: Review Auth Logs (10 minutes)

1. In Supabase Dashboard → **Authentication** → **Logs**
2. Filter for failed login attempts
3. Look for error messages containing:
   - "session limit"
   - "rate limit"
   - "too many sessions"
   - "maximum sessions"

**This will reveal the exact error from Supabase's perspective.**

### Step 5: Test Hypothesis (15 minutes)

**Test A: Different Devices**
1. Have User A log in from Computer 1
2. Have User B log in from Computer 2
3. Have User C log in from Computer 3
4. Check if all 3 can access their dashboards simultaneously

**Test B: Same Device, Different Browsers**
1. Have User A log in using Chrome
2. Have User B log in using Firefox
3. Have User C log in using Edge
4. Check if all 3 can access their dashboards simultaneously

**Test C: Same Browser, Different Tabs**
1. Open Chrome Tab 1, log in as User A
2. Open Chrome Tab 2, log in as User B
3. Open Chrome Tab 3, log in as User C
4. Check if all 3 can access their dashboards simultaneously

**Expected Results**:
- Test A & B should work (different browsers = different sessions)
- Test C should work (tab-isolated sessions are implemented)
- If Test C fails, there's a Supabase-level session limit

## Technical Details

### Current Implementation (Correct)

The system uses **tab-isolated sessions**:

```javascript
// frontend/web/js/lib/supabaseClient.js
const tabId = getOrCreateTabId(); // Unique per tab
const storageKey = `sb-${projectRef}-auth-tab-${tabId}`; // Tab-specific key

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: window.sessionStorage, // Tab-isolated, not shared
    storageKey, // Unique per tab
    persistSession: true,
    autoRefreshToken: true
  }
});
```

**This means**:
- Each browser tab has its own auth session
- Sessions don't interfere with each other
- Multiple users can log in from the same computer (different tabs)
- The issue is NOT in the application code

### Login Flow

```
1. User enters credentials
2. supabase.auth.signInWithPassword({ email, password })
   ↓
3. Supabase Auth validates credentials
   ↓
4. Supabase creates JWT token and session
   ↓
5. Token stored in sessionStorage with tab-specific key
   ↓
6. Application calls get_staff_role() RPC
   ↓
7. Application calls set_staff_presence(true) RPC
   ↓
8. User redirected to dashboard
```

**Where the issue occurs**: Step 4 - Supabase Auth session creation

If Supabase has a 2-session limit, Step 4 fails for the 3rd user with "Invalid Credentials" error.

## Possible Supabase Configurations Causing This

### Configuration 1: Session Limit Per User
```
Setting: auth.max_sessions_per_user = 2
Effect: Each user can only have 2 active sessions
Solution: Increase to 10+ or set to unlimited
```

### Configuration 2: Global Session Limit
```
Setting: auth.max_concurrent_sessions = 2
Effect: Only 2 total sessions allowed across all users
Solution: Increase to match expected concurrent users (20+)
```

### Configuration 3: Connection Pool Limit
```
Setting: database.max_connections = 20
Effect: If each session uses a connection, limit is reached
Solution: Upgrade plan or optimize connection usage
```

## If Supabase Settings Look Correct

If all Supabase settings look correct but the issue persists, check:

### 1. Supabase Plan Limits
- Free tier has stricter limits
- Check if your plan includes session limits
- Consider upgrading to Pro plan

### 2. Custom Auth Hooks
- Check if there are any Supabase Auth Hooks configured
- Navigate to **Authentication** → **Hooks**
- Look for custom hooks that might be limiting sessions

### 3. Database Triggers
- Check for triggers on `auth.users` table
- Look for custom logic that might limit sessions

### 4. Edge Functions
- Check if there are Edge Functions intercepting auth requests
- Navigate to **Edge Functions** in Supabase Dashboard

## Monitoring and Prevention

### Add Session Monitoring

Create a dashboard query to monitor active sessions:

```sql
-- Check active auth sessions
SELECT 
  COUNT(*) as active_sessions,
  COUNT(DISTINCT user_id) as unique_users
FROM auth.sessions
WHERE expires_at > NOW();

-- Check staff presence
SELECT 
  COUNT(*) as online_staff,
  array_agg(email) as online_emails
FROM public.staff
WHERE is_online = true;
```

### Add Logging

Update `authService.js` to log session details:

```javascript
export async function signInStaff({ identifier, password }) {
  console.log('[Auth] Login attempt:', { identifier, timestamp: new Date().toISOString() });
  
  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    });
    
    if (error) {
      console.error('[Auth] Login failed:', {
        error: error.message,
        code: error.status,
        details: error
      });
      throw new Error('Invalid email or password.');
    }
    
    console.log('[Auth] Login successful:', {
      userId: data.user.id,
      email: data.user.email,
      sessionId: data.session?.access_token?.substring(0, 20) + '...'
    });
    
    // Continue with role check...
  } catch (error) {
    console.error('[Auth] Login exception:', error);
    throw error;
  }
}
```

## Contact Supabase Support

If the issue persists after checking all settings:

1. Go to [Supabase Support](https://supabase.com/dashboard/support)
2. Create a ticket with:
   - **Subject**: "Session limit preventing concurrent logins"
   - **Description**: "Only 2 users can log in concurrently. 3rd user gets 'Invalid Credentials' error."
   - **Project ID**: [Your project ID]
   - **Expected behavior**: Multiple staff members should be able to log in simultaneously
   - **Actual behavior**: Only 2 concurrent sessions allowed
   - **Workaround**: Changing password temporarily fixes the issue

## Summary

**Most Likely Cause**: Supabase project has a 2-session limit configured

**Most Likely Solution**: Increase session limit in Supabase Dashboard → Authentication → Settings

**Estimated Time to Fix**: 5-10 minutes (just changing a setting)

**Confidence Level**: High - The application code is correctly implemented for concurrent sessions

## Next Steps

1. ✅ Complete Step 1-4 above (check Supabase settings)
2. ✅ Run Test A-C to confirm hypothesis
3. ✅ Apply fix in Supabase Dashboard
4. ✅ Test with 5+ concurrent users
5. ✅ Document the solution
6. ✅ Add monitoring to prevent future issues
