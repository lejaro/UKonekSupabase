# Queue Management Module

## Purpose

Provides same-day service queue ticketing, lane movement (waiting/on-call/serving), and dashboard metrics.

## Primary Tables

### queue_tickets
- Per-day queue tickets grouped by `service_key`.
- Tracks ticket progression and timestamps.

Key fields:
- `queue_date`, `service_key`, `service_label`
- `queue_number`, `ticket_code`
- `citizen_id` (FK -> citizens)
- `citizen_type`, `status`
- `served_at`, `completed_at`

## Domain Values

### Citizen type
- `regular`
- `pwd`
- `pregnant`

### Queue status
- `waiting`
- `on_call`
- `serving`
- `completed`
- `cancelled`

## RPC Contracts

- `list_available_queue_services(p_date)`
- `create_queue_ticket(p_service_key, p_service_label, p_citizen_type, p_reason, p_symptoms)`
- `get_my_queue_dashboard()`
- `set_queue_current_serving(p_queue_ticket_id)`
- `advance_queue_ticket(p_queue_date, p_service_key)`
- `purge_completed_queue_tickets(p_queue_date, p_service_key, p_grace_seconds)`

## Frontend Data Shape (Web Queue Board)

Queue ticket payload used by web module includes:
- Ticket fields: `id`, `queue_date`, `service_key`, `reason`, `symptoms`, `queue_number`, `ticket_code`, `service_label`, `citizen_type`, `status`, `created_at`, `served_at`, `completed_at`
- Nested citizen object: `citizen: { id, firstname, surname, email }`

## RLS Summary

- Citizens can insert and read their own tickets.
- Active staff and admin can read/update queue tickets.
