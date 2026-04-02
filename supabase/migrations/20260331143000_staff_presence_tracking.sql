-- Add presence tracking for currently logged-in staff counting.

alter table public.staff
  add column if not exists is_online boolean not null default false,
  add column if not exists last_seen timestamptz;

create index if not exists idx_staff_online_last_seen
  on public.staff (is_online, last_seen desc);

create or replace function public.set_staff_presence(p_is_online boolean default true)
returns boolean
language plpgsql
security definer
volatile
as $$
declare
  v_user_id uuid;
  v_user_email text;
begin
  v_user_id := auth.uid();
  v_user_email := lower(coalesce(auth.jwt()->>'email', ''));

  if v_user_id is null and v_user_email = '' then
    return false;
  end if;

  update public.staff
  set is_online = p_is_online,
      last_seen = now()
  where (v_user_id is not null and auth_user_id = v_user_id)
     or (v_user_email <> '' and lower(email) = v_user_email);

  return found;
end;
$$;

grant execute on function public.set_staff_presence(boolean) to authenticated;
