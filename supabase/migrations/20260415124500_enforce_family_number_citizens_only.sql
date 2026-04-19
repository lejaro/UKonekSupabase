-- Enforce: only citizen records may have a family_number value.

-- Clean up any invalid historical rows first (if any exist).
update public.citizens
set family_number = null
where family_number is not null
  and lower(trim(coalesce(role, ''))) <> 'citizen';

alter table public.citizens
  drop constraint if exists citizens_family_number_citizen_only;

alter table public.citizens
  add constraint citizens_family_number_citizen_only
  check (
    family_number is null
    or lower(trim(coalesce(role, ''))) = 'citizen'
  );
