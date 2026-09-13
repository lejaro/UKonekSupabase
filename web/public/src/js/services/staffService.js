import { supabase } from '../lib/supabaseClient.js';

async function assertCanModifyAccounts(actionDescription = 'modify user accounts') {
  const { data: authData } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }));
  const currentAuthUser = authData?.user;
  if (!currentAuthUser) {
    throw new Error(`Authentication required to ${actionDescription}.`);
  }

  const { data: staffRecord } = await supabase
    .from('staff')
    .select('id, role, status')
    .eq('auth_user_id', currentAuthUser.id)
    .maybeSingle();

  const role = String(staffRecord?.role || '').trim().toLowerCase();
  if (role === 'nurse' || role === 'staff') {
    throw new Error(`Forbidden: Nurses are not permitted to ${actionDescription}.`);
  }

  if (role !== 'admin') {
    throw new Error(`Forbidden: Admin role required to ${actionDescription}.`);
  }

  return { currentAuthUser, staffRecord };
}

export async function listStaff() {
  const { data, error } = await supabase
    .from('staff')
    .select('id, first_name, last_name, email, role, status, employee_id, doctor_specialization, is_online, last_seen, auth_user_id, availability_status')
    .order('id', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load staff records.');
  }

  return data || [];
}

export async function updateStaffById(id, payload) {
  await assertCanModifyAccounts('modify user accounts');

  // Attempt using update_staff_account_admin RPC first
  try {
    const { data: rpcData, error: rpcError } = await supabase.rpc('update_staff_account_admin', {
      target_staff_id: id,
      p_first_name: payload.first_name || null,
      p_last_name: payload.last_name || null,
      p_middle_name: payload.middle_name || null,
      p_username: payload.username || null,
      p_email: payload.email || null,
      p_employee_id: payload.employee_id || null,
      p_role: payload.role || null,
      p_birthday: payload.birthday || null
    });

    if (!rpcError && rpcData?.success) {
      return rpcData.staff;
    }
    if (rpcError && /forbidden.*admin role required/i.test(rpcError.message)) {
      throw new Error('Forbidden: Nurses and non-admin users are not permitted to modify user accounts.');
    }
  } catch (rpcErr) {
    if (/forbidden/i.test(rpcErr?.message)) throw rpcErr;
  }

  const { data, error } = await supabase
    .from('staff')
    .update(payload)
    .eq('id', id)
    .select()
    .maybeSingle();

  if (error) {
    const msg = error.message || 'Unable to update account.';
    if (/forbidden|permission denied|policy/i.test(msg)) {
      throw new Error('Forbidden: Nurses and non-admin users are not permitted to modify user accounts.');
    }
    throw new Error(msg);
  }

  return data;
}

export async function deleteStaffById(id) {
  const { currentAuthUser } = await assertCanModifyAccounts('delete user accounts');
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
  const { currentAuthUser } = await assertCanModifyAccounts('delete user accounts');
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
      throw new Error('Forbidden: Nurses and non-admin users are not permitted to delete user accounts.');
    }
    throw new Error(msg);
  }
}

export async function resetStaffPassword(staffId, newPassword) {
  await assertCanModifyAccounts('reset user passwords');

  const { data, error } = await supabase.rpc('reset_staff_password_admin', {
    target_staff_id: staffId,
    p_new_password: newPassword
  });

  if (error) {
    const msg = error.message || 'Failed to reset password.';
    if (/forbidden.*admin role required/i.test(msg)) {
      throw new Error('Forbidden: Nurses and non-admin users are not permitted to reset user passwords.');
    }
    throw new Error(msg);
  }

  if (data && data.error) {
    if (/forbidden.*admin role required/i.test(data.error)) {
      throw new Error('Forbidden: Nurses and non-admin users are not permitted to reset user passwords.');
    }
    throw new Error(data.error);
  }

  return data;
}
