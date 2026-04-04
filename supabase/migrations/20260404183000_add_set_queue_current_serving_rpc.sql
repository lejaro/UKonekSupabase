-- Allow staff/admin to explicitly choose who is currently serving.
-- Ensures only one active 'serving' ticket per date/service.

create or replace function public.set_queue_current_serving(
  p_queue_ticket_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_target public.queue_tickets%rowtype;
begin
  v_role := lower(trim(coalesce(public.get_staff_role(), '')));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

  select *
  into v_target
  from public.queue_tickets
  where id = p_queue_ticket_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Queue ticket not found.');
  end if;

  if lower(trim(coalesce(v_target.status, ''))) in ('completed', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'Cannot set completed/cancelled ticket as serving.');
  end if;

  update public.queue_tickets
  set status = 'waiting'
  where id <> v_target.id
    and queue_date = v_target.queue_date
    and service_key = v_target.service_key
    and lower(trim(coalesce(status, ''))) = 'serving';

  update public.queue_tickets
  set
    status = 'serving',
    served_at = coalesce(served_at, now())
  where id = v_target.id;

  return jsonb_build_object(
    'ok', true,
    'queue_date', v_target.queue_date,
    'service_key', v_target.service_key,
    'current_ticket_id', v_target.id,
    'current_queue_number', v_target.queue_number,
    'current_ticket_code', v_target.ticket_code,
    'citizen_id', v_target.citizen_id
  );
end;
$$;

grant execute on function public.set_queue_current_serving(bigint) to authenticated;
