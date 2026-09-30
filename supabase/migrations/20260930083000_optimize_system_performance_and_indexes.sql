-- =============================================================================
-- System Performance Optimizations for 50+ Concurrent Users
-- 1. Refactor get_clinical_operations_metrics to use UTC range scans instead of
--    per-row AT TIME ZONE conversions, enabling index utilization.
-- 2. Add missing composite & single-column B-tree indexes on hot tables:
--    - medicine_intake_logs(citizen_id, intake_date)
--    - prescription_item_dispenses(dispensed_at)
--    - consultations(created_at)
-- 3. Inline redundant sub-function call in get_queue_limiter_status() to eliminate
--    duplicate table queries.
-- =============================================================================

-- 1. Missing Indexes
CREATE INDEX IF NOT EXISTS idx_medicine_intake_citizen_date 
  ON public.medicine_intake_logs(citizen_id, intake_date);

CREATE INDEX IF NOT EXISTS idx_pid_dispensed_at 
  ON public.prescription_item_dispenses(dispensed_at);

CREATE INDEX IF NOT EXISTS idx_consultations_created_at 
  ON public.consultations(created_at);

-- 2. Scoped & Indexed get_clinical_operations_metrics
CREATE OR REPLACE FUNCTION public.get_clinical_operations_metrics()
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date;
  v_start_utc timestamptz;
  v_end_utc timestamptz;
BEGIN
  v_today := public.get_manila_date();
  -- Pre-compute UTC boundaries for Manila today
  v_start_utc := (v_today::timestamp AT TIME ZONE 'Asia/Manila');
  v_end_utc := ((v_today + 1)::timestamp AT TIME ZONE 'Asia/Manila');

  RETURN json_build_object(
    'waiting',        (SELECT count(*) FROM public.queue_tickets WHERE status IN ('waiting', 'on_call') AND queue_date = v_today),
    'serving',        (SELECT count(*) FROM public.queue_tickets WHERE status = 'serving' AND queue_date = v_today),
    'consults_today', (SELECT count(*) FROM public.consultations WHERE created_at >= v_start_utc AND created_at < v_end_utc),
    'vitals_today',   (SELECT count(*) FROM public.vital_signs WHERE created_at >= v_start_utc AND created_at < v_end_utc),
    'dispenses_today',(
      (SELECT count(*) FROM public.prescription_item_dispenses WHERE dispensed_at >= v_start_utc AND dispensed_at < v_end_utc) +
      (SELECT count(*) FROM public.otc_dispenses WHERE dispensed_at >= v_start_utc AND dispensed_at < v_end_utc)
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_clinical_operations_metrics() TO authenticated, anon, service_role;

-- 3. Streamlined get_queue_limiter_status
CREATE OR REPLACE FUNCTION public.get_queue_limiter_status()
RETURNS TABLE (
    enabled BOOLEAN,
    daily_limit INTEGER,
    today_count INTEGER,
    limit_reached BOOLEAN,
    remaining_slots INTEGER,
    doctors_available BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_enabled BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
    v_reached BOOLEAN;
    v_remaining INTEGER;
    v_docs_avail BOOLEAN;
BEGIN
    v_enabled := is_queue_limiter_enabled();
    v_limit := get_daily_ticket_limit();
    v_count := get_today_ticket_count();
    v_reached := (v_enabled AND v_count >= v_limit);
    v_remaining := GREATEST(0, v_limit - v_count);
    v_docs_avail := is_any_doctor_available();
    
    RETURN QUERY SELECT v_enabled, v_limit, v_count, v_reached, v_remaining, v_docs_avail;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_queue_limiter_status() TO authenticated, anon, service_role;
