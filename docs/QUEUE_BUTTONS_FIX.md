# Queue Buttons Fix - Refresh and TV View

## Problem
The **Refresh** and **TV View** buttons in the Queue section were not working when clicked.

## Root Cause

### Issue 1: Premature Initialization
The `appointments` module was initializing on `DOMContentLoaded` event, which happens when the page first loads. At that time:
- The queue section has the `hidden` class
- The buttons are not accessible in the DOM
- Event listeners are attached to non-existent elements

### Issue 2: Duplicate Initialization
The dashboard was calling both:
1. `appointments.init()` - which loads tickets
2. `appointments.loadQueueTickets()` - loading tickets again

This caused unnecessary duplicate data fetching.

### Issue 3: No Listener Cleanup
Event listeners were being added every time the section was shown, without removing old listeners, potentially causing multiple executions.

## Solution

### 1. Removed Auto-Initialization
**File:** `frontend/web/js/appointments.js`

**Before:**
```javascript
document.addEventListener('DOMContentLoaded', () => {
  appointments.init();
});
```

**After:**
```javascript
// Don't auto-initialize on DOMContentLoaded
// Let the dashboard call init() when the queue section is shown
```

### 2. Improved init() Function
**File:** `frontend/web/js/appointments.js`

Added checks to ensure:
- Queue section exists in DOM
- Queue section is visible (not hidden)
- Event listeners are always set up (they handle duplicates)
- Data is loaded on first init and refreshed on subsequent calls

```javascript
const init = async () => {
  const queueSection = document.getElementById('queue-section');
  if (!queueSection) return;
  
  // Check if section is visible
  const isHidden = queueSection.classList.contains('hidden');
  if (isHidden) return;
  
  // Always set up event listeners
  setupEventListeners();
  setupTicketModalHandlers();
  setupLaneDropZones();
  
  // Load data (first time or refresh)
  if (!isInitialized) {
    await loadQueueTickets();
    setupRealtimeListener();
    isInitialized = true;
  } else {
    await loadQueueTickets();
  }
};
```

### 3. Enhanced setupEventListeners()
**File:** `frontend/web/js/appointments.js`

Added:
- Console logging for debugging
- Listener cleanup before adding new ones
- Proper handler references stored on button elements

```javascript
const setupEventListeners = () => {
  const refreshBtn = document.getElementById('queue-refresh-btn');
  const tvViewBtn = document.getElementById('open-tv-view-btn');
  
  // Remove old listeners if they exist
  if (refreshBtn && refreshBtn._queueRefreshHandler) {
    refreshBtn.removeEventListener('click', refreshBtn._queueRefreshHandler);
  }
  
  // Add new listeners
  if (refreshBtn) {
    const refreshHandler = async () => {
      console.log('[Queue] Refresh button clicked');
      refreshBtn.disabled = true;
      refreshBtn.textContent = 'Loading...';
      try {
        await loadQueueTickets();
      } finally {
        refreshBtn.disabled = false;
        refreshBtn.textContent = 'Refresh';
      }
    };
    refreshBtn._queueRefreshHandler = refreshHandler;
    refreshBtn.addEventListener('click', refreshHandler);
  }
  
  // Similar for TV View button
};
```

### 4. Simplified Dashboard Call
**File:** `frontend/web/js/dashboard.js`

**Before:**
```javascript
case 'queue-section':
  if (typeof appointments !== 'undefined') {
    if (appointments.init) {
      appointments.init();
    }
    if (appointments.loadQueueTickets) {
      appointments.loadQueueTickets();
    }
  }
  break;
```

**After:**
```javascript
case 'queue-section':
  if (typeof appointments !== 'undefined' && appointments.init) {
    await appointments.init();
  }
  break;
```

## Benefits

### 1. Proper Timing
- Event listeners are attached when buttons actually exist in the DOM
- No more attaching listeners to hidden elements

### 2. No Duplicates
- Old listeners are removed before adding new ones
- Prevents multiple executions of the same action

### 3. Better Debugging
- Console logs show when buttons are found/not found
- Console logs show when buttons are clicked
- Easy to diagnose issues

### 4. Cleaner Code
- Single initialization call from dashboard
- No duplicate data loading
- Clear separation of concerns

## Testing

### 1. Test Refresh Button
1. Navigate to Queue section
2. Click **Refresh** button
3. Console should show: `[Queue] Refresh button clicked`
4. Button should show "Loading..." then "Refresh"
5. Queue data should reload

### 2. Test TV View Button
1. Navigate to Queue section
2. Click **TV View** button
3. Console should show: `[Queue] TV View button clicked`
4. New window should open with `tv-view.html`

### 3. Test Multiple Navigation
1. Navigate to Queue section
2. Navigate away (e.g., to Dashboard)
3. Navigate back to Queue section
4. Buttons should still work
5. No duplicate listeners (check console logs)

## Console Output (Success)

```
[Queue] Init called, isInitialized: false
[Queue] Queue section hidden: false
[Queue] Setting up event listeners...
[Queue] Refresh button found: true
[Queue] TV View button found: true
[Queue] Refresh button listener attached
[Queue] TV View button listener attached
[Queue] First-time initialization...
[Queue] Loading tickets for date: 2026-05-11
[Queue] Fetching tickets with direct query
[Queue] Direct query returned 5 tickets
[Queue] Final ticket count: 5
[Queue] Initialization complete

// When clicking Refresh button:
[Queue] Refresh button clicked
[Queue] Loading tickets for date: 2026-05-11
[Queue] Fetching tickets with direct query
[Queue] Direct query returned 5 tickets

// When clicking TV View button:
[Queue] TV View button clicked
```

## Troubleshooting

### Buttons still not working?

1. **Check console logs**
   - Look for `[Queue] Refresh button found: false`
   - This means button IDs don't match

2. **Check button IDs in HTML**
   - Should be `id="queue-refresh-btn"`
   - Should be `id="open-tv-view-btn"`

3. **Check if section is visible**
   - Look for `[Queue] Queue section hidden: true`
   - Section must be visible for init to proceed

4. **Check for JavaScript errors**
   - Open console and look for red error messages
   - Fix any errors before testing buttons

### TV View opens wrong page?

The TV View button opens `tv-view.html` in the same directory as the dashboard. If the file is in a different location, update the path:

```javascript
window.open('tv-view.html', '_blank');  // Current directory
window.open('../tv-view.html', '_blank');  // Parent directory
window.open('/path/to/tv-view.html', '_blank');  // Absolute path
```

## Related Changes

This fix builds on the previous queue data loading fix:
- **Data Loading Fix**: Changed from RPC to direct query
- **Button Fix**: Fixed event listener timing and cleanup

Both fixes work together to make the queue section fully functional.

## Files Modified

1. `frontend/web/js/appointments.js`
   - Removed DOMContentLoaded auto-init
   - Enhanced init() function
   - Improved setupEventListeners()
   - Added console logging

2. `frontend/web/js/dashboard.js`
   - Simplified queue-section case
   - Single init() call instead of init() + loadQueueTickets()

## Success Criteria

✅ Refresh button works and reloads queue data
✅ TV View button opens new window with tv-view.html
✅ Buttons work after navigating away and back
✅ No duplicate event listeners
✅ Console logs show proper initialization
✅ No JavaScript errors
