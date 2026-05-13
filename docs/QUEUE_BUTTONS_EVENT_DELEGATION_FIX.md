# Queue Buttons Fix - Event Delegation Approach

## Problem
Refresh and TV View buttons were still not working even after previous fixes.

## Root Cause
The event listeners were being attached directly to buttons, but:
1. Multiple event listeners were being added to `document` for ticket actions
2. This could interfere with button click events
3. Event propagation might be stopped by other handlers
4. Direct button listeners are fragile when DOM changes

## Solution
Changed to **event delegation** pattern - attach a single click handler to the queue section that handles ALL button clicks.

## Benefits of Event Delegation

### Before (Direct Listeners)
```javascript
// Attach listener directly to each button
refreshBtn.addEventListener('click', refreshHandler);
tvViewBtn.addEventListener('click', tvViewHandler);
document.addEventListener('click', ticketActionHandler);  // Global!
```

**Problems:**
- Multiple global listeners on `document`
- Listeners can interfere with each other
- Need to re-attach if buttons are re-rendered
- Hard to debug which listener fires first

### After (Event Delegation)
```javascript
// Single listener on queue section handles everything
queueSection.addEventListener('click', (event) => {
  if (target.id === 'queue-refresh-btn') { /* handle */ }
  if (target.id === 'open-tv-view-btn') { /* handle */ }
  if (target.closest('[data-action="..."]')) { /* handle */ }
});
```

**Benefits:**
- ✅ Single event listener (no conflicts)
- ✅ Works even if buttons are re-rendered
- ✅ Easier to debug (one handler)
- ✅ Better performance
- ✅ Cleaner code

## Code Changes

### File: `frontend/web/js/appointments.js`

#### Complete Rewrite of setupEventListeners()

**Before:**
```javascript
const setupEventListeners = () => {
  const refreshBtn = document.getElementById('queue-refresh-btn');
  const tvViewBtn = document.getElementById('open-tv-view-btn');
  
  // Direct listeners on buttons
  refreshBtn?.addEventListener('click', refreshHandler);
  tvViewBtn?.addEventListener('click', tvViewHandler);
  
  // Global listener on document
  document.addEventListener('click', ticketActionHandler);
};
```

**After:**
```javascript
const setupEventListeners = () => {
  const queueSection = document.getElementById('queue-section');
  
  // Single listener on queue section
  const clickHandler = async (event) => {
    const target = event.target;
    
    // Check which button was clicked
    if (target.id === 'queue-refresh-btn' || target.closest('#queue-refresh-btn')) {
      event.preventDefault();
      event.stopPropagation();
      console.log('[Queue] Refresh button clicked');
      // Handle refresh
      return;
    }
    
    if (target.id === 'open-tv-view-btn' || target.closest('#open-tv-view-btn')) {
      event.preventDefault();
      event.stopPropagation();
      console.log('[Queue] TV View button clicked');
      window.open('tv-view.html', '_blank');
      return;
    }
    
    // Handle ticket actions
    const actionBtn = target.closest('[data-action]');
    if (actionBtn) {
      // Handle based on data-action attribute
    }
  };
  
  // Attach single handler
  queueSection.addEventListener('click', clickHandler);
};
```

## Key Features

### 1. Event Delegation
Attach listener to parent element (queue section) instead of individual buttons.

### 2. Event Propagation Control
```javascript
event.preventDefault();
event.stopPropagation();
```
Prevents other handlers from interfering.

### 3. Flexible Target Matching
```javascript
if (target.id === 'queue-refresh-btn' || target.closest('#queue-refresh-btn'))
```
Handles clicks on button or its children (like text/icons inside button).

### 4. Cleanup
```javascript
if (queueSection._queueClickHandler) {
  queueSection.removeEventListener('click', queueSection._queueClickHandler);
}
```
Removes old handler before adding new one.

### 5. Handler Reference
```javascript
queueSection._queueClickHandler = clickHandler;
```
Stores reference for later cleanup.

## Testing

### Test 1: Refresh Button
1. Navigate to Queue section
2. Click **Refresh** button
3. Console should show: `[Queue] Refresh button clicked`
4. Button should show "Loading..." then "Refresh"
5. Queue data should reload

### Test 2: TV View Button
1. Navigate to Queue section
2. Click **TV View** button
3. Console should show: `[Queue] TV View button clicked`
4. New window should open with `tv-view.html`

### Test 3: Multiple Clicks
1. Click Refresh button multiple times quickly
2. Should handle gracefully (button disabled during load)
3. No duplicate requests

### Test 4: Navigation
1. Navigate to Queue section (buttons work)
2. Navigate away
3. Navigate back to Queue section
4. Buttons should still work (no duplicate handlers)

## Console Output

### Successful Setup
```
[Queue] Setting up event listeners...
[Queue] Event delegation handler attached to queue section
[Queue] Refresh button found: true
[Queue] TV View button found: true
```

### Button Clicks
```
[Queue] Refresh button clicked
[Queue] Loading tickets for date: 2026-05-11
[Queue] Fetching tickets with direct query
[Queue] Direct query returned 5 tickets

[Queue] TV View button clicked
```

## Troubleshooting

### Buttons still not working?

1. **Check console logs**
   ```
   [Queue] Event delegation handler attached to queue section
   ```
   If missing, event listener wasn't attached.

2. **Check button IDs**
   - Refresh: `id="queue-refresh-btn"`
   - TV View: `id="open-tv-view-btn"`

3. **Check queue section exists**
   ```javascript
   document.getElementById('queue-section')
   ```
   Should not be null.

4. **Check for JavaScript errors**
   - Open console (F12)
   - Look for red error messages
   - Fix any errors before testing

### Click not detected?

1. **Check event propagation**
   - Other handlers might be stopping propagation
   - Our handler uses `stopPropagation()` to prevent this

2. **Check button structure**
   - Button should be inside `#queue-section`
   - Button should have correct ID

3. **Check CSS**
   - Button should not have `pointer-events: none`
   - Button should be visible and clickable

## Why This Works

### Event Delegation Pattern
This is a standard JavaScript pattern for handling dynamic content:

1. **Attach to parent**: Listen on a stable parent element
2. **Check target**: Determine which child was clicked
3. **Handle accordingly**: Execute appropriate action

### Benefits in This Case
1. **No conflicts**: Single listener instead of multiple
2. **Robust**: Works even if buttons are re-rendered
3. **Clean**: Easy to understand and maintain
4. **Performant**: One listener instead of many

## Related Patterns

### Event Delegation (Used Here)
```javascript
parent.addEventListener('click', (e) => {
  if (e.target.matches('.button')) {
    // Handle button click
  }
});
```

### Direct Listeners (Previous Approach)
```javascript
button.addEventListener('click', handler);
```

### Global Listeners (Avoid)
```javascript
document.addEventListener('click', handler);  // Too broad!
```

## Future Improvements

1. **Keyboard Support**: Add keyboard event handlers
2. **Touch Support**: Add touch event handlers for mobile
3. **Accessibility**: Add ARIA attributes and focus management
4. **Analytics**: Track button clicks for usage metrics

## Summary

**The Issue**: Direct button listeners weren't firing
**The Fix**: Changed to event delegation pattern
**The Result**: Buttons now work reliably

This approach is more robust and follows JavaScript best practices for handling events in dynamic UIs.

---

**Status:** ✅ Fixed
**Pattern:** Event Delegation
**Impact:** Refresh and TV View buttons now work correctly
**Date:** May 11, 2026
