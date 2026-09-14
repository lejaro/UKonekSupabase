import { supabase } from '../lib/supabaseClient.js';
import * as sessionAuth from './sessionAuth.js';

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());
}

export function isLocalEnvironment() {
  if (typeof window === 'undefined') return false;
  const host = window.location.hostname;
  const port = window.location.port;
  return (
    host === 'localhost' ||
    host === '127.0.0.1' ||
    !host ||
    port === '5500' ||
    port === '5501' ||
    window.location.protocol === 'file:'
  );
}

export async function resolveStaffLoginEmail(identifier) {
  const trimmed = String(identifier || '').trim();
  if (isEmail(trimmed)) {
    return trimmed.toLowerCase();
  }

  // Attempt lookup by username or employee_id from public.staff
  try {
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('email')
      .or(`username.ilike.%${trimmed}%,employee_id.ilike.%${trimmed}%`)
      .limit(1)
      .maybeSingle();

    if (!error && staffMember?.email) {
      console.log(`[Auth] Resolved identifier "${trimmed}" to email "${staffMember.email}"`);
      return String(staffMember.email).toLowerCase();
    }
  } catch (lookupErr) {
    console.warn('[Auth] Staff identifier lookup warning:', lookupErr);
  }

  throw new Error(`Account "${trimmed}" not found. Please enter your valid email address.`);
}

export async function signInStaff({ identifier, password }) {
  const email = await resolveStaffLoginEmail(identifier);
  const isLocalDev = isLocalEnvironment();

  console.log('[Auth] Attempting sign-in for:', email, isLocalDev ? '(Local Dev)' : '(Production)');

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error || !data?.user) {
    console.warn('[Auth] Supabase auth.signInWithPassword error:', error);

    // In local development, allow bypass if account exists as an active staff member in the database
    if (isLocalDev) {
      try {
        const { data: staffRecord, error: staffErr } = await supabase
          .from('staff')
          .select('id, first_name, last_name, email, username, role, employee_id, status')
          .ilike('email', email)
          .maybeSingle();

        if (!staffErr && staffRecord && String(staffRecord.status || '').toLowerCase() === 'active') {
          console.info('[Auth Local Dev] Active staff record found in database. Authorizing local session:', staffRecord);
          return {
            id: staffRecord.auth_user_id || `local-dev-${staffRecord.id}`,
            email: staffRecord.email,
            role: String(staffRecord.role || 'doctor').toLowerCase(),
            user_metadata: {
              first_name: staffRecord.first_name,
              last_name: staffRecord.last_name,
              role: staffRecord.role
            },
            isLocalDevBypass: true,
            staffRecord
          };
        }
      } catch (devLookupErr) {
        console.warn('[Auth Local Dev] Staff lookup fallback error:', devLookupErr);
      }
    }

    const rawMsg = String(error?.message || '').trim();
    if (/invalid login credentials/i.test(rawMsg)) {
      throw new Error('Invalid email or password. Please verify your credentials or check your account in Supabase.');
    }
    if (/email not confirmed/i.test(rawMsg)) {
      throw new Error('Email address has not been confirmed. Please confirm your email in Supabase Auth.');
    }
    throw new Error(rawMsg ? `Supabase Auth: ${rawMsg}` : 'Invalid email or password.');
  }

  // User authenticated with Auth, now check if they're an active staff member
  const { data: staffRole, error: roleError } = await supabase.rpc('get_staff_role');
  
  if (roleError) {
    console.error('Staff role lookup error:', roleError);
    if (!isLocalDev) {
      await supabase.auth.signOut();
    }

    const roleErrorMessage = String(roleError.message || 'unknown error');
    if (/non-volatile function|update is not allowed/i.test(roleErrorMessage)) {
      throw new Error('Login is blocked by an outdated database migration (staff role function). Apply latest Supabase migrations, then try again.');
    }

    if (!isLocalDev) {
      throw new Error(`Error checking staff status: ${roleErrorMessage}`);
    }
  }

  if (!staffRole && !isLocalDev) {
    await supabase.auth.signOut();
    throw new Error('Your account does not exist in the system. Please contact your administrator.');
  }

  try {
    await setStaffPresence(true);
    await supabase.rpc('log_staff_action', { p_action: 'login' });
  } catch (presenceError) {
    console.warn('Presence update warning on sign in:', presenceError);
  }

  return data.user;
}

export async function getAuthenticatedStaffProfile() {
  const isLocalDev = isLocalEnvironment();

  const { data: userResult, error: userError } = await supabase.auth.getUser().catch(() => ({ data: null, error: true }));
  if (userError || !userResult?.user) {
    if (isLocalDev) {
      const meta = sessionAuth.getAuthSessionMeta();
      const role = (sessionStorage.getItem('ukonek_role') || meta?.role || '').trim().toLowerCase();
      if (role && meta?.email) {
        return {
          id: meta.userId || 14,
          email: meta.email,
          role: role,
          username: meta.username || meta.email.split('@')[0],
          first_name: meta.firstName || 'Doctor',
          last_name: meta.lastName || 'Staff'
        };
      }
    }
    return null;
  }

  const { data: profile, error: profileError } = await supabase.rpc('get_staff_profile');
  if (profileError) {
    const profileErrorMessage = String(profileError.message || 'unknown error');
    if (/non-volatile function|update is not allowed/i.test(profileErrorMessage)) {
      throw new Error('Staff profile lookup failed due to an outdated database migration. Apply latest Supabase migrations for get_staff_profile/get_staff_role.');
    }
    throw new Error(`Error loading staff profile: ${profileErrorMessage}`);
  }

  if (!profile) {
    return null;
  }

  return typeof profile === 'string' ? JSON.parse(profile) : profile;
}

export async function signOutStaff() {
  try {
    await supabase.rpc('log_staff_action', { p_action: 'logout' }).catch(() => {});
  } catch (logError) {
    console.warn('Logging update warning on sign out:', logError);
  }

  try {
    await setStaffPresence(false);
  } catch (presenceError) {
    console.warn('Presence update warning on sign out:', presenceError);
  }

  await supabase.auth.signOut();
}

export async function setStaffPresence(isOnline = true) {
  const { data, error } = await supabase.rpc('set_staff_presence', {
    p_is_online: Boolean(isOnline)
  });

  if (error) {
    throw new Error(error.message || 'Failed to update staff presence.');
  }

  return Boolean(data);
}

export async function requestRegistrationEmailOtp(email) {
  const normalizedEmail = String(email || '').trim().toLowerCase();

  const { error } = await supabase.auth.signInWithOtp({
    email: normalizedEmail,
    options: {
      shouldCreateUser: true,
      data: { role: 'nurse' }
    }
  });

  if (error) {
    throw new Error(error.message || 'Failed to send verification code.');
  }
}

export async function verifyRegistrationEmailOtp(email, otp) {
  const normalizedEmail = String(email || '').trim().toLowerCase();
  const normalizedOtp = String(otp || '').trim();

  const { data, error } = await supabase.auth.verifyOtp({
    email: normalizedEmail,
    token: normalizedOtp,
    type: 'email'
  });

  if (error || !data?.user?.id) {
    throw new Error(error?.message || 'Invalid or expired verification code.');
  }

  const authUserId = data.user.id;
  await supabase.auth.signOut();

  return authUserId;
}

export async function completeStaffRegistration({
  profile,
  otp,
  username,
  password,
  consentGiven
}) {
  const normalizedEmail = String(profile?.email || '').trim().toLowerCase();
  const normalizedOtp = String(otp || '').trim();
  const normalizedUsername = String(username || '').trim();

  if (!normalizedEmail) {
    throw new Error('Registration email is required.');
  }

  if (!/^\d{6}$/.test(normalizedOtp)) {
    throw new Error('Please enter a valid 6-digit OTP.');
  }

  if (!normalizedUsername) {
    throw new Error('Username is required.');
  }

  if (!password || String(password).length < 6) {
    throw new Error('Password must be at least 6 characters long.');
  }

  const { data: otpData, error: otpError } = await supabase.auth.verifyOtp({
    email: normalizedEmail,
    token: normalizedOtp,
    type: 'email'
  });

  if (otpError || !otpData?.user?.id) {
    throw new Error(otpError?.message || 'Invalid or expired verification code.');
  }

  const authUserId = otpData.user.id;

  const { error: passwordError } = await supabase.auth.updateUser({ password });
  if (passwordError) {
    throw new Error(passwordError.message || 'Unable to set account password.');
  }

  const payload = {
    first_name: String(profile?.first_name || '').trim(),
    middle_name: String(profile?.middle_name || '').trim(),
    last_name: String(profile?.last_name || '').trim(),
    birthday: profile?.birthday || null,
    gender: String(profile?.gender || '').trim() || null,
    username: normalizedUsername,
    employee_id: String(profile?.employee_id || '').trim(),
    email: normalizedEmail,
    role: String(profile?.role || '').trim(),
    consent_given: Boolean(consentGiven),
    status: 'Active',
    auth_user_id: authUserId
  };

  const { error: staffError } = await supabase
    .from('staff')
    .upsert(payload, { onConflict: 'email' });

  if (staffError) {
    throw new Error(staffError.message || 'Unable to save staff registration.');
  }

  await supabase.auth.signOut();
  return { authUserId };
}
