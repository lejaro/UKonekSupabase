-- Migration: Remove family infrastructure
-- Dropping family_number column and ensuring no references exist.

DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'citizens' 
        AND column_name = 'family_number'
    ) THEN
        ALTER TABLE public.citizens DROP COLUMN family_number;
    END IF;
END $$;

-- Update handle_new_user trigger function to ensure it doesn't try to use family_number metadata
-- (Though it wasn't in our previous check, this is a safety measure if the DB has a different version)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  v_role := lower(coalesce(new.raw_user_meta_data->>'role', ''));

  IF v_role = 'citizen' THEN
    INSERT INTO public.citizens (
      firstname, surname, middle_initial, date_of_birth, age,
      contact_number, sex, email, complete_address,
      emergency_contact_complete_name, emergency_contact_contact_number,
      relation, username, role, auth_user_id
    ) VALUES (
      coalesce(new.raw_user_meta_data->>'firstname', ''),
      coalesce(new.raw_user_meta_data->>'surname', ''),
      new.raw_user_meta_data->>'middle_initial',
      (new.raw_user_meta_data->>'date_of_birth')::date,
      (new.raw_user_meta_data->>'age')::integer,
      new.raw_user_meta_data->>'contact_number',
      new.raw_user_meta_data->>'sex',
      new.email,
      new.raw_user_meta_data->>'complete_address',
      new.raw_user_meta_data->>'emergency_contact_complete_name',
      new.raw_user_meta_data->>'emergency_contact_contact_number',
      new.raw_user_meta_data->>'relation',
      new.raw_user_meta_data->>'username',
      'citizen',
      new.id
    );
  END IF;

  RETURN new;
END;
$$;
