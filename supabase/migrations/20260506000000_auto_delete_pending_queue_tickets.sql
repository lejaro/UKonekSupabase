-- Automatically delete pending queue tickets when the day has ended
-- This migration creates a function and scheduled job to clean up old pending tickets

-- Function to delete pending queue tickets from previous days
CREATE OR REPLACE FUNCTION public.delete_old_pending_queue_tickets()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delete queue tickets that are:
  -- 1. Status is 'waiting' or 'on_call' (pending states)
  -- 2. Created before today (previous days)
  DELETE FROM public.queue_tickets
  WHERE status IN ('waiting', 'on_call')
    AND DATE(created_at) < CURRENT_DATE;
  
  -- Log the cleanup action
  RAISE NOTICE 'Deleted old pending queue tickets from previous days at %', NOW();
END;
$$;

-- Grant execute permission to authenticated users (for manual trigger if needed)
GRANT EXECUTE ON FUNCTION public.delete_old_pending_queue_tickets() TO authenticated;

-- Create a scheduled job using pg_cron (if available)
-- This will run every day at midnight (00:00)
-- Note: pg_cron extension must be enabled in Supabase project settings

-- Check if pg_cron is available and create the scheduled job
DO $$
BEGIN
  -- Try to create the cron job
  -- This will fail silently if pg_cron is not installed
  BEGIN
    PERFORM cron.schedule(
      'delete-old-pending-queue-tickets',  -- job name
      '0 0 * * *',                          -- cron schedule: every day at midnight
      $$SELECT public.delete_old_pending_queue_tickets();$$
    );
    RAISE NOTICE 'Scheduled job created successfully';
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'pg_cron extension not available. Please enable it in Supabase dashboard or run the function manually.';
    WHEN OTHERS THEN
      RAISE NOTICE 'Could not create scheduled job: %', SQLERRM;
  END;
END;
$$;

-- Alternative: Create a trigger-based approach that runs on first query of the day
-- This is a fallback if pg_cron is not available

CREATE OR REPLACE FUNCTION public.check_and_delete_old_queue_tickets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  last_cleanup_date DATE;
BEGIN
  -- Get the last cleanup date from a tracking table
  -- We'll use a simple approach: check if any tickets from previous days exist
  SELECT MAX(DATE(created_at)) INTO last_cleanup_date
  FROM public.queue_tickets
  WHERE status IN ('waiting', 'on_call')
    AND DATE(created_at) < CURRENT_DATE;
  
  -- If there are old pending tickets, delete them
  IF last_cleanup_date IS NOT NULL THEN
    DELETE FROM public.queue_tickets
    WHERE status IN ('waiting', 'on_call')
      AND DATE(created_at) < CURRENT_DATE;
    
    RAISE NOTICE 'Auto-deleted % old pending queue tickets', FOUND;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger that runs before insert on queue_tickets
-- This ensures cleanup happens when first ticket of the day is created
DROP TRIGGER IF EXISTS trigger_cleanup_old_queue_tickets ON public.queue_tickets;
CREATE TRIGGER trigger_cleanup_old_queue_tickets
  BEFORE INSERT ON public.queue_tickets
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.check_and_delete_old_queue_tickets();

-- Add comments for documentation
COMMENT ON FUNCTION public.delete_old_pending_queue_tickets() IS 
  'Deletes queue tickets with status waiting or on_call that were created before today. Run daily at midnight via pg_cron or manually.';

COMMENT ON FUNCTION public.check_and_delete_old_queue_tickets() IS 
  'Trigger function that automatically cleans up old pending queue tickets when new tickets are created. Fallback for when pg_cron is not available.';

-- Manual execution example (for testing or manual cleanup):
-- SELECT public.delete_old_pending_queue_tickets();
