-- Auto-link legacy citizen accounts by email when queue RPCs run.

create or replace function public.create_queue_ticket(
  p_service_key text,
  p_service_label text,
  p_citizen_type text,
  p_reason text default null,
  p_symptoms text default null
)
returns table (
  id bigint,
  queue_number integer,
  ticket_code text,
  service_key text,
  service_label text,
  citizen_type text,
  status text,
  estimated_wait_minutes integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
  v_user_email text;
  v_service_key text;
  v_service_label text;
  v_citizen_type text;
  v_next_number integer;
  v_ticket_code text;
  v_waiting_ahead integer;
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
    raise exception 'Citizen profile not found for current session.';
  end if;

  v_service_key := lower(trim(coalesce(p_service_key, '')));
  v_service_label := trim(coalesce(p_service_label, ''));
  v_citizen_type := lower(trim(coalesce(p_citizen_type, 'regular')));

  if v_service_key = '' then
    raise exception 'Service key is required.';
  end if;

  if v_service_label = '' then
    raise exception 'Service label is required.';
  end if;

  if v_citizen_type not in ('regular', 'pwd', 'pregnant') then
    raise exception 'Invalid citizen type.';
  end if;

  select coalesce(max(q.queue_number), 0) + 1
  into v_next_number
  from public.queue_tickets q
  where q.queue_date = current_date
    and q.service_key = v_service_key;

  v_ticket_code := format(
    'Q-%s-%s-%s',
    to_char(current_date, 'YYYYMMDD'),
    upper(substr(regexp_replace(v_service_key, '[^a-z0-9]+', '', 'g'), 1, 4)),
    lpad(v_next_number::text, 3, '0')
  );

  insert into public.queue_tickets (
    queue_date,
    service_key,
    service_label,
    queue_number,
    ticket_code,
    citizen_id,
    citizen_type,
    reason,
    symptoms,
    status
  )
  values (
    current_date,
    v_service_key,
    v_service_label,
    v_next_number,
    v_ticket_code,
    v_citizen_id,
    v_citizen_type,
    nullif(trim(coalesce(p_reason, '')), ''),
    nullif(trim(coalesce(p_symptoms, '')), ''),
    'waiting'
  )
  returning
    queue_tickets.id,
    queue_tickets.queue_number,
    queue_tickets.ticket_code,
    queue_tickets.service_key,
    queue_tickets.service_label,
    queue_tickets.citizen_type,
    queue_tickets.status
  into id, queue_number, ticket_code, service_key, service_label, citizen_type, status;

  select count(*)::integer
  into v_waiting_ahead
  from public.queue_tickets q
  where q.queue_date = current_date
    and q.service_key = v_service_key
    and lower(trim(coalesce(q.status, ''))) in ('waiting', 'serving')
    and q.queue_number < v_next_number;

  estimated_wait_minutes := greatest(0, v_waiting_ahead) * 10;

  return next;
end;
$$;

grant execute on function public.create_queue_ticket(text, text, text, text, text) to authenticated;

create or replace function public.get_my_queue_dashboard()
returns table (
  queue_id bigint,
  service_key text,
  service_label text,
  ticket_code text,
  my_queue_number integer,
  currently_serving_queue_number integer,
  estimated_wait_minutes integer,
  status text,
  queue_date date
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
    and lower(trim(coalesce(q.status, ''))) in ('waiting', 'serving')
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

  queue_id := v_queue_id;
  service_key := v_service_key;
  service_label := v_service_label;
  ticket_code := v_ticket_code;
  my_queue_number := v_my_queue;
  currently_serving_queue_number := v_serving_queue;
  estimated_wait_minutes := (coalesce(v_waiting_ahead, 0) + case when v_serving_queue is not null and v_serving_queue < v_my_queue then 1 else 0 end) * 10;
  status := v_status;
  queue_date := v_queue_date;

  return next;
end;
$$;

grant execute on function public.get_my_queue_dashboard() to authenticated;
