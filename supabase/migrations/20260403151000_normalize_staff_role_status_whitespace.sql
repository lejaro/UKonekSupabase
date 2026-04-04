-- Normalize existing staff role/status values by trimming surrounding whitespace.
-- This prevents read filters from missing rows due to accidental spaces.

update public.staff
set
  role = trim(role),
  status = case
    when status is null then status
    else trim(status)
  end
where role <> trim(role)
   or (status is not null and status <> trim(status));
