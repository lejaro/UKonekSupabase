-- =============================================================================
-- Migration: Add intake_date column and unique constraint on medicine_intake_logs
--
-- Purpose:
--   1. Adds intake_date to cleanly track the date of intake in Manila timezone.
--   2. Enforces unique constraint (citizen_id, prescription_item_id, dose_index, intake_date)
--      so client upserts reliably prevent duplicate intake entries.
-- =============================================================================

-- 1. Add column if not exists
ALTER TABLE public.medicine_intake_logs
ADD COLUMN IF NOT EXISTS intake_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Manila')::date;

-- 2. Backfill any existing records
UPDATE public.medicine_intake_logs
SET intake_date = (created_at AT TIME ZONE 'Asia/Manila')::date
WHERE intake_date IS NULL;

-- 3. Deduplicate any existing records keeping the latest one before creating constraint
DELETE FROM public.medicine_intake_logs a
USING public.medicine_intake_logs b
WHERE a.id < b.id
  AND a.citizen_id = b.citizen_id
  AND a.prescription_item_id = b.prescription_item_id
  AND a.dose_index = b.dose_index
  AND a.intake_date = b.intake_date;

-- 4. Add unique constraint if not already present
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_intake_per_dose_per_day'
    ) THEN
        ALTER TABLE public.medicine_intake_logs
        ADD CONSTRAINT unique_intake_per_dose_per_day
        UNIQUE (citizen_id, prescription_item_id, dose_index, intake_date);
    END IF;
END $$;
