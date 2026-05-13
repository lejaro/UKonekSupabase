# Queue Section Testing Guide

## Quick Test Steps

### 1. Open the Application
1. Navigate to `frontend/web/html/index.html` in your browser
2. Log in with a doctor or staff account
3. Open the browser Developer Console (F12 or Ctrl+Shift+I)

### 2. Navigate to Queue Section
1. Click on "Queue" in the left sidebar navigation
2. Watch the console for `[Queue]` log messages

### 3. Check Console Output

#### Successful Load Example:
```
[Queue] Initializing queue module...
[Queue] Loading tickets for date: 2026-05-11
[Queue] Attempting RPC call: list_queue_tickets_for_staff
[Queue] RPC returned 5 tickets
[Queue] Final ticket count: 5
[Queue] Rendering queue with 5 total tickets
[Queue] Buckets: { waiting: 3, onCall: 1, serving: 1 }
[Queue] Rendering 3 tickets in lane: waiting
[Queue] Rendered 3 elements in queue-waiting-list
[Queue] Rendering 1 tickets in lane: on_call
[Queue] Rendered 1 elements in queue-oncall-list
[Queue] Rendering 1 tickets in lane: serving
[Queue] Rendered 1 elements in queue-serving-list
[Queue] Initialization complete
```

#### No Tickets Example:
```
[Queue] Initializing queue module...
[Queue] Loading tickets for date: 2026-05-11
[Queue] Attempting RPC call: list_queue_tickets_for_staff
[Queue] RPC returned 0 tickets
[Queue] No tickets for today, attempting fallback to recent active tickets (last 24h)...
[Queue] 24h fallback returned 0 tickets
[Queue] Still no tickets after 24h fallback, loading all active tickets...
[Queue] All active tickets returned 0 tickets
[Queue] Final ticket count: 0
[Queue] Rendering queue with 0 total tickets
[Queue] Buckets: { waiting: 0, onCall: 0, serving: 0 }
[Queue] Rendering 0 tickets in lane: waiting
[Queue] Rendered 1 elements in queue-waiting-list
```

### 4. Common Issues and Solutions

#### Issue: No `[Queue]` logs appear
**Cause**: JavaScript error preventing module load
**Solution**: 
- Check console for JavaScript errors
- Verify `appointments.js` is loaded (check Network tab)
- Check if `appointments` object exists: type `appointments` in console

#### Issue: "Container not found" warnings
**Cause**: HTML structure missing required elements
**Solution**:
- Verify queue section HTML has these IDs:
  - `queue-waiting-list`
  - `queue-oncall-list`
  - `queue-serving-list`

#### Issue: RPC error in logs
**Cause**: Database permission or authentication issue
**Solution**:
- Verify user is logged in
- Check database RLS policies
- Verify `list_queue_tickets_for_staff` function exists
- Check user has `authenticated` role

#### Issue: "Final ticket count: 0" but tickets exist
**Cause**: Date mismatch or status filter
**Solution**:
- Check `queue_date` in database matches today's date
- Verify ticket `status` is not 'cancelled' or 'completed'
- Check if tickets have correct status values: 'waiting', 'on_call', or 'serving'

### 5. Manual Ticket Creation (for testing)

If no tickets exist, you can create test tickets using SQL:

```sql
-- Insert a test citizen (if needed)
INSERT INTO citizens (firstname, surname, email, date_of_birth, sex)
VALUES ('Test', 'Patient', 'test@example.com', '1990-01-01', 'Male')
RETURNING id;

-- Insert a test queue ticket (replace <citizen_id> with actual ID)
INSERT INTO queue_tickets (
  citizen_id,
  queue_date,
  queue_number,
  ticket_code,
  service_key,
  service_label,
  status,
  citizen_type
)
VALUES (
  <citizen_id>,
  CURRENT_DATE,
  1,
  'A001',
  'general',
  'General Consultation',
  'waiting',
  'regular'
);
```

### 6. Test Queue Actions

Once tickets are visible, test these actions:

- [ ] **Move to On Call**: Click "On Call" button on a waiting ticket
- [ ] **Move to Serving**: Click "Serve Now" button on a ticket
- [ ] **Start Vitals**: Click "Start Vitals" on an on-call ticket
- [ ] **Complete**: Click "Complete" on a serving ticket
- [ ] **View Info**: Click "Info" button or click on a ticket card
- [ ] **Drag & Drop**: Drag a ticket card to another lane
- [ ] **Refresh**: Click "Refresh" button
- [ ] **TV View**: Click "TV View" button (opens in new window)

### 7. Verify Realtime Updates

1. Open the queue section in two browser windows
2. Move a ticket in one window
3. Verify the other window updates automatically
4. Check console for realtime subscription messages

### 8. Performance Check

- Queue should load within 2 seconds
- Ticket actions should complete within 1 second
- UI should remain responsive during operations
- No memory leaks after multiple refreshes

## Troubleshooting Commands

### Check if appointments module is loaded:
```javascript
console.log(appointments);
```

### Manually trigger queue load:
```javascript
appointments.loadQueueTickets();
```

### Check current tickets:
```javascript
// This won't work directly as currentQueueTickets is private
// But you can check the DOM:
document.querySelectorAll('.queue-ticket-card').length
```

### Force re-initialization:
```javascript
// Reload the page to reset initialization state
location.reload();
```

## Success Criteria

✅ Console shows `[Queue] Initialization complete`
✅ Ticket counts appear in lane headers
✅ Ticket cards are visible in appropriate lanes
✅ All ticket actions work correctly
✅ Realtime updates work
✅ No JavaScript errors in console
✅ UI is responsive and performant
