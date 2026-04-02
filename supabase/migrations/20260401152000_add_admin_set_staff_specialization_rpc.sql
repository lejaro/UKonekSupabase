begin;

create or replace function public.set_staff_specialization_admin(
  target_staff_id bigint,
  p_specialization text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_role text;
  updated_row public.staff%rowtype;
begin
  select s.role
    into current_role
  from public.staff s
  where s.auth_user_id = auth.uid()
  limit 1;

  if current_role is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Admin access required.');
  end if;

  update public.staff
     set doctor_specialization = nullif(trim(coalesce(p_specialization, '')), '')
   where id = target_staff_id
   returning * into updated_row;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Staff record not found.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'staff', jsonb_build_object(
      'id', updated_row.id,
      'role', updated_row.role,
      'doctor_specialization', updated_row.doctor_specialization
    )
  );
end;
$$;

grant execute on function public.set_staff_specialization_admin(bigint, text) to authenticated;

commit;
