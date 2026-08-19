-- =============================================================================
-- P0-4 + P2-9: Fix cron job schedule + add cron log cleanup
--
-- Problem:
--   staff_unavailable_5pm_manila runs '0 * * * *' (every hour, 24×/day)
--   but only does real work at 5PM Manila. Wastes DB wakeups + grows
--   cron.job_run_details (2,645 rows as of 2026-08-16).
--
-- Fix:
--   1. Reschedule to '0 9 * * *' UTC = 5PM Manila (UTC+8: 9+8=17=5PM). ✓
--   2. Add weekly cleanup of cron.job_run_details (Sundays at 3AM UTC).
-- =============================================================================

-- 1. Reschedule staff_unavailable_5pm_manila: hourly → once at 5PM Manila
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('staff_unavailable_5pm_manila');
  EXCEPTION WHEN OTHERS THEN
    -- Job may not exist yet; safe to ignore
  END;

  PERFORM cron.schedule(
    'staff_unavailable_5pm_manila',
    '0 9 * * *',
    'select public.set_staff_unavailable_after_hours();'
  );
END;
$$;

-- 2. Weekly cleanup of cron.job_run_details (Sundays 3AM UTC)
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('cleanup-cron-logs');
  EXCEPTION WHEN OTHERS THEN
    -- Job may not exist yet; safe to ignore
  END;

  PERFORM cron.schedule(
    'cleanup-cron-logs',
    '0 3 * * 0',
    $cmd$DELETE FROM cron.job_run_details WHERE start_time < now() - interval '7 days'$cmd$
  );
END;
$$;
