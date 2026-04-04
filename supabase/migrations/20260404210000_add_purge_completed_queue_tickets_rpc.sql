-- Automatically remove completed queue tickets for today's queue view.

create or replace function public.purge_completed_queue_tickets(
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
  v_target_date date;
  v_service_key text;
  v_deleted_count integer := 0;
begin
  v_role := lower(trim(coalesce(public.get_staff_role(), '')));
  if v_role = '' then
    raise exception 'Forbidden: active staff account required';
  end if;

  v_target_date := coalesce(p_queue_date, current_date);
  v_service_key := nullif(lower(trim(coalesce(p_service_key, ''))), '');

  delete from public.queue_tickets q
  where q.queue_date = v_target_date
    and lower(trim(coalesce(q.status, ''))) = 'completed'
    and (v_service_key is null or lower(trim(coalesce(q.service_key, ''))) = v_service_key);

  get diagnostics v_deleted_count = row_count;

  return jsonb_build_object(
    'ok', true,
    'queue_date', v_target_date,
    'service_key', v_service_key,
    'deleted_count', v_deleted_count
  );
end;
$$;

grant execute on function public.purge_completed_queue_tickets(date, text) to authenticated;
