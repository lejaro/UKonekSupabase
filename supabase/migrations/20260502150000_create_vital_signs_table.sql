-- Create vital_signs table for patient assessments
CREATE TABLE IF NOT EXISTS public.vital_signs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    citizen_id BIGINT NOT NULL REFERENCES public.citizens(id) ON DELETE CASCADE,
    nurse_id BIGINT REFERENCES public.staff(id) ON DELETE SET NULL,
    chief_complaint TEXT NOT NULL,
    blood_pressure TEXT, -- Format: "120/80"
    respiratory_rate INTEGER,
    temperature DECIMAL(4,1), -- Format: 36.5
    oxygen_saturation INTEGER, -- Percentage: 98
    current_medications TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_vital_signs_citizen_id ON public.vital_signs(citizen_id);
CREATE INDEX IF NOT EXISTS idx_vital_signs_created_at ON public.vital_signs(created_at);

-- Set permissions for vital_signs table
ALTER TABLE public.vital_signs ENABLE ROW LEVEL SECURITY;

-- Policy: Allow all authenticated users (staff/doctors) to insert vital signs
CREATE POLICY "Allow staff to insert vital signs" ON public.vital_signs
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- Policy: Allow staff to view all vital signs
CREATE POLICY "Allow staff to view vital signs" ON public.vital_signs
    FOR SELECT TO authenticated
    USING (true);
