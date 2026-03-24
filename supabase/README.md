# Supabase CLI Runbook (Backend)

## Why `supabase start` failed

Local Supabase requires Docker Desktop. If Docker is not installed/running, `supabase start` will fail.

## Cloud-first workflow (no local Docker required)

Run these commands from `backend`:

1. `npx supabase login`
2. `npx supabase link --project-ref <your-project-ref>`
3. `npx supabase db push`

This applies SQL migrations in `supabase/migrations` directly to your hosted Supabase project.

## Local workflow (requires Docker)

1. Install/start Docker Desktop
2. `npx supabase start`
3. `npx supabase db reset`
4. `npx supabase status`

## Important note

The migration includes temporary permissive RLS policies (`temp_allow_all_*`) to avoid breaking current development flows during migration. Replace these with role/user-specific policies before production release.
