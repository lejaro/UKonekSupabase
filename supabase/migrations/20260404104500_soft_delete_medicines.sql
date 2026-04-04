-- Soft-delete medicines and allow re-adding archived names.

alter table public.medicines
  add column if not exists archived_at timestamptz;

drop index if exists public.idx_medicines_name_lower;
create unique index if not exists idx_medicines_name_lower_active
  on public.medicines (lower(trim(name)))
  where archived_at is null;
