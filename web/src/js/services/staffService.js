import { supabase } from '../lib/supabaseClient.js';

export async function listStaff() {
  const { data, error } = await supabase
    .from('staff')
    .select('*')
    .order('id', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load staff records.');
  }

  return data || [];
}

export async function updateStaffById(id, payload) {
  const { data, error } = await supabase
    .from('staff')
    .update(payload)
    .eq('id', id)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Unable to update account.');
  }

  return data;
}

export async function deleteStaffById(id) {
  const { data: authData } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }));
  const currentAuthUser = authData?.user;
  if (currentAuthUser) {
    const { data: staffRecord } = await supabase
      .from('staff')
      .select('id, auth_user_id')
      .eq('id', id)
      .maybeSingle();

    if (staffRecord && String(staffRecord.auth_user_id) === String(currentAuthUser.id)) {
      throw new Error('Guardrail Active: You cannot delete your own account.');
    }
  }

  const { error } = await supabase
    .from('staff')
    .delete()
    .eq('id', id);

  if (error) {
    throw new Error(error.message || 'Unable to delete account.');
  }
}

export async function deleteStaffAccount(staffId) {
  const { data: authData } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }));
  const currentAuthUser = authData?.user;
  if (currentAuthUser) {
    const { data: staffRecord } = await supabase
      .from('staff')
      .select('id, auth_user_id')
      .eq('id', staffId)
      .maybeSingle();

    if (staffRecord && String(staffRecord.auth_user_id) === String(currentAuthUser.id)) {
      throw new Error('Guardrail Active: You cannot delete your own account.');
    }
  }

  const { error } = await supabase.rpc('delete_staff_member', { target_staff_id: staffId });
  if (error) {
    const msg = error.message || 'Failed to delete account.';
    if (/forbidden.*admin role required/i.test(msg)) {
      throw new Error('Forbidden: admin role required. Please run migration 20260907001500_fix_is_admin_and_schedule_rpcs.sql in your Supabase SQL Editor to grant admin account permissions.');
    }
    throw new Error(msg);
  }
}

export async function resetStaffPassword(staffId, newPassword) {
  const { data, error } = await supabase.rpc('reset_staff_password_admin', {
    target_staff_id: staffId,
    p_new_password: newPassword
  });

  if (error) {
    const msg = error.message || 'Failed to reset password.';
    if (/forbidden.*admin role required/i.test(msg)) {
      throw new Error('Forbidden: admin role required. Please run migration 20260907001500_fix_is_admin_and_schedule_rpcs.sql in your Supabase SQL Editor to grant admin account permissions.');
    }
    throw new Error(msg);
  }

  if (data && data.error) {
    if (/forbidden.*admin role required/i.test(data.error)) {
      throw new Error('Forbidden: admin role required. Please run migration 20260907001500_fix_is_admin_and_schedule_rpcs.sql in your Supabase SQL Editor to grant admin account permissions.');
    }
    throw new Error(data.error);
  }

  return data;
}
