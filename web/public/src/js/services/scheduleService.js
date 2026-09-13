import { supabase } from '../lib/supabaseClient.js';

/**
 * Doctor Schedule Service
 * Encapsulates doctor schedule fetching, creation, updates, and deletion.
 */

/**
 * List available doctor schedules using the official RPC.
 * @param {string} [dateFrom] - YYYY-MM-DD
 * @param {string} [dateTo] - YYYY-MM-DD
 * @returns {Promise<Array>}
 */
export async function listAvailableDoctorSchedules(dateFrom, dateTo) {
  const from = dateFrom || new Date().toISOString().split('T')[0];
  const to = dateTo || new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0];

  const { data, error } = await supabase.rpc('list_available_doctor_schedules', {
    p_date_from: from,
    p_date_to: to,
  });

  if (error) {
    throw new Error(error.message || 'Failed to list available doctor schedules.');
  }

  return data || [];
}

/**
 * List raw doctor schedule rows with staff join for administrative dashboard views.
 * @param {Object} [options]
 * @param {string} [options.from] - YYYY-MM-DD
 * @param {string} [options.to] - YYYY-MM-DD
 * @param {number|string} [options.doctorStaffId]
 * @returns {Promise<Array>}
 */
export async function listDoctorSchedules({ from, to, doctorStaffId } = {}) {
  let query = supabase
    .from('doctor_schedules')
    .select(`
      id,
      doctor_staff_id,
      schedule_date,
      start_time,
      end_time,
      notes,
      doctor:staff!doctor_staff_id (
        id,
        first_name,
        last_name,
        doctor_specialization,
        status
      )
    `)
    .order('schedule_date', { ascending: true })
    .order('start_time', { ascending: true });

  if (from) {
    query = query.gte('schedule_date', from);
  }

  if (to) {
    query = query.lte('schedule_date', to);
  }

  if (doctorStaffId) {
    query = query.eq('doctor_staff_id', doctorStaffId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list doctor schedules.');
  }

  return data || [];
}

/**
 * Get a single schedule record by ID.
 * @param {number|string} id
 * @returns {Promise<Object|null>}
 */
export async function getDoctorScheduleById(id) {
  const { data, error } = await supabase
    .from('doctor_schedules')
    .select(`
      id,
      doctor_staff_id,
      schedule_date,
      start_time,
      end_time,
      notes,
      doctor:staff!doctor_staff_id (id, first_name, last_name)
    `)
    .eq('id', id)
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to fetch doctor schedule.');
  }

  return data;
}

/**
 * Create or update a doctor schedule.
 * @param {Object} payload
 * @param {number} payload.doctor_staff_id
 * @param {string} payload.schedule_date - YYYY-MM-DD
 * @param {string} payload.start_time - HH:MM:SS
 * @param {string} payload.end_time - HH:MM:SS
 * @param {string} [payload.notes]
 * @param {number} [payload.created_by_staff_id]
 * @param {number|string} [id] - Optional ID for updating an existing schedule
 * @returns {Promise<Object>}
 */
export async function saveDoctorSchedule(payload, id = null) {
  if (!payload.doctor_staff_id) {
    throw new Error('Doctor staff ID is required.');
  }
  if (!payload.schedule_date) {
    throw new Error('Schedule date is required.');
  }
  if (!payload.start_time || !payload.end_time) {
    throw new Error('Start and end times are required.');
  }

  let result;
  if (id) {
    result = await supabase
      .from('doctor_schedules')
      .update(payload)
      .eq('id', id)
      .select()
      .maybeSingle();
  } else {
    result = await supabase
      .from('doctor_schedules')
      .insert(payload)
      .select()
      .maybeSingle();
  }

  if (result.error) {
    throw new Error(result.error.message || 'Failed to save doctor schedule.');
  }

  return result.data;
}

/**
 * Delete a doctor schedule by ID.
 * @param {number|string} id
 * @returns {Promise<boolean>}
 */
export async function deleteDoctorSchedule(id) {
  // First attempt using admin RPC if available
  const rpcResult = await supabase.rpc('delete_doctor_schedule_admin', {
    p_id: Number(id),
  });

  if (!rpcResult.error) {
    return true;
  }

  // Fallback to direct delete
  const { error } = await supabase
    .from('doctor_schedules')
    .delete()
    .eq('id', id);

  if (error) {
    throw new Error(error.message || 'Failed to delete doctor schedule.');
  }

  return true;
}
