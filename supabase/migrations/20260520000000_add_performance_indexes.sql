-- =============================================================================
-- Migration: Add Performance Indexes to Prevent High DB RAM & Committed Memory Saturation
-- Fixes sequential scans in RLS policies (is_admin, auth_user_id) and core queries.
-- =============================================================================

-- 1. Indexes for RLS policy checks (CRITICAL for RAM optimization)
CREATE INDEX IF NOT EXISTS idx_staff_auth_user_id ON public.staff(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_staff_email_lower ON public.staff(lower(email));
CREATE INDEX IF NOT EXISTS idx_citizens_auth_user_id ON public.citizens(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_citizens_email_lower ON public.citizens(lower(email));

-- 2. Indexes for Queue operations
CREATE INDEX IF NOT EXISTS idx_queue_tickets_date_status ON public.queue_tickets(queue_date, status);
CREATE INDEX IF NOT EXISTS idx_queue_tickets_citizen_id ON public.queue_tickets(citizen_id);
CREATE INDEX IF NOT EXISTS idx_queue_tickets_ticket_code ON public.queue_tickets(ticket_code);

-- 3. Indexes for Clinical & Consultation records
CREATE INDEX IF NOT EXISTS idx_consultations_patient ON public.consultations(patient_citizen_id);
CREATE INDEX IF NOT EXISTS idx_consultations_doctor ON public.consultations(doctor_staff_id);
CREATE INDEX IF NOT EXISTS idx_consultations_date ON public.consultations(consulted_at DESC);

-- 4. Indexes for Prescriptions & Pharmacy
CREATE INDEX IF NOT EXISTS idx_prescription_headers_doctor ON public.prescription_headers(doctor_staff_id);
CREATE INDEX IF NOT EXISTS idx_prescription_headers_consultation ON public.prescription_headers(consultation_id);
CREATE INDEX IF NOT EXISTS idx_prescription_items_header ON public.prescription_items(prescription_id);

-- 5. Indexes for Doctor Schedules (appointments table may not exist in remote)
CREATE INDEX IF NOT EXISTS idx_doctor_schedules_doc_date ON public.doctor_schedules(doctor_staff_id, schedule_date);
