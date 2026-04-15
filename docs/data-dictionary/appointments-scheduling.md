# Appointments and Scheduling Module

## Purpose

Supports doctor availability management and appointment booking/lifecycle.

## Primary Tables

### doctor_schedules
- Admin-managed slots per doctor.
- Unique slot per doctor/date/time range.
- Readable by active staff; write restricted to admin.

Key fields:
- `doctor_staff_id` (FK -> staff)
- `schedule_date`, `start_time`, `end_time`
- `created_by_staff_id` (FK -> staff)

### appointments
- Links citizen to doctor schedule slot intent.
- Contains status and notes fields for patient/doctor workflows.

Key fields:
- `citizen_id` (FK -> citizens)
- `doctor_staff_id` (FK -> staff)
- `appointment_date`, `appointment_time`
- `status`, `patient_notes`, `doctor_notes`

## Domain Values

### Appointment status
- `pending`
- `confirmed`
- `completed`
- `cancelled`
- `no-show`

## RPC Contracts

### Scheduling
- `list_doctor_schedules()`
- `list_available_doctor_schedules(...)`
- `upsert_doctor_schedule_admin(...)`
- `delete_doctor_schedule_admin(p_id)`
- `purge_expired_doctor_schedules()`

### Booking and listing
- `get_available_doctor_slots(p_doctor_staff_id, p_date_from, p_date_to)`
- `book_appointment(p_citizen_id, p_doctor_staff_id, p_appointment_date, p_appointment_time, p_patient_notes)`
- `list_my_appointments()`
- `list_doctor_appointments(p_status, p_date_from, p_date_to)`
- `list_all_appointments(p_status, p_date_from, p_date_to, p_doctor_staff_id)`

## RLS Summary

- Citizens can manage their own appointments under policy conditions.
- Doctors can view and update assigned appointments.
- Admin has broad management permissions.
