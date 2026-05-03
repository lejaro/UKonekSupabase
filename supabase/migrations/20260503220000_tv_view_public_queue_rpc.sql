-- TV View public queue display RPC
-- Returns only the non-sensitive queue data needed for the TV display board:
-- currently serving (status = 'serving'), on-call (status = 'on_call'),
-- and waiting (status = 'waiting') tickets for today.
-- Uses security definer so the TV display page needs no auth session.

create or replace function public.get_tv_queue_display(
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_serving  json;
  v_on_call  json;
  v_waiting  json;
begin
  -- Currently serving tickets
  select json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status,
      'served_at',     q.served_at
    )
    order by q.queue_number asc
  )
  into v_serving
  from public.queue_tickets q
  where q.queue_date = coalesce(p_date, current_date)
    and lower(trim(q.status)) = 'serving';

  -- On-call tickets
  select json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status
    )
    order by q.queue_number asc
  )
  into v_on_call
  from public.queue_tickets q
  where q.queue_date = coalesce(p_date, current_date)
    and lower(trim(q.status)) = 'on_call';

  -- Waiting tickets
  select json_agg(
    json_build_object(
      'id',            q.id,
      'queue_number',  q.queue_number,
      'service_key',   q.service_key,
      'service_label', q.service_label,
      'status',        q.status,
      'citizen_type',  q.citizen_type
    )
    order by q.queue_number asc
  )
  into v_waiting
  from public.queue_tickets q
  where q.queue_date = coalesce(p_date, current_date)
    and lower(trim(q.status)) = 'waiting';

  return json_build_object(
    'serving',  coalesce(v_serving, '[]'::json),
    'on_call',  coalesce(v_on_call, '[]'::json),
    'waiting',  coalesce(v_waiting, '[]'::json),
    'as_of',    now()
  );
end;
$$;

-- Allow anon role to call this function (TV screen needs no login)
grant execute on function public.get_tv_queue_display(date) to anon;
grant execute on function public.get_tv_queue_display(date) to authenticated;
