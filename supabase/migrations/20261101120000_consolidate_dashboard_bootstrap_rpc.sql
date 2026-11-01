-- =============================================================================
-- Migration: 20261101120000_consolidate_dashboard_bootstrap_rpc.sql
-- Description: High-performance consolidated dashboard bootstrap RPC and
--              indexes to prevent memory commitment spikes (Committed_AS)
--              by eliminating multi-query parallel bursts and client-side
--              table scans.
-- =============================================================================

-- 1. Covering & Partial Indexes for Telemetry & Realtime Filters
CREATE INDEX IF NOT EXISTS idx_queue_tickets_date_status 
  ON public.queue_tickets (queue_date, status);

CREATE INDEX IF NOT EXISTS idx_queue_tickets_created_at 
  ON public.queue_tickets (created_at);

CREATE INDEX IF NOT EXISTS idx_consultations_created_at 
  ON public.consultations (created_at);

CREATE INDEX IF NOT EXISTS idx_vital_signs_created_at 
  ON public.vital_signs (created_at);

CREATE INDEX IF NOT EXISTS idx_rx_dispenses_dispensed_at 
  ON public.prescription_item_dispenses (dispensed_at);

CREATE INDEX IF NOT EXISTS idx_otc_dispenses_dispensed_at 
  ON public.otc_dispenses (dispensed_at);


-- 2. Consolidated High-Speed Dashboard RPC
CREATE OR REPLACE FUNCTION public.get_dashboard_bootstrap_data()
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
  v_seven_days_ago date;
  v_seven_days_utc timestamptz;
  
  v_waiting int;
  v_serving int;
  v_consults_today int;
  v_vitals_today int;
  v_dispenses_today int;
  v_registered_citizens int;

  v_line_trend json;
  v_top_diagnoses json;
  v_priority_dist json;
BEGIN
  v_today := public.get_manila_date();
  v_start_utc := (v_today::timestamp AT TIME ZONE 'Asia/Manila');
  v_end_utc := ((v_today + 1)::timestamp AT TIME ZONE 'Asia/Manila');
  v_seven_days_ago := v_today - 6;
  v_seven_days_utc := (v_seven_days_ago::timestamp AT TIME ZONE 'Asia/Manila');

  -- 1. Operational Counts
  SELECT count(*) INTO v_waiting 
  FROM public.queue_tickets 
  WHERE status IN ('waiting', 'on_call') AND queue_date = v_today;

  SELECT count(*) INTO v_serving 
  FROM public.queue_tickets 
  WHERE status = 'serving' AND queue_date = v_today;

  SELECT count(*) INTO v_consults_today 
  FROM public.consultations 
  WHERE created_at >= v_start_utc AND created_at < v_end_utc;

  SELECT count(*) INTO v_vitals_today 
  FROM public.vital_signs 
  WHERE created_at >= v_start_utc AND created_at < v_end_utc;

  SELECT (
    coalesce((SELECT count(*) FROM public.prescription_item_dispenses WHERE dispensed_at >= v_start_utc AND dispensed_at < v_end_utc), 0) +
    coalesce((SELECT count(*) FROM public.otc_dispenses WHERE dispensed_at >= v_start_utc AND dispensed_at < v_end_utc), 0)
  ) INTO v_dispenses_today;

  SELECT count(*) INTO v_registered_citizens 
  FROM public.citizens;

  -- 2. 7-Day Line Trend: Daily Queue & Consultations volume
  WITH days AS (
    SELECT generate_series(v_seven_days_ago, v_today, '1 day'::interval)::date AS d
  ),
  q_counts AS (
    SELECT coalesce(queue_date, (created_at AT TIME ZONE 'Asia/Manila')::date) AS q_date, count(*) AS cnt
    FROM public.queue_tickets
    WHERE created_at >= v_seven_days_utc
    GROUP BY 1
  ),
  c_counts AS (
    SELECT coalesce((consulted_at AT TIME ZONE 'Asia/Manila')::date, (created_at AT TIME ZONE 'Asia/Manila')::date) AS c_date, count(*) AS cnt
    FROM public.consultations
    WHERE created_at >= v_seven_days_utc
    GROUP BY 1
  )
  SELECT json_build_object(
    'dates', coalesce(json_agg(to_char(days.d, 'YYYY-MM-DD') ORDER BY days.d), '[]'::json),
    'labels', coalesce(json_agg(to_char(days.d, 'FMMM/FMDD') ORDER BY days.d), '[]'::json),
    'queueCounts', coalesce(json_agg(coalesce(q.cnt, 0) ORDER BY days.d), '[]'::json),
    'consultCounts', coalesce(json_agg(coalesce(c.cnt, 0) ORDER BY days.d), '[]'::json)
  ) INTO v_line_trend
  FROM days
  LEFT JOIN q_counts q ON q.q_date = days.d
  LEFT JOIN c_counts c ON c.c_date = days.d;

  -- 3. Top 5 Diagnoses in last 7 days
  WITH diags AS (
    SELECT trim(diagnosis) AS diag, count(*) AS cnt
    FROM public.consultations
    WHERE created_at >= v_seven_days_utc
      AND diagnosis IS NOT NULL
      AND trim(diagnosis) NOT IN ('', '—', '-', 'None', 'none', 'N/A', 'n/a', 'null', 'NULL')
    GROUP BY trim(diagnosis)
    ORDER BY cnt DESC
    LIMIT 5
  )
  SELECT json_build_object(
    'labels', coalesce(json_agg(diag ORDER BY cnt DESC), '[]'::json),
    'counts', coalesce(json_agg(cnt ORDER BY cnt DESC), '[]'::json)
  ) INTO v_top_diagnoses
  FROM diags;

  -- 4. Priority Distribution in last 7 days
  WITH classified AS (
    SELECT
      CASE
        WHEN lower(citizen_type) = 'pwd' OR lower(coalesce(service_label, '')) LIKE '%pwd%' THEN 'PWD'
        WHEN lower(citizen_type) = 'pregnant' OR lower(coalesce(service_label, '')) LIKE '%pregnant%' THEN 'Pregnant'
        ELSE 'Regular'
      END AS cat
    FROM public.queue_tickets
    WHERE created_at >= v_seven_days_utc
  ),
  cat_counts AS (
    SELECT
      count(*) FILTER (WHERE cat = 'Regular') AS regular_cnt,
      count(*) FILTER (WHERE cat = 'PWD') AS pwd_cnt,
      count(*) FILTER (WHERE cat = 'Pregnant') AS pregnant_cnt
    FROM classified
  )
  SELECT json_build_object(
    'labels', json_build_array('Regular', 'PWD', 'Pregnant'),
    'counts', json_build_array(coalesce(regular_cnt, 0), coalesce(pwd_cnt, 0), coalesce(pregnant_cnt, 0))
  ) INTO v_priority_dist
  FROM cat_counts;

  RETURN json_build_object(
    'metrics', json_build_object(
      'waiting', coalesce(v_waiting, 0),
      'serving', coalesce(v_serving, 0),
      'consults_today', coalesce(v_consults_today, 0),
      'vitals_today', coalesce(v_vitals_today, 0),
      'dispenses_today', coalesce(v_dispenses_today, 0),
      'registered_citizens', coalesce(v_registered_citizens, 0)
    ),
    'analytics', json_build_object(
      'lineTrend', coalesce(v_line_trend, '{}'::json),
      'topDiagnoses', coalesce(v_top_diagnoses, json_build_object('labels', '[]'::json, 'counts', '[]'::json)),
      'priorityDist', coalesce(v_priority_dist, json_build_object('labels', json_build_array('Regular', 'PWD', 'Pregnant'), 'counts', json_build_array(0, 0, 0)))
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_dashboard_bootstrap_data() TO authenticated, anon, service_role;

