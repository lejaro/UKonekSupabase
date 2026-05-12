# Queue Section Fix - Direct Query Implementation

## Issue
Queue tickets were not visible in the web dashboard queue section, even though the Vitals Assessment section could fetch them successfully.

## Root Cause
The Queue Management section was using an RPC function (`list_queue_tickets_for_staff`) that may not exist or have permission issues, while the Vitals Assessment section was using a direct Supabase query that worked correctly.

## Solution
Changed the Queue Management section to use the **same direct query approach** as the Vitals Assessment section.

## Changes Made

### File: `frontend/web/js/appointments.js`

#### **loadQueueTickets() function - Complete Rewrite**

**Before:** Used RPC function with complex fallback logic
```javascript
// Attempted RPC call first
const rpc = await supabase.rpc('list_queue_tickets_for_staff', {...});
// Then fell back to direct query if RPC failed
// Then tried 24h fallback with RPC
// Then tried all active with RPC
```

**After:** Uses direct query (same as vitals section)
```javascript
// Direct query to queue_tickets table
const { data, error } = await supabase
  .from('queue_tickets')
  .select(queryStr)
  .eq('queue_date', today)
  .not('status', 'in', '("cancelled","completed")')
  .order('queue_number', { ascending: true });
```

### Key Improvements

1. **Consistency** - Now uses the same query method as Vitals Assessment
2. **Simplicity** - Removed complex RPC mapping and multiple fallback attempts
3. **Reliability** - Direct queries work with standard RLS policies
4. **Performance** - Fewer database calls, faster response

### Query Logic

1. **First attempt**: Load today's active tickets (not cancelled/completed)
2. **Fallback**: If no tickets today, load all active tickets (no date filter)

## Why This Works

The Vitals Assessment section successfully fetches queue tickets using:
```javascript
await supabase
  .from('queue_tickets')
  .select(`...`)
  .eq('queue_date', new Date().toISOString().split('T')[0])
  .in('status', ['waiting', 'on_call'])
```

The Queue Management section now uses the same approach, ensuring consistent behavior across the application.

## Testing

1. Open the web dashboard
2. Navigate to the Queue section
3. Tickets should now be visible
4. Console logs will show:
   ```
   [Queue] Loading tickets for date: 2026-05-11
   [Queue] Fetching tickets with direct query
   [Queue] Direct query returned X tickets
   [Queue] Final ticket count: X
   [Queue] Rendering queue with X total tickets
   ```

## Diagnostic Logging

Comprehensive logging has been added to help diagnose any future issues:

- **init()** - Shows initialization status
- **loadQueueTickets()** - Shows query attempts and results
- **renderQueue()** - Shows ticket distribution across lanes
- **renderLaneCards()** - Shows DOM element creation

## Rollback

If issues occur, the RPC-based approach can be restored from git history. However, the direct query approach is recommended as it:
- Matches the working vitals section implementation
- Requires no special database functions
- Works with standard RLS policies
- Is easier to debug and maintain
