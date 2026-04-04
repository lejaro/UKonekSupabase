-- Persist on-call queue state and expose mobile queue metrics.

alter table public.queue_tickets
  drop constraint if exists queue_tickets_status_valid;

alter table public.queue_tickets
  add constraint queue_tickets_status_valid
  check (
    lower(trim(both from status)) = any (
      array['waiting'::text, 'on_call'::text, 'serving'::text, 'completed'::text, 'cancelled'::text]
    )
  );

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

  -- Promote next ticket with On Call priority, then Waiting.
  update public.queue_tickets q
  set
    status = 'serving',
    served_at = coalesce(q.served_at, now())
  where q.id = (
    select q2.id
    from public.queue_tickets q2
    where q2.queue_date = v_target_date
      and q2.service_key = v_service_key
      and lower(trim(coalesce(q2.status, ''))) in ('on_call', 'waiting')
    order by case when lower(trim(coalesce(q2.status, ''))) = 'on_call' then 0 else 1 end,
             q2.queue_number asc
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

drop function if exists public.get_my_queue_dashboard();

create or replace function public.get_my_queue_dashboard()
returns table(
  queue_id bigint,
  service_key text,
  service_label text,
  ticket_code text,
  my_queue_number integer,
  currently_serving_queue_number integer,
  estimated_wait_minutes integer,
  status text,
  queue_date date,
  is_on_call boolean,
  waiting_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_user_email text;
  v_queue_id bigint;
  v_service_key text;
  v_service_label text;
  v_ticket_code text;
  v_my_queue integer;
  v_status text;
  v_serving_queue integer;
  v_waiting_ahead integer;
  v_on_call_ahead integer;
  v_waiting_total integer;
  v_queue_date date;
begin
  select c.id
  into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid()
  limit 1;

  if v_citizen_id is null then
    v_user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));

    if v_user_email <> '' then
      update public.citizens c
      set auth_user_id = auth.uid()
      where c.id = (
        select c2.id
        from public.citizens c2
        where lower(trim(coalesce(c2.email, ''))) = v_user_email
          and c2.auth_user_id is null
        order by c2.id
        limit 1
      )
      returning c.id into v_citizen_id;
    end if;
  end if;

  if v_citizen_id is null then
    return;
  end if;

  select
    q.id,
    q.service_key,
    q.service_label,
    q.ticket_code,
    q.queue_number,
    q.status,
    q.queue_date
  into
    v_queue_id,
    v_service_key,
    v_service_label,
    v_ticket_code,
    v_my_queue,
    v_status,
    v_queue_date
  from public.queue_tickets q
  where q.citizen_id = v_citizen_id
    and q.queue_date = current_date
    and lower(trim(coalesce(q.status, ''))) in ('waiting', 'on_call', 'serving')
  order by q.created_at desc
  limit 1;

  if v_queue_id is null then
    return;
  end if;

  select min(q.queue_number)
  into v_serving_queue
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(coalesce(q.status, ''))) = 'serving';

  select count(*)::integer
  into v_waiting_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(coalesce(q.status, ''))) = 'waiting'
    and q.queue_number < v_my_queue;

  select count(*)::integer
  into v_on_call_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(coalesce(q.status, ''))) = 'on_call'
    and q.queue_number < v_my_queue;

  select count(*)::integer
  into v_waiting_total
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(coalesce(q.status, ''))) = 'waiting';

  queue_id := v_queue_id;
  service_key := v_service_key;
  service_label := v_service_label;
  ticket_code := v_ticket_code;
  my_queue_number := v_my_queue;
  currently_serving_queue_number := v_serving_queue;
  estimated_wait_minutes := (
    coalesce(v_waiting_ahead, 0)
    + coalesce(v_on_call_ahead, 0)
    + case when v_serving_queue is not null and v_serving_queue < v_my_queue then 1 else 0 end
  ) * 10;
  status := v_status;
  queue_date := v_queue_date;
  is_on_call := lower(trim(coalesce(v_status, ''))) = 'on_call';
  waiting_count := coalesce(v_waiting_total, 0);

  return next;
end;
$$;

grant execute on function public.get_my_queue_dashboard() to authenticated;
