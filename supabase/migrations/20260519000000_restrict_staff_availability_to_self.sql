-- Migration: Restrict staff availability updates to only the user themselves.
-- Users can only modify their own availability status row.

create or replace function public.set_staff_availability(
  p_target_staff_id bigint default null,
  p_status text default 'available'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_email text;
  v_actor_staff_id bigint;
  v_actor_role text;
  v_target_staff_id bigint;
  v_status text;
begin
  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  if auth.uid() is null and v_user_email = '' then
    raise exception 'Forbidden: authentication required';
  end if;

  -- Auto-link auth.uid to staff row if not yet linked
  update public.staff
  set auth_user_id = auth.uid()
  where auth.uid() is not null
    and auth_user_id is null
    and lower(email) = v_user_email
    and lower(coalesce(status, '')) = 'active';

  select s.id, lower(coalesce(s.role, ''))
    into v_actor_staff_id, v_actor_role
  from public.staff s
  where lower(coalesce(s.status, '')) = 'active'
    and (
      (auth.uid() is not null and s.auth_user_id = auth.uid())
      or (v_user_email <> '' and lower(s.email) = v_user_email)
    )
  order by case when lower(coalesce(s.role, '')) = 'doctor' then 0 else 1 end, s.id asc
  limit 1;

  if v_actor_staff_id is null then
    raise exception 'Active staff account required';
  end if;

  -- Verify role is permitted to modify availability
  if v_actor_role not in ('doctor', 'admin', 'nurse', 'staff', 'specialist') then
    raise exception 'Forbidden: insufficient role to update availability';
  end if;

  v_target_staff_id := coalesce(p_target_staff_id, v_actor_staff_id);

  -- ENFORCE: Staff can only change their own availability status!
  if v_target_staff_id <> v_actor_staff_id then
    raise exception 'Forbidden: you can only update your own availability status';
  end if;

  v_status := lower(trim(coalesce(p_status, 'available')));
  if v_status = 'on break' then
    v_status := 'on_break';
  end if;

  if v_status not in ('available', 'on_break', 'unavailable') then
    raise exception 'Invalid availability status';
  end if;

  update public.staff
  set availability_status = v_status
  where id = v_target_staff_id
    and lower(trim(coalesce(role, ''))) in ('doctor', 'nurse', 'staff', 'specialist')
    and lower(coalesce(status, '')) = 'active';

  if not found then
    raise exception 'Unable to update staff availability';
  end if;

  return json_build_object('staff_id', v_target_staff_id, 'availability_status', v_status);
end;
$$;

grant execute on function public.set_staff_availability(bigint, text) to authenticated;
