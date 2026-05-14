-- ───────────────────────────────────────────────────────────────────────────
-- FIX: EXPAND QUEUE SERVICES TO ALL CLINIC OFFERINGS
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.list_available_queue_services(date);

CREATE OR REPLACE FUNCTION public.list_available_queue_services(
  p_date date DEFAULT NULL
)
RETURNS TABLE (
  service_key text,
  service_label text,
  doctor_count integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH standard_services AS (
    SELECT 'medical_consultation'::text as s_key, 'Medical Consultation'::text as s_label, 1 as ord
    UNION ALL SELECT 'animal_bite_center'::text, 'Animal Bite Center'::text, 2
    UNION ALL SELECT 'family_preventive_care'::text, 'Family Preventive Care & Wellness'::text, 3
    UNION ALL SELECT 'family_counselling'::text, 'Family Counselling'::text, 4
    UNION ALL SELECT 'prenatal_gyne'::text, 'Pre Natal and Gyne Consult'::text, 5
    UNION ALL SELECT 'pediatric_illness'::text, 'Pediatric Illness and Wellness'::text, 6
    UNION ALL SELECT 'intensive_lifestyle_change'::text, 'Intensive Therapeutic Lifestyle Change'::text, 7
    UNION ALL SELECT 'lifestyle_health_check'::text, 'Lifestyle Health Check'::text, 8
    UNION ALL SELECT 'geriatric_palliative'::text, 'Geriatric & Palliative Care'::text, 9
    UNION ALL SELECT 'iv_hydration'::text, 'IV Hydration'::text, 10
    UNION ALL SELECT 'onsite_ape'::text, 'On site APE'::text, 11
    UNION ALL SELECT 'pre_employment_exam'::text, 'Pre-Employment Exam'::text, 12
    UNION ALL SELECT 'minor_surgery'::text, 'Minor Surgery'::text, 13
    UNION ALL SELECT 'cauterization'::text, 'Cauterization'::text, 14
    UNION ALL SELECT 'ecg'::text, 'ECG'::text, 15
    UNION ALL SELECT 'clinical_lab_test'::text, 'Clinical Laboratory test'::text, 16
    UNION ALL SELECT 'immunization'::text, 'Immunization'::text, 17
  ),
  doctor_source AS (
    SELECT 
      count(*)::integer as d_count
    FROM public.doctor_schedules ds
    JOIN public.staff s ON s.id = ds.doctor_staff_id
    WHERE ds.schedule_date = coalesce(p_date, public.get_manila_date())
      AND lower(trim(coalesce(s.status, ''))) = 'active'
      AND lower(trim(coalesce(s.role, ''))) = 'doctor'
  )
  SELECT 
    ss.s_key as service_key,
    ss.s_label as service_label,
    coalesce((SELECT d_count FROM doctor_source), 0) as doctor_count
  FROM standard_services ss
  ORDER BY ss.ord;
$$;
