-- Link vital_signs to queue_tickets and add notes column.
-- Add upsert RPC so one assessment per ticket is enforced (update if exists).
-- Add get_vitals_for_ticket RPC for doctor view during consultation.

-- 1. Add queue_ticket_id and notes to vital_signs
ALTER TABLE public.vital_signs
  ADD COLUMN IF NOT EXISTS queue_ticket_id BIGINT REFERENCES public.queue_tickets(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE INDEX IF NOT EXISTS idx_vital_signs_queue_ticket_id
  ON public.vital_signs (queue_ticket_id);

-- Partial unique index: at most one assessment per queue ticket
CREATE UNIQUE INDEX IF NOT EXISTS uq_vital_signs_queue_ticket
  ON public.vital_signs (queue_ticket_id)
  WHERE queue_ticket_id IS NOT NULL;

-- 2. Allow staff to update vital signs (for upsert on same ticket)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'vital_signs' AND policyname = 'Allow staff to update vital signs'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "Allow staff to update vital signs" ON public.vital_signs
        FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
    $policy$;
  END IF;
END;
$$;

-- 3. upsert_vital_assessment: insert or update the assessment for a ticket
drop function if exists public.upsert_vital_assessment(bigint, bigint, text, text, integer, numeric, integer, integer, text, text);

create or replace function public.upsert_vital_assessment(
  p_queue_ticket_id   bigint,
  p_citizen_id        bigint,
  p_chief_complaint   text,
  p_blood_pressure    text     default null,
  p_heart_rate        integer  default null,
  p_temperature       numeric  default null,
  p_respiratory_rate  integer  default null,
  p_oxygen_saturation integer  default null,
  p_current_medications text   default null,
  p_notes             text     default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nurse_id   bigint;
  v_result_id  uuid;
begin
  -- Caller must be active staff
  select s.id into v_nurse_id
  from   public.staff s
  where  s.auth_user_id = auth.uid()
    and  lower(coalesce(s.status, '')) = 'active'
  limit 1;

  if v_nurse_id is null then
    return json_build_object('error', 'Forbidden: active staff account required');
  end if;

  if p_citizen_id is null or p_chief_complaint is null or trim(p_chief_complaint) = '' then
    return json_build_object('error', 'citizen_id and chief_complaint are required');
  end if;

  insert into public.vital_signs (
    queue_ticket_id,
    citizen_id,
    nurse_id,
    chief_complaint,
    blood_pressure,
    heart_rate,
    temperature,
    respiratory_rate,
    oxygen_saturation,
    current_medications,
    notes,
    created_at
  )
  values (
    p_queue_ticket_id,
    p_citizen_id,
    v_nurse_id,
    trim(p_chief_complaint),
    nullif(trim(coalesce(p_blood_pressure, '')),    ''),
    p_heart_rate,
    p_temperature,
    p_respiratory_rate,
    p_oxygen_saturation,
    nullif(trim(coalesce(p_current_medications, '')), ''),
    nullif(trim(coalesce(p_notes, '')),               ''),
    now()
  )
  on conflict (queue_ticket_id)
  do update set
    citizen_id          = excluded.citizen_id,
    nurse_id            = excluded.nurse_id,
    chief_complaint     = excluded.chief_complaint,
    blood_pressure      = excluded.blood_pressure,
    heart_rate          = excluded.heart_rate,
    temperature         = excluded.temperature,
    respiratory_rate    = excluded.respiratory_rate,
    oxygen_saturation   = excluded.oxygen_saturation,
    current_medications = excluded.current_medications,
    notes               = excluded.notes,
    created_at          = now()
  returning id into v_result_id;

  return json_build_object('ok', true, 'id', v_result_id);
exception
  when others then
    return json_build_object('error', coalesce(sqlerrm, 'Failed to save vital assessment'));
end;
$$;

grant execute on function public.upsert_vital_assessment(bigint, bigint, text, text, integer, numeric, integer, integer, text, text) to authenticated;

-- 4. get_vitals_for_ticket: fetch assessment for a queue ticket (for doctor consultation view)
drop function if exists public.get_vitals_for_ticket(bigint);

create or replace function public.get_vitals_for_ticket(p_queue_ticket_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_row  json;
begin
  v_role := lower(coalesce(public.get_staff_role(), ''));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

  select row_to_json(t) into v_row
  from (
    select
      vs.id,
      vs.queue_ticket_id,
      vs.citizen_id,
      vs.chief_complaint,
      vs.blood_pressure,
      vs.heart_rate,
      vs.temperature,
      vs.respiratory_rate,
      vs.oxygen_saturation,
      vs.current_medications,
      vs.notes,
      vs.created_at,
      coalesce(
        nullif(trim(concat_ws(' ', s.first_name, s.last_name)), ''),
        'Nurse'
      ) as nurse_name
    from   public.vital_signs vs
    left   join public.staff s on s.id = vs.nurse_id
    where  vs.queue_ticket_id = p_queue_ticket_id
    order  by vs.created_at desc
    limit  1
  ) t;

  return v_row;
end;
$$;

grant execute on function public.get_vitals_for_ticket(bigint) to authenticated;
