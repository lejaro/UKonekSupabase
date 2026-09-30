-- Optimize list_available_doctor_schedules by removing the mutating purge function
-- to prevent Thundering Herd Row Exclusive locks and DB IO exhaustion under load.

CREATE OR REPLACE FUNCTION public.list_available_doctor_schedules(
  p_date_from date default current_date,
  p_date_to date default (current_date + interval '30 days')::date
)
RETURNS TABLE (
  id bigint,
  doctor_staff_id bigint,
  doctor_name varchar,
  specialization text,
  schedule_date date,
  start_time time,
  end_time time,
  notes text,
  availability_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('row_security', 'off', true);

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- REMOVED: PERFORM public.purge_expired_doctor_schedules();
  -- This caused severe database locking and IO exhaustion on read queries.
  -- The query naturally filters expired schedules via p_date_from.

  RETURN QUERY
  SELECT
    ds.id,
    ds.doctor_staff_id,
    coalesce(
      nullif(trim(ds.doctor_name), ''),
      trim(concat(coalesce(s.first_name, ''), ' ', coalesce(s.last_name, '')))
    )::varchar AS doctor_name,
    coalesce(s.doctor_specialization, '')::text AS specialization,
    ds.schedule_date,
    ds.start_time,
    ds.end_time,
    ds.notes,
    coalesce(s.availability_status, 'available') AS availability_status
  FROM public.doctor_schedules ds
  JOIN public.staff s
    ON s.id = ds.doctor_staff_id
  WHERE lower(trim(coalesce(s.role, ''))) = 'doctor'
    AND lower(trim(coalesce(s.status, ''))) = 'active'
    AND lower(trim(coalesce(s.availability_status, 'available'))) IN ('available', 'on_break')
    AND ds.schedule_date >= p_date_from
    AND ds.schedule_date <= p_date_to
  ORDER BY ds.schedule_date ASC, ds.start_time ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_available_doctor_schedules(date, date) TO authenticated;
