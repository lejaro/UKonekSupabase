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
  const { error } = await supabase
    .from('staff')
    .delete()
    .eq('id', id);

  if (error) {
    throw new Error(error.message || 'Unable to delete account.');
  }
}

export async function deleteStaffAccount(staffId) {
  const { error } = await supabase.rpc('delete_staff_member', { target_staff_id: staffId });
  if (error) {
    throw new Error(error.message || 'Failed to delete account.');
  }
}

export async function resetStaffPassword(staffId, newPassword) {
  const { data, error } = await supabase.rpc('reset_staff_password_admin', {
    target_staff_id: staffId,
    p_new_password: newPassword
  });

  if (error) {
    throw new Error(error.message || 'Failed to reset password.');
  }

  if (data && data.error) {
    throw new Error(data.error);
  }

  return data;
}
