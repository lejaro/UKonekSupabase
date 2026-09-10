import { supabase } from '../lib/supabaseClient.js';

/**
 * Pharmacy & Inventory Service
 * Encapsulates medicines catalog, stock updates, prescriptions, and dispense logs.
 */

/**
 * List medicines from the clinic inventory.
 * @param {Object} [options]
 * @param {boolean} [options.includeArchived=false]
 * @param {number} [options.limit=100]
 * @returns {Promise<Array>}
 */
export async function listMedicines({ includeArchived = false, limit = 100 } = {}) {
  let query = supabase
    .from('medicines')
    .select('*')
    .order('brand_name', { ascending: true })
    .limit(limit);

  if (!includeArchived) {
    query = query.is('archived_at', null);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list medicines.');
  }

  return data || [];
}

/**
 * Retrieve a medicine by primary key.
 * @param {number|string} id
 * @returns {Promise<Object|null>}
 */
export async function getMedicineById(id) {
  const { data, error } = await supabase
    .from('medicines')
    .select('*')
    .eq('id', id)
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to fetch medicine.');
  }

  return data;
}

/**
 * Create a new medicine entry in inventory.
 * @param {Object} payload
 * @returns {Promise<Object>}
 */
export async function createMedicine(payload) {
  const { data, error } = await supabase
    .from('medicines')
    .insert(payload)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to create medicine.');
  }

  return data;
}

/**
 * Update medicine properties (e.g. stock, pricing, expiry).
 * @param {number|string} id
 * @param {Object} payload
 * @returns {Promise<Object>}
 */
export async function updateMedicine(id, payload) {
  const { data, error } = await supabase
    .from('medicines')
    .update(payload)
    .eq('id', id)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to update medicine.');
  }

  return data;
}

/**
 * Soft-archive a medicine.
 * @param {number|string} id
 * @returns {Promise<Object>}
 */
export async function archiveMedicine(id) {
  return updateMedicine(id, { archived_at: new Date().toISOString() });
}

/**
 * List prescriptions with patient and doctor details.
 * @param {Object} [options]
 * @param {string} [options.status]
 * @param {number|string} [options.citizenId]
 * @param {number} [options.limit=50]
 * @returns {Promise<Array>}
 */
export async function listPrescriptions({ status, citizenId, limit = 50 } = {}) {
  let query = supabase
    .from('prescriptions')
    .select(`
      id,
      prescription_code,
      patient_identifier,
      patient_citizen_id,
      doctor_staff_id,
      dispensing_status,
      issued_at,
      dispensed_at,
      created_at,
      items:prescription_items (
        id,
        medicine_id,
        quantity,
        dosage,
        frequency,
        duration,
        instructions
      ),
      doctor:staff!doctor_staff_id (first_name, last_name),
      patient:citizens!patient_citizen_id (firstname, surname, age)
    `)
    .order('issued_at', { ascending: false })
    .limit(limit);

  if (status) {
    query = query.eq('dispensing_status', status);
  }

  if (citizenId) {
    query = query.eq('patient_citizen_id', citizenId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list prescriptions.');
  }

  return data || [];
}

/**
 * List dispense logs for dispensed medicines.
 * @param {Object} [options]
 * @param {number|string} [options.prescriptionId]
 * @param {number} [options.limit=50]
 * @returns {Promise<Array>}
 */
export async function listDispenseLogs({ prescriptionId, limit = 50 } = {}) {
  let query = supabase
    .from('prescription_dispense_logs')
    .select(`
      id,
      prescription_id,
      prescription_item_id,
      dispensed_quantity,
      unit,
      dispensed_at,
      note,
      pharmacist_staff_id,
      pharmacist:staff!pharmacist_staff_id (first_name, last_name)
    `)
    .order('dispensed_at', { ascending: false })
    .limit(limit);

  if (prescriptionId) {
    query = query.eq('prescription_id', prescriptionId);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list dispense logs.');
  }

  return data || [];
}

/**
 * Record a new dispense log entry.
 * @param {Object} payload
 * @returns {Promise<Object>}
 */
export async function recordDispenseLog(payload) {
  const insertData = {
    prescription_id: payload.prescription_id,
    prescription_item_id: payload.prescription_item_id || null,
    dispensed_quantity: payload.dispensed_quantity,
    unit: payload.unit || 'pcs',
    dispensed_at: payload.dispensed_at || new Date().toISOString(),
    note: payload.note || 'Fulfilled by Pharmacy',
    pharmacist_staff_id: payload.pharmacist_staff_id || null,
  };

  const { data, error } = await supabase
    .from('prescription_dispense_logs')
    .insert(insertData)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to record dispense log.');
  }

  return data;
}
