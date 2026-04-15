# Communication and Feedback Module

## Purpose

Handles outbound information to users (announcements) and inbound user messages (feedback).

## Primary Tables

### announcements
- Staff-authored communication posts.
- Visibility-scoped for audience targeting.

Key fields:
- `title`, `content`
- `visibility` (`all`, `staff`, `citizen`)
- `created_by_staff_id` (FK -> staff)

### feedbacks
- Citizen feedback submissions with optional rating.

Key fields:
- `citizen_id` (optional FK -> citizens)
- `from_email`, `subject`, `message`, `rating`

## Trigger Functions

- `set_announcements_updated_at()`
- `set_feedbacks_updated_at()`

## RLS Summary

- Announcements: active staff read; admin write/delete.
- Feedbacks: active staff read; citizens insert; admin full management.
