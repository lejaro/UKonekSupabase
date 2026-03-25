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

export async function signInStaff({ identifier, password }) {
  const email = await resolveStaffLoginEmail(identifier);

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password
  });

  if (error || !data?.user) {
    throw new Error('Invalid email or password.');
  }

  // User authenticated with Auth, now check if they're an active staff member
  const { data: staffRole, error: roleError } = await supabase.rpc('get_staff_role');
  
  if (roleError) {
    console.error('Staff role lookup error:', roleError);
    await supabase.auth.signOut();
    throw new Error(`Error checking staff status: ${roleError.message || 'unknown error'}`);
  }

  if (!staffRole) {
    // No active staff account found - check status and give specific message
    const { data: statusCheck, error: statusError } = await supabase.rpc('check_pending_staff_status', {
      p_email: email
    });

    await supabase.auth.signOut();

    if (statusCheck?.is_active_staff) {
      // Account is active but auth link may be missing
      throw new Error('Account is active in the system but authentication failed. Please try resetting your password.');
    } else if (statusCheck?.is_pending) {
      throw new Error('Your account is pending approval. Please contact your administrator.');
    } else if (statusCheck?.needs_admin_approval) {
      throw new Error('Your account exists but is not yet active. Please contact your administrator.');
    } else {
      throw new Error('Your account does not exist in the system. Please contact your administrator.');
    }
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
  if (!isEmail(normalizedEmail)) {
    throw new Error('Please enter a valid email address.');
  }

  const resetPageUrl = `${window.location.origin}/frontend/web/html/reset-password.html`;
  
  const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail, {
    redirectTo: resetPageUrl
  });
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
    // Not a recovery link, silently continue
    return false;
  }

  const hashParams = new URLSearchParams(hash.replace(/^#/, ''));
  const accessToken = hashParams.get('access_token');
  const refreshToken = hashParams.get('refresh_token');

  if (!accessToken || !refreshToken) {
    throw new Error('Recovery link is invalid or malformed.');
  }

  const { error } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken
  });

  if (error) {
    throw new Error('This recovery link has expired. Please request a new one.');
  }

  // Clean the URL history
  history.replaceState({}, document.title, window.location.pathname + window.location.search);
  return true;
}

export async function resetPasswordWithRecoverySession(newPassword) {
  // Validate password strength FIRST
  if (!newPassword) {
    throw new Error('Password is required.');
  }

  if (newPassword.length < 6) {
    throw new Error('Password must be at least 6 characters long.');
  }

  // Ensure password has at least one letter and one number (best practice)
  if (!/[a-zA-Z]/.test(newPassword) || !/\d/.test(newPassword)) {
    console.warn('Password does not contain mix of letters and numbers - may reduce security');
  }

  // Get current session (recovery session from reset link)
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !sessionData?.session) {
    throw new Error('Recovery session missing or expired. Request a new reset link.');
  }

  const userId = sessionData.session.user?.id;
  const userEmail = sessionData.session.user?.email;
  console.log('Resetting password for user:', userId, 'Email:', userEmail);

  // Update password in Auth
  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) {
    console.error('Password update error:', error);
    throw new Error(error.message || 'Failed to reset password. Please try again.');
  }

  console.log('Password updated successfully');

  // Give Supabase a moment to persist the password change
  await new Promise(resolve => setTimeout(resolve, 500));

  // NOW: Ensure the staff account is linked to the auth user
  // This handles the case where pending_staff was created but auth_user_id wasn't set
  try {
    const { error: updateError } = await supabase.rpc('link_staff_to_auth', {
      p_email: userEmail,
      p_auth_user_id: userId
    });

    if (updateError) {
      console.warn('Staff linking error (non-critical):', updateError);
      // Don't throw - this is a helper function, password reset is already successful
    } else {
      console.log('Staff account linked to auth user');
    }
  } catch (err) {
    console.warn('Staff linking failed:', err);
  }

  // Sign out after password reset - clears all sessions and tokens
  const { error: signOutError } = await supabase.auth.signOut({ scope: 'global' });
  if (signOutError) {
    console.warn('Sign out error (non-critical):', signOutError);
  }

  console.log('User signed out - password reset complete. Please log in with new password.');
}
