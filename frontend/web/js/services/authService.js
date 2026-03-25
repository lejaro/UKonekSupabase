import { supabase } from '../lib/supabaseClient.js';

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());
}

export async function resolveStaffLoginEmail(identifier) {
  const trimmedIdentifier = String(identifier || '').trim();
  if (!isEmail(trimmedIdentifier)) {
    throw new Error('Please enter your email address.');
  }

  return trimmedIdentifier.toLowerCase();
}

export async function signInStaff({ identifier, password, selectedRole }) {
  const email = await resolveStaffLoginEmail(identifier);

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error || !data?.user) {
    throw new Error('Invalid credentials.');
  }

  const { data: staffRole, error: roleError } = await supabase.rpc('get_staff_role');
  if (roleError || !staffRole) {
    await supabase.auth.signOut();
    throw new Error('Account not found or not yet active.');
  }

  if (selectedRole && String(staffRole).toLowerCase() !== String(selectedRole).toLowerCase()) {
    await supabase.auth.signOut();
    throw new Error('Selected role does not match this account.');
  }

  return data.user;
}

export async function getAuthenticatedStaffProfile() {
  const { data: userResult, error: userError } = await supabase.auth.getUser();
  if (userError || !userResult?.user) {
    return null;
  }

  const { data: profile, error: profileError } = await supabase.rpc('get_staff_profile');
  if (profileError || !profile) {
    return null;
  }

  return typeof profile === 'string' ? JSON.parse(profile) : profile;
}

export async function signOutStaff() {
  await supabase.auth.signOut();
}

export async function requestPasswordReset(email) {
  const normalizedEmail = String(email || '').trim().toLowerCase();
  const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail);
  if (error) {
    throw new Error(error.message || 'Failed to send reset email.');
  }
}

export async function requestRegistrationEmailOtp(email) {
  const normalizedEmail = String(email || '').trim().toLowerCase();

  const { error } = await supabase.auth.signInWithOtp({
    email: normalizedEmail,
    options: {
      shouldCreateUser: true,
      data: { role: 'staff_pending' }
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

export async function ensureRecoverySessionFromHash() {
  const hash = window.location.hash || '';
  if (!hash.includes('type=recovery')) {
    return;
  }

  const hashParams = new URLSearchParams(hash.replace(/^#/, ''));
  const accessToken = hashParams.get('access_token');
  const refreshToken = hashParams.get('refresh_token');

  if (!accessToken || !refreshToken) {
    return;
  }

  const { error } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken
  });

  if (error) {
    throw new Error(error.message || 'Unable to establish recovery session.');
  }

  history.replaceState({}, document.title, window.location.pathname + window.location.search);
}

export async function resetPasswordWithRecoverySession(newPassword) {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData?.session) {
    throw new Error('Recovery session missing or expired. Request a new reset link.');
  }

  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) {
    throw new Error(error.message || 'Failed to reset password.');
  }
}
