-- Expand clinical records for comprehensive consultation workflows.

-- 1. Update vital_signs table
ALTER TABLE public.vital_signs
ADD COLUMN IF NOT EXISTS heart_rate INTEGER;

-- 2. Update consultations table
ALTER TABLE public.consultations
ADD COLUMN IF NOT EXISTS hpi TEXT,
ADD COLUMN IF NOT EXISTS pmh TEXT,
ADD COLUMN IF NOT EXISTS allergies TEXT,
ADD COLUMN IF NOT EXISTS immunization_status TEXT,
ADD COLUMN IF NOT EXISTS social_history TEXT,
ADD COLUMN IF NOT EXISTS physical_exam JSONB,
ADD COLUMN IF NOT EXISTS differential_diagnosis TEXT,
ADD COLUMN IF NOT EXISTS lab_orders TEXT,
ADD COLUMN IF NOT EXISTS follow_up_date DATE;

-- 3. Update prescription_items table
ALTER TABLE public.prescription_items
ADD COLUMN IF NOT EXISTS dosage TEXT,
ADD COLUMN IF NOT EXISTS frequency TEXT,
ADD COLUMN IF NOT EXISTS instructions TEXT,
ADD COLUMN IF NOT EXISTS additional_info TEXT;
