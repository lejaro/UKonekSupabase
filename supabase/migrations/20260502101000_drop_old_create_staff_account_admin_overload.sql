-- Drop legacy create_staff_account_admin overload with employee_id and specialization args.

drop function if exists public.create_staff_account_admin(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_birthday date,
  p_gender text,
  p_username text,
  p_employee_id text,
  p_email text,
  p_role text,
  p_doctor_specialization text,
  p_password text,
  p_consent_given boolean,
  p_status text
);
