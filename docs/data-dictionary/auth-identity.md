# Auth and Identity Module

## Purpose

Manages identity linkage between Supabase Auth users and application profiles for staff and citizens.

## Primary Tables

### staff
- Core staff profile record for admin, doctor, nurse, specialist, and staff roles.
- Identity link: `auth_user_id` (unique).
- Access-critical fields: `role`, `status`, `doctor_specialization`, `is_online`, `last_seen`.

### citizens
- Core citizen profile record.
- Identity link: `auth_user_id` (unique).
- Includes personal and emergency contact profile fields.

### pending_citizen_signups
- Pre-auth OTP staging table for citizen signup.
- Stores `profile` JSON, `otp_hash`, expiry, attempts, verification and consumption timestamps.
- Blocked from normal client access through RLS; service-role path only.

## Key Relationships

- `staff.auth_user_id` -> Supabase `auth.users.id` (logical, cross-schema)
- `citizens.auth_user_id` -> Supabase `auth.users.id` (logical, cross-schema)

## RPC and Trigger Contracts

### Role/Profile helpers
- `is_admin()`
- `get_staff_role()`
- `get_staff_profile()`
- `set_staff_presence(p_is_online)`

### Staff account management
- `create_staff_account_admin(...)`
- `delete_staff_member(target_staff_id)`
- `reset_staff_password_admin(...)`
- `set_staff_specialization_admin(...)`
- `set_my_doctor_specialization(p_specialization)`
- `update_my_staff_profile(...)`
- `link_staff_to_auth(p_email, p_auth_user_id)`

### Auth bootstrap
- `handle_new_user()` trigger function

## Edge Functions

### citizen-request-otp
- Inserts/upserts `pending_citizen_signups`.
- Sends OTP email via Supabase Auth OTP flow.

### citizen-verify-otp
- Validates OTP hash, expiry, and attempts.
- Marks `verified_at` when successful.

### citizen-complete-signup
- Requires verified pending row.
- Creates auth user and marks `consumed_at`.

## Common Status/Domain Values

- Staff role examples: `admin`, `doctor`, `nurse`, `staff`, `specialist`
- Staff status is normalized with trimmed/lower-compare policy checks, expected active state: `Active`
