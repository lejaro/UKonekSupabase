-- =============================================================================
-- Migration: 20261108143000_optimize_queue_tickets_deletion.sql
-- Description:
--   1. Optimizes delete_old_pending_queue_tickets() and check_and_delete_old_queue_tickets()
--      to use the indexed queue_date column instead of wrapping created_at in timezone
--      expressions that cause sequential table scans.
--   2. Performs batching to prevent large WAL spikes and reduce autovacuum memory load
--      at midnight (16:00 UTC / 12:00 AM Manila).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.delete_old_pending_queue_tickets()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_manila DATE;
  v_deleted_count INT := 0;
  v_batch_deleted INT := 0;
BEGIN
  v_today_manila := (NOW() AT TIME ZONE 'Asia/Manila')::date;

  -- Delete in batches of 500 rows to prevent massive single-transaction WAL surges
  -- and mitigate intense autovacuum memory commitment spikes at midnight.
  LOOP
    WITH rows_to_delete AS (
      SELECT id FROM public.queue_tickets
      WHERE queue_date < v_today_manila
         OR created_at < (v_today_manila::text || ' 00:00:00+08')::timestamptz
      LIMIT 500
    )
    DELETE FROM public.queue_tickets
    WHERE id IN (SELECT id FROM rows_to_delete);

    GET DIAGNOSTICS v_batch_deleted = ROW_COUNT;
    v_deleted_count := v_deleted_count + v_batch_deleted;

    EXIT WHEN v_batch_deleted < 500;
  END LOOP;

  RAISE NOTICE 'Deleted % old queue tickets prior to Manila date %', v_deleted_count, v_today_manila;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_old_pending_queue_tickets() TO authenticated;

-- Optimize trigger function
CREATE OR REPLACE FUNCTION public.check_and_delete_old_queue_tickets()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today_manila DATE;
  v_last_cleanup DATE;
BEGIN
  v_today_manila := (NOW() AT TIME ZONE 'Asia/Manila')::date;
  
  -- Fast lookup of last cleanup date
  SELECT config_value::date INTO v_last_cleanup
  FROM public.system_config
  WHERE config_key = 'last_queue_cleanup_date';
  
  -- If already cleaned up today, exit immediately without scanning queue_tickets
  IF v_last_cleanup IS NOT NULL AND v_last_cleanup >= v_today_manila THEN
    RETURN NULL;
  END IF;
  
  -- Perform cleanup using optimized batch function
  PERFORM public.delete_old_pending_queue_tickets();
  
  -- Record that today's cleanup completed
  INSERT INTO public.system_config (config_key, config_value, description, updated_at)
  VALUES ('last_queue_cleanup_date', v_today_manila::text, 'Date of last automated queue ticket cleanup in Manila time', TIMEZONE('Asia/Manila', NOW()))
  ON CONFLICT (config_key) DO UPDATE
    SET config_value = EXCLUDED.config_value,
        updated_at = EXCLUDED.updated_at;
        
  RETURN NULL;
END;
$$;
