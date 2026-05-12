# Queue Ticket Daily Limiter System

## Overview

The Queue Ticket Daily Limiter System restricts the number of queue tickets that can be created per day to prevent clinic overcrowding and ensure quality patient care. The default limit is **20 tickets per day**.

## Features

✅ **Configurable Daily Limit** - Administrators can adjust the limit  
✅ **Automatic Daily Reset** - Counter resets at midnight automatically  
✅ **Real-time Status** - Shows remaining slots to patients  
✅ **User-Friendly Messages** - Clear communication when limit is reached  
✅ **Enable/Disable Toggle** - Can be turned off if needed  
✅ **Mobile & Web Support** - Works on both platforms  

## Database Schema

### System Configuration Table

```sql
CREATE TABLE public.system_config (
    config_key TEXT PRIMARY KEY,
    config_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id)
);
```

### Configuration Keys

| Key | Default Value | Description |
|-----|---------------|-------------|
| `daily_queue_ticket_limit` | `20` | Maximum tickets per day |
| `queue_limiter_enabled` | `true` | Enable/disable the limiter |

## Functions

### 1. `get_daily_ticket_limit()`
Returns the configured daily ticket limit.

```sql
SELECT get_daily_ticket_limit();
-- Returns: 20 (or configured value)
```

### 2. `is_queue_limiter_enabled()`
Returns whether the limiter is enabled.

```sql
SELECT is_queue_limiter_enabled();
-- Returns: true or false
```

### 3. `get_today_ticket_count()`
Returns the number of tickets created today.

```sql
SELECT get_today_ticket_count();
-- Returns: 15 (example)
```

### 4. `is_daily_ticket_limit_reached()`
Returns true if the daily limit is reached.

```sql
SELECT is_daily_ticket_limit_reached();
-- Returns: true or false
```

### 5. `get_queue_limiter_status()`
Returns complete status information for UI display.

```sql
SELECT * FROM get_queue_limiter_status();
```

**Returns:**
```
enabled       | true
daily_limit   | 20
today_count   | 15
limit_reached | false
remaining_slots | 5
```

### 6. `create_queue_ticket()` (Updated)
Now includes automatic limit checking before creating tickets.

```sql
SELECT * FROM create_queue_ticket(
    'general',
    'General Consultation',
    'regular',
    'Annual checkup',
    'None'
);
```

**Error when limit reached:**
```
Exception: Daily queue ticket limit reached. Consultations for today are full. 
Please try again tomorrow or contact the clinic for assistance.
```

## How It Works

### Ticket Creation Flow

```
1. Patient attempts to create queue ticket
   ↓
2. System checks if limiter is enabled
   ↓
3. If enabled, check today's ticket count
   ↓
4. Compare count with daily limit
   ↓
5. If limit reached → Reject with error message
   ↓
6. If limit not reached → Create ticket
   ↓
7. Increment today's count
```

### Daily Reset

The system automatically resets at midnight because:
- Tickets are counted using `DATE(created_at) = CURRENT_DATE`
- No manual reset needed
- Works across timezones

## Configuration

### View Current Configuration

```sql
SELECT * FROM public.system_config 
WHERE config_key IN ('daily_queue_ticket_limit', 'queue_limiter_enabled');
```

### Change Daily Limit

```sql
UPDATE public.system_config
SET config_value = '30',
    updated_at = NOW(),
    updated_by = auth.uid()
WHERE config_key = 'daily_queue_ticket_limit';
```

### Disable Limiter

```sql
UPDATE public.system_config
SET config_value = 'false',
    updated_at = NOW(),
    updated_by = auth.uid()
WHERE config_key = 'queue_limiter_enabled';
```

### Enable Limiter

```sql
UPDATE public.system_config
SET config_value = 'true',
    updated_at = NOW(),
    updated_by = auth.uid()
WHERE config_key = 'queue_limiter_enabled';
```

## Mobile App Integration

### API Service Method

```dart
static Future<QueueLimiterStatus> getQueueLimiterStatus() async {
  final response = await _client.rpc('get_queue_limiter_status');
  final rows = (response as List<dynamic>?) ?? const [];
  if (rows.isEmpty || rows.first is! Map<String, dynamic>) {
    return QueueLimiterStatus.disabled();
  }
  return QueueLimiterStatus.fromMap(rows.first as Map<String, dynamic>);
}
```

### Model Class

```dart
class QueueLimiterStatus {
  final bool enabled;
  final int dailyLimit;
  final int todayCount;
  final bool limitReached;
  final int remainingSlots;
  
  String get statusMessage {
    if (!enabled) return '';
    if (limitReached) {
      return 'Daily consultation limit reached ($dailyLimit/$dailyLimit). Please try again tomorrow.';
    }
    if (remainingSlots <= 5) {
      return 'Only $remainingSlots consultation slots remaining today.';
    }
    return '$remainingSlots consultation slots available today.';
  }
}
```

### UI Implementation

The mobile app displays:

1. **When limit reached** (Red alert):
   - "Consultations Full" header
   - Explanation of daily limit
   - Suggestions: Try tomorrow, call clinic, emergency visits

2. **When slots low** (≤5 remaining, Yellow warning):
   - "Only X consultation slots remaining today!"

3. **When slots available** (Green info):
   - "X of Y consultation slots available"

4. **Submit button**:
   - Disabled when limit reached
   - Shows "LIMIT REACHED" text
   - Grey color when disabled

## Web App Integration

### JavaScript Function (To be implemented)

```javascript
async function getQueueLimiterStatus() {
  const { data, error } = await supabase
    .rpc('get_queue_limiter_status');
  
  if (error) throw error;
  return data[0];
}
```

### UI Display (To be implemented)

Similar to mobile app:
- Alert banner when limit reached
- Warning when slots are low
- Info display for available slots
- Disabled button when limit reached

## Error Messages

### For Patients

**When limit reached:**
```
Daily queue ticket limit reached. Consultations for today are full. 
Please try again tomorrow or contact the clinic for assistance.
```

**What patients can do:**
- ✅ Try again tomorrow when slots reset
- ✅ Call the clinic for scheduling assistance
- ✅ For emergencies, visit immediately

### For Administrators

**When updating configuration:**
```sql
-- Success
UPDATE 1

-- Error (invalid value)
ERROR: invalid input syntax for type integer: "abc"
```

## Performance Considerations

### Index

An index is created for efficient counting:

```sql
CREATE INDEX idx_queue_tickets_created_at_date 
ON public.queue_tickets (DATE(created_at));
```

This ensures fast queries when counting today's tickets.

### Caching

The mobile app caches the limiter status and refreshes:
- When page loads
- When user manually refreshes
- Every 9 seconds (if in queue)

## Security

### Row Level Security (RLS)

```sql
-- Anyone can read system config
CREATE POLICY "Anyone can read system config"
ON public.system_config FOR SELECT USING (true);

-- Only authenticated users can update
CREATE POLICY "Authenticated users can update system config"
ON public.system_config FOR UPDATE
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);
```

### Function Security

All functions use `SECURITY DEFINER` to ensure:
- Consistent execution context
- Proper permission checking
- No SQL injection vulnerabilities

## Monitoring

### Check Today's Status

```sql
SELECT 
    is_queue_limiter_enabled() as enabled,
    get_daily_ticket_limit() as limit,
    get_today_ticket_count() as count,
    is_daily_ticket_limit_reached() as reached,
    get_daily_ticket_limit() - get_today_ticket_count() as remaining;
```

### View Recent Tickets

```sql
SELECT 
    DATE(created_at) as date,
    COUNT(*) as ticket_count
FROM public.queue_tickets
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

### Audit Configuration Changes

```sql
SELECT 
    config_key,
    config_value,
    updated_at,
    updated_by
FROM public.system_config
WHERE config_key IN ('daily_queue_ticket_limit', 'queue_limiter_enabled')
ORDER BY updated_at DESC;
```

## Troubleshooting

### Issue: Limit not enforced

**Check if limiter is enabled:**
```sql
SELECT is_queue_limiter_enabled();
```

**Solution:** Enable the limiter
```sql
UPDATE public.system_config
SET config_value = 'true'
WHERE config_key = 'queue_limiter_enabled';
```

### Issue: Wrong ticket count

**Check today's count:**
```sql
SELECT get_today_ticket_count();
```

**Verify manually:**
```sql
SELECT COUNT(*) 
FROM public.queue_tickets
WHERE DATE(created_at) = CURRENT_DATE;
```

### Issue: Limit reached too early

**Check current limit:**
```sql
SELECT get_daily_ticket_limit();
```

**Solution:** Increase the limit
```sql
UPDATE public.system_config
SET config_value = '30'
WHERE config_key = 'daily_queue_ticket_limit';
```

## Future Enhancements

Potential improvements:

1. **Per-Service Limits** - Different limits for different services
2. **Time-based Limits** - Different limits for morning/afternoon
3. **Priority Overrides** - Allow PWD/pregnant to bypass limit
4. **Waitlist System** - Queue patients when limit is reached
5. **Admin Dashboard** - Visual interface for configuration
6. **Analytics** - Track limit reach frequency
7. **Notifications** - Alert admins when limit is near

## Testing

### Test Limit Enforcement

```sql
-- 1. Set low limit for testing
UPDATE public.system_config
SET config_value = '2'
WHERE config_key = 'daily_queue_ticket_limit';

-- 2. Create first ticket (should succeed)
SELECT * FROM create_queue_ticket('general', 'General', 'regular', 'Test 1', '');

-- 3. Create second ticket (should succeed)
SELECT * FROM create_queue_ticket('general', 'General', 'regular', 'Test 2', '');

-- 4. Create third ticket (should fail)
SELECT * FROM create_queue_ticket('general', 'General', 'regular', 'Test 3', '');
-- Expected: Exception about limit reached

-- 5. Reset limit
UPDATE public.system_config
SET config_value = '20'
WHERE config_key = 'daily_queue_ticket_limit';
```

### Test Disable/Enable

```sql
-- Disable limiter
UPDATE public.system_config
SET config_value = 'false'
WHERE config_key = 'queue_limiter_enabled';

-- Should allow unlimited tickets
SELECT is_daily_ticket_limit_reached();
-- Expected: false (even if count > limit)

-- Re-enable limiter
UPDATE public.system_config
SET config_value = 'true'
WHERE config_key = 'queue_limiter_enabled';
```

## Migration

The system is installed via migration:
```
supabase/migrations/20260507000000_add_queue_ticket_limiter.sql
```

To apply:
```bash
# Local development
supabase db reset

# Production
supabase db push
```

## Support

For issues or questions:
1. Check this documentation
2. Review migration file
3. Test with SQL queries
4. Check mobile app logs
5. Verify RLS policies

---

**Version**: 1.0  
**Last Updated**: May 7, 2026  
**Status**: ✅ Production Ready
