-- Advance queue atomically for a given date/service:
-- 1) complete current serving ticket (if any)
-- 2) promote next waiting ticket to serving

create or replace function public.advance_queue_ticket(
  p_queue_date date default current_date,
  p_service_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_service_key text;
  v_target_date date;
  v_completed_id bigint;
  v_completed_queue_number integer;
  v_current_id bigint;
  v_current_queue_number integer;
  v_current_ticket_code text;
begin
  v_role := lower(trim(coalesce(public.get_staff_role(), '')));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

  v_service_key := lower(trim(coalesce(p_service_key, '')));
  if v_service_key = '' then
    return jsonb_build_object('ok', false, 'error', 'Service key is required.');
  end if;

  v_target_date := coalesce(p_queue_date, current_date);

  -- Complete currently serving ticket (if there is one).
  update public.queue_tickets q
  set
    status = 'completed',
    completed_at = now()
  where q.id = (
    select q2.id
    from public.queue_tickets q2
    where q2.queue_date = v_target_date
      and q2.service_key = v_service_key
      and lower(trim(coalesce(q2.status, ''))) = 'serving'
    order by q2.queue_number asc
    limit 1
    for update skip locked
  )
  returning q.id, q.queue_number
  into v_completed_id, v_completed_queue_number;

  -- Promote next waiting ticket.
  update public.queue_tickets q
  set
    status = 'serving',
    served_at = coalesce(q.served_at, now())
  where q.id = (
    select q2.id
    from public.queue_tickets q2
    where q2.queue_date = v_target_date
      and q2.service_key = v_service_key
      and lower(trim(coalesce(q2.status, ''))) = 'waiting'
    order by q2.queue_number asc
    limit 1
    for update skip locked
  )
  returning q.id, q.queue_number, q.ticket_code
  into v_current_id, v_current_queue_number, v_current_ticket_code;

  return jsonb_build_object(
    'ok', true,
    'queue_date', v_target_date,
    'service_key', v_service_key,
    'completed_ticket_id', v_completed_id,
    'completed_queue_number', v_completed_queue_number,
    'current_ticket_id', v_current_id,
    'current_queue_number', v_current_queue_number,
    'current_ticket_code', v_current_ticket_code
  );
end;
$$;

grant execute on function public.advance_queue_ticket(date, text) to authenticated;
