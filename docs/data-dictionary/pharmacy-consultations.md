# Pharmacy and Consultations Module

## Purpose

Supports clinical consultation records, prescriptions, and medicine inventory management.

## Primary Tables

### medicines
- Inventory table with quantity and soft-delete support (`archived_at`).
- Active-name uniqueness via partial index.

Key fields:
- `name`, `qty`, `unit`, `archived_at`
- `created_by_staff_id` (FK -> staff)

### consultations
- Clinical consultation record.

Key fields:
- `patient_identifier`
- `patient_citizen_id` (FK -> citizens)
- `doctor_staff_id` (FK -> staff)
- `symptoms`, `diagnosis`, `notes`, `consulted_at`

### prescription_headers
- Prescription envelope/header linked to consultation and doctor.

Key fields:
- `consultation_id` (FK -> consultations)
- `doctor_staff_id` (FK -> staff)
- `patient_identifier`, `issued_at`

### prescription_items
- Line-item medicines under a prescription header.

Key fields:
- `prescription_id` (FK -> prescription_headers)
- `medicine_name`, `quantity`, `unit`

## RPC Contracts

- `get_my_prescribed_medicines(p_limit)`

## Trigger Functions

- `set_medicines_updated_at()`
- `set_consultations_updated_at()`
- `set_prescription_headers_updated_at()`

## RLS Summary

- Medicines: active staff can read; write permissions vary by role; hard delete admin-only.
- Consultations/prescriptions: active staff can read; inserts restricted to active doctors under ownership checks.
