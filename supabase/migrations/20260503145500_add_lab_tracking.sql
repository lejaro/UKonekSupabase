-- Create lab_orders table for tracking clinical tests.

CREATE TABLE IF NOT EXISTS public.lab_orders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    consultation_id BIGINT REFERENCES public.consultations(id) ON DELETE CASCADE,
    patient_citizen_id BIGINT REFERENCES public.citizens(id) ON DELETE CASCADE,
    doctor_staff_id BIGINT REFERENCES public.staff(id) ON DELETE SET NULL,
    test_name TEXT NOT NULL,
    priority TEXT DEFAULT 'Regular', -- Regular, Urgent
    status TEXT DEFAULT 'Pending', -- Pending, Completed, Cancelled
    results_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    completed_at TIMESTAMPTZ
);

-- RLS
ALTER TABLE public.lab_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow staff to view lab orders" ON public.lab_orders
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "Allow staff to manage lab orders" ON public.lab_orders
    FOR ALL TO authenticated
    USING (true);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_lab_orders_consultation_id ON public.lab_orders(consultation_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_status ON public.lab_orders(status);
