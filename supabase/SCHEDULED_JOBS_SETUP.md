# Scheduled Jobs Setup for uKonek

## Auto-Delete Pending Queue Tickets

The system automatically deletes pending queue tickets (status: `waiting` or `on_call`) from previous days.

### Implementation

Two approaches are implemented:

#### 1. **pg_cron Scheduled Job (Recommended)**
- Runs every day at midnight (00:00)
- Requires `pg_cron` extension to be enabled

#### 2. **Trigger-Based Cleanup (Fallback)**
- Automatically runs when the first queue ticket of the day is created
- Works without pg_cron extension
- Ensures old tickets are cleaned up even if pg_cron is not available

### How to Enable pg_cron in Supabase

1. **Go to Supabase Dashboard**
   - Navigate to your project
   - Go to **Database** → **Extensions**

2. **Enable pg_cron Extension**
   - Search for `pg_cron`
   - Click **Enable** button
   - Wait for extension to be activated

3. **Verify Installation**
   Run this query in SQL Editor:
   ```sql
   SELECT * FROM cron.job;
   ```
   
   You should see the job: `delete-old-pending-queue-tickets`

4. **Check Job Status**
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'delete-old-pending-queue-tickets')
   ORDER BY start_time DESC 
   LIMIT 10;
   ```

### Manual Execution

To manually delete old pending queue tickets:

```sql
SELECT public.delete_old_pending_queue_tickets();
```

### What Gets Deleted

The function deletes queue tickets that meet ALL these conditions:
- Status is `waiting` OR `on_call`
- Created date is before today (CURRENT_DATE)

### What is NOT Deleted

Queue tickets with these statuses are preserved:
- `completed` - Already served
- `cancelled` - Manually cancelled
- `no_show` - Patient didn't show up

### Monitoring

To check when the last cleanup ran:

```sql
-- Check cron job runs (if pg_cron is enabled)
SELECT 
  jobname,
  start_time,
  end_time,
  status,
  return_message
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'delete-old-pending-queue-tickets')
ORDER BY start_time DESC
LIMIT 5;
```

### Troubleshooting

**If pg_cron is not available:**
- The trigger-based fallback will handle cleanup automatically
- Old tickets will be deleted when the first new ticket is created each day

**To disable the scheduled job:**
```sql
SELECT cron.unschedule('delete-old-pending-queue-tickets');
```

**To re-enable the scheduled job:**
```sql
SELECT cron.schedule(
  'delete-old-pending-queue-tickets',
  '0 0 * * *',
  $$SELECT public.delete_old_pending_queue_tickets();$$
);
```

### Schedule Customization

To change when the cleanup runs, modify the cron schedule:

```sql
-- Run at 1:00 AM instead of midnight
SELECT cron.schedule(
  'delete-old-pending-queue-tickets',
  '0 1 * * *',  -- minute hour day month weekday
  $$SELECT public.delete_old_pending_queue_tickets();$$
);
```

Common cron schedules:
- `0 0 * * *` - Every day at midnight
- `0 1 * * *` - Every day at 1:00 AM
- `0 */6 * * *` - Every 6 hours
- `0 0 * * 0` - Every Sunday at midnight

### Testing

To test the cleanup function:

1. **Create test tickets from yesterday:**
   ```sql
   INSERT INTO queue_tickets (citizen_id, ticket_code, status, created_at)
   VALUES 
     (1, 'TEST-001', 'waiting', CURRENT_DATE - INTERVAL '1 day'),
     (1, 'TEST-002', 'on_call', CURRENT_DATE - INTERVAL '1 day');
   ```

2. **Run cleanup:**
   ```sql
   SELECT public.delete_old_pending_queue_tickets();
   ```

3. **Verify deletion:**
   ```sql
   SELECT * FROM queue_tickets WHERE ticket_code LIKE 'TEST-%';
   -- Should return no results
   ```

### Migration File

The migration file is located at:
```
supabase/migrations/20260506000000_auto_delete_pending_queue_tickets.sql
```

Apply it using:
```bash
supabase db push
```

Or run it manually in the Supabase SQL Editor.
