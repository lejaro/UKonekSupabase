-- Add RPC to allow citizens to cancel their own active queue ticket.

create or replace function public.cancel_my_queue_ticket()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_citizen_id bigint;
begin
  select c.id
  into v_citizen_id
  from public.citizens c
  where c.auth_user_id = auth.uid()
  limit 1;

  if v_citizen_id is null then
    return false;
  end if;

  update public.queue_tickets
  set status = 'cancelled',
      updated_at = now()
  where citizen_id = v_citizen_id
    and queue_date = current_date
    and lower(trim(coalesce(status, ''))) in ('waiting', 'on_call');

  return found;
end;
$$;

grant execute on function public.cancel_my_queue_ticket() to authenticated;
