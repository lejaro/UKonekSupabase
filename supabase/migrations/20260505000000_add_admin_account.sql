-- Add hardcoded admin account
-- Email: admin@ukonek.local
-- Password: ukonek123
-- Dashboard: Same as doctor (full access)

-- Note: The password hash below is for 'ukonek123' using bcrypt
-- You can generate a new hash using: https://bcrypt-generator.com/ or bcrypt libraries
-- This hash is: $2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy

-- Insert into auth.users (hardcoded UUID and password hash)
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change
)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'admin@ukonek.local',
  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
  now(),
  now(),
  now(),
  '',
  '',
  '',
  ''
)
ON CONFLICT (id) DO NOTHING;

-- Insert into auth.identities (without ON CONFLICT since there's no unique constraint)
INSERT INTO auth.identities (
  provider_id,
  id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
SELECT
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'a0000000-0000-0000-0000-000000000001'::uuid,
  jsonb_build_object(
    'sub', 'a0000000-0000-0000-0000-000000000001',
    'email', 'admin@ukonek.local',
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(),
  now(),
  now()
WHERE NOT EXISTS (
  SELECT 1 FROM auth.identities 
  WHERE user_id = 'a0000000-0000-0000-0000-000000000001'::uuid 
  AND provider = 'email'
);

-- Insert into public.staff table with role 'admin'
-- Admin has same dashboard access as doctor
INSERT INTO public.staff (
  auth_user_id,
  email,
  first_name,
  middle_name,
  last_name,
  username,
  employee_id,
  role,
  consent_given,
  status,
  created_at
)
VALUES (
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'admin@ukonek.local',
  'System',
  '',
  'Administrator',
  'admin',
  'ADMIN-001',
  'admin',
  true,
  'Active',
  now()
)
ON CONFLICT (auth_user_id) DO NOTHING;

-- Grant admin same permissions as doctor for dashboard access
-- The dashboard checks for role 'doctor' or 'admin' for full access
COMMENT ON COLUMN public.staff.role IS 'Staff role: doctor, nurse, pharmacist, admin, receptionist';
