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

export async function listPendingStaff() {
  const { data, error } = await supabase
    .from('pending_staff')
    .select('*')
    .order('id', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load pending registrations.');
  }

  return data || [];
}

export async function createPendingStaff(payload) {
  const { error } = await supabase
    .from('pending_staff')
    .insert(payload);

  if (error) {
    throw new Error(error.message || 'Unable to submit registration.');
  }

  return true;
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

export async function approvePendingStaff(pendingId) {
  const { error } = await supabase.rpc('approve_pending_staff', { pending_id: pendingId });
  if (error) {
    throw new Error(error.message || 'Approval failed.');
  }
}

export async function rejectPendingStaff(pendingId) {
  const { error } = await supabase.rpc('reject_pending_staff', { pending_id: pendingId });
  if (error) {
    throw new Error(error.message || 'Rejection failed.');
  }
}

export async function deleteStaffAccount(staffId) {
  const { error } = await supabase.rpc('delete_staff_member', { target_staff_id: staffId });
  if (error) {
    throw new Error(error.message || 'Failed to delete account.');
  }
}
