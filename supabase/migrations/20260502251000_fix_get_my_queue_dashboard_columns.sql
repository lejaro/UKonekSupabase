-- Restore is_on_call and waiting_count columns to get_my_queue_dashboard.
-- These were accidentally removed in a previous migration.

drop function if exists public.get_my_queue_dashboard();

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
    return;
  end if;

  -- Find the most recent active ticket for today
  select
    q.id,
    q.service_key,
    q.service_label,
    q.ticket_code,
    q.queue_number,
    trim(both from q.status) as status,
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
    and lower(trim(both from coalesce(q.status, ''))) in ('waiting', 'on_call', 'serving')
  order by q.created_at desc
  limit 1;

  if v_queue_id is null then
    return;
  end if;

  -- Currently serving is the lowest number in 'serving' or 'on_call' status
  select min(q.queue_number)
  into v_serving_queue
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) in ('serving', 'on_call');

  -- Count how many 'waiting' people are ahead
  select count(*)::integer
  into v_waiting_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) = 'waiting'
    and q.queue_number < v_my_queue;

  -- Count how many 'on_call' people are ahead
  select count(*)::integer
  into v_on_call_ahead
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) = 'on_call'
    and q.queue_number < v_my_queue;

  -- Total waiting for this service
  select count(*)::integer
  into v_waiting_total
  from public.queue_tickets q
  where q.queue_date = v_queue_date
    and q.service_key = v_service_key
    and lower(trim(both from coalesce(q.status, ''))) = 'waiting';

  queue_id := v_queue_id;
  service_key := v_service_key;
  service_label := v_service_label;
  ticket_code := v_ticket_code;
  my_queue_number := v_my_queue;
  currently_serving_queue_number := v_serving_queue;
  
  -- Calculate estimated wait
  if lower(trim(both from coalesce(v_status, ''))) in ('serving', 'on_call') then
    estimated_wait_minutes := 0;
  else
    estimated_wait_minutes := (
      coalesce(v_waiting_ahead, 0) 
      + coalesce(v_on_call_ahead, 0)
      + case when v_serving_queue is not null and v_serving_queue < v_my_queue then 1 else 0 end
    ) * 10;
  end if;
  
  status := v_status;
  queue_date := v_queue_date;
  is_on_call := lower(trim(both from coalesce(v_status, ''))) = 'on_call';
  waiting_count := coalesce(v_waiting_total, 0);

  return next;
end;
$$;

grant execute on function public.get_my_queue_dashboard() to authenticated;
