-- Add duration column to prescription_items
ALTER TABLE public.prescription_items
ADD COLUMN IF NOT EXISTS duration TEXT;
