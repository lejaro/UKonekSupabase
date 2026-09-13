-- =============================================================================
-- Scope Clinical Operations Metrics to Manila Today
-- Date: 2026-09-12
--
-- Ensures all 4 clinical operations counts (Patients in Queue, Consultations Today,
-- Triage Assessments Today, Medicines Dispensed Today) strictly filter for today
-- in Asia/Manila timezone.
-- =============================================================================

create or replace function public.get_clinical_operations_metrics()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'waiting',        (select count(*) from public.queue_tickets where status in ('waiting', 'on_call') and queue_date = public.get_manila_date()),
    'serving',        (select count(*) from public.queue_tickets where status = 'serving' and queue_date = public.get_manila_date()),
    'consults_today', (select count(*) from public.consultations where (created_at at time zone 'Asia/Manila')::date = public.get_manila_date()),
    'vitals_today',   (select count(*) from public.vital_signs where (created_at at time zone 'Asia/Manila')::date = public.get_manila_date()),
    'dispenses_today',(
      (select count(*) from public.prescription_item_dispenses where (dispensed_at at time zone 'Asia/Manila')::date = public.get_manila_date()) +
      (select count(*) from public.otc_dispenses where (dispensed_at at time zone 'Asia/Manila')::date = public.get_manila_date())
    )
  );
$$;

grant execute on function public.get_clinical_operations_metrics() to authenticated, anon;
