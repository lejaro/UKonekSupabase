-- Automatically delete queue tickets when the day has ended (12:00 AM Asia/Manila)
-- This migration creates a function, scheduled job, and fallback trigger to clean up old tickets.

-- Function to delete queue tickets from previous days
CREATE OR REPLACE FUNCTION public.delete_old_pending_queue_tickets()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delete all queue tickets created before today in Asia/Manila local time
  DELETE FROM public.queue_tickets
  WHERE (created_at AT TIME ZONE 'Asia/Manila')::date < (now() AT TIME ZONE 'Asia/Manila')::date;
  
  -- Log the cleanup action
  RAISE NOTICE 'Deleted old queue tickets from previous days at %', timezone('Asia/Manila', NOW());
END;
$$;

-- Grant execute permission to authenticated users (for manual trigger if needed)
GRANT EXECUTE ON FUNCTION public.delete_old_pending_queue_tickets() TO authenticated;

-- Create a scheduled job using pg_cron (if available)
-- This will run every day at 12:00 AM (midnight) Manila Time (which is 16:00 UTC)
-- Note: pg_cron extension must be enabled in Supabase project settings
DO $$
BEGIN
  -- Try to clean up the existing job first to update its schedule
  BEGIN
    PERFORM cron.unschedule('delete-old-pending-queue-tickets');
  EXCEPTION WHEN OTHERS THEN
    -- Ignore if the job does not exist yet
  END;

  -- Create the updated cron job scheduled for 16:00 UTC (12:00 AM Asia/Manila)
  BEGIN
    PERFORM cron.schedule(
      'delete-old-pending-queue-tickets',  -- job name
      '0 16 * * *',                         -- cron schedule: 16:00 UTC (12:00 AM Asia/Manila)
      'SELECT public.delete_old_pending_queue_tickets();'
    );
    RAISE NOTICE 'Scheduled job created successfully for 12:00 AM Manila time (16:00 UTC)';
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'pg_cron extension not available. Falling back to trigger-based cleanup.';
    WHEN OTHERS THEN
      RAISE NOTICE 'Could not create scheduled job: %', SQLERRM;
  END;
END;
$$;

-- Fallback: Create a trigger-based approach that runs on first query of the day
-- This ensures cleanup happens at midnight even if pg_cron is not enabled or available
CREATE OR REPLACE FUNCTION public.check_and_delete_old_queue_tickets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  has_old_tickets BOOLEAN;
BEGIN
  -- Check if any tickets from previous days exist in Manila time
  SELECT EXISTS (
    SELECT 1 FROM public.queue_tickets
    WHERE (created_at AT TIME ZONE 'Asia/Manila')::date < (now() AT TIME ZONE 'Asia/Manila')::date
  ) INTO has_old_tickets;
  
  -- If there are old tickets, delete them
  IF has_old_tickets THEN
    DELETE FROM public.queue_tickets
    WHERE (created_at AT TIME ZONE 'Asia/Manila')::date < (now() AT TIME ZONE 'Asia/Manila')::date;
    
    RAISE NOTICE 'Auto-deleted old queue tickets from previous days';
  END IF;
  
  -- Statement-level trigger must return NULL
  RETURN NULL;
END;
$$;

-- Create trigger that runs before insert on queue_tickets
-- This ensures cleanup happens when the first ticket of the new day is created
DROP TRIGGER IF EXISTS trigger_cleanup_old_queue_tickets ON public.queue_tickets;
CREATE TRIGGER trigger_cleanup_old_queue_tickets
  BEFORE INSERT ON public.queue_tickets
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.check_and_delete_old_queue_tickets();

-- Add comments for documentation
COMMENT ON FUNCTION public.delete_old_pending_queue_tickets() IS 
  'Deletes all queue tickets created before today in Asia/Manila timezone. Run daily at 12:00 AM Manila time via pg_cron or manually.';

COMMENT ON FUNCTION public.check_and_delete_old_queue_tickets() IS 
  'Trigger function that automatically cleans up old queue tickets when a new ticket is inserted. Fallback for when pg_cron is not available.';
