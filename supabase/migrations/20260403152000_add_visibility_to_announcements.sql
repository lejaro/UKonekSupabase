-- Add visibility column to announcements table (staff only, citizen only, or all)

alter table public.announcements
add column visibility varchar(20) not null default 'all'
check (visibility in ('all', 'staff', 'citizen'));

-- Create index for visibility to speed up filtered queries
create index if not exists idx_announcements_visibility on public.announcements(visibility);
