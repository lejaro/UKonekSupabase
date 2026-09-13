import { supabase } from '../lib/supabaseClient.js';

/**
 * Consultation & Clinical Records Service
 * Encapsulates consultations, diagnoses, and vital signs operations.
 */

/**
 * List consultation records with optional filters.
 * @param {Object} [options]
 * @param {number|string} [options.patientCitizenId]
 * @param {number|string} [options.doctorStaffId]
 * @param {string} [options.since] - ISO timestamp
 * @param {number} [options.limit=50]
 * @returns {Promise<Array>}
 */
export async function listConsultations({
  patientCitizenId,
  doctorStaffId,
  since,
  limit = 50,
} = {}) {
  let query = supabase
    .from('consultations')
    .select(`
      id,
      patient_identifier,
      patient_citizen_id,
      doctor_staff_id,
      symptoms,
      diagnosis,
      notes,
      consulted_at,
      created_at,
      doctor:staff!doctor_staff_id (
        id,
        first_name,
        last_name,
        doctor_specialization
      ),
      patient:citizens!patient_citizen_id (
        id,
        firstname,
        surname,
        age,
        complete_address,
        contact_number
      )
    `)
    .order('consulted_at', { ascending: false })
    .limit(limit);

  if (patientCitizenId) {
    query = query.eq('patient_citizen_id', patientCitizenId);
  }

  if (doctorStaffId) {
    query = query.eq('doctor_staff_id', doctorStaffId);
  }

  if (since) {
    query = query.gte('consulted_at', since);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list consultations.');
  }

  return data || [];
}

/**
 * Get a single consultation by its primary key.
 * @param {number|string} consultationId
 * @returns {Promise<Object|null>}
 */
export async function getConsultationById(consultationId) {
  const { data, error } = await supabase
    .from('consultations')
    .select(`
      id,
      patient_identifier,
      patient_citizen_id,
      doctor_staff_id,
      symptoms,
      diagnosis,
      notes,
      consulted_at,
      created_at,
      doctor:staff!doctor_staff_id (first_name, last_name),
      patient:citizens!patient_citizen_id (firstname, surname, age)
    `)
    .eq('id', consultationId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to retrieve consultation.');
  }

  return data;
}

/**
 * Create a new consultation record.
 * @param {Object} payload
 * @param {string} [payload.patient_identifier]
 * @param {number} [payload.patient_citizen_id]
 * @param {number} payload.doctor_staff_id
 * @param {string} [payload.symptoms]
 * @param {string} payload.diagnosis
 * @param {string} [payload.notes]
 * @param {string} [payload.consulted_at]
 * @returns {Promise<Object>}
 */
export async function createConsultation(payload) {
  if (!payload.doctor_staff_id) {
    throw new Error('Attending doctor is required for consultation.');
  }
  if (!payload.diagnosis) {
    throw new Error('Diagnosis is required.');
  }

  const insertData = {
    patient_identifier: payload.patient_identifier || null,
    patient_citizen_id: payload.patient_citizen_id || null,
    doctor_staff_id: payload.doctor_staff_id,
    symptoms: (payload.symptoms || '').trim() || null,
    diagnosis: payload.diagnosis.trim(),
    notes: (payload.notes || '').trim() || null,
    consulted_at: payload.consulted_at || new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from('consultations')
    .insert(insertData)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to save consultation.');
  }

  return data;
}

/**
 * List vital signs records.
 * @param {Object} [options]
 * @param {number|string} [options.citizenId]
 * @param {string} [options.since] - ISO timestamp
 * @param {number} [options.limit=50]
 * @returns {Promise<Array>}
 */
export async function listVitalSigns({ citizenId, since, limit = 50 } = {}) {
  let query = supabase
    .from('vital_signs')
    .select(`
      id,
      citizen_id,
      created_at,
      blood_pressure,
      heart_rate,
      respiratory_rate,
      temperature,
      oxygen_saturation,
      chief_complaint,
      height_cm,
      weight_kg,
      bmi,
      citizen:citizens (
        id,
        firstname,
        surname,
        age
      )
    `)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (citizenId) {
    query = query.eq('citizen_id', citizenId);
  }

  if (since) {
    query = query.gte('created_at', since);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Failed to list vital signs.');
  }

  return data || [];
}

/**
 * Record new vital signs for a citizen.
 * @param {Object} payload
 * @param {number} payload.citizen_id
 * @param {string} [payload.blood_pressure]
 * @param {number|string} [payload.heart_rate]
 * @param {number|string} [payload.respiratory_rate]
 * @param {number|string} [payload.temperature]
 * @param {number|string} [payload.oxygen_saturation]
 * @param {string} [payload.chief_complaint]
 * @param {number} [payload.nurse_id]
 * @param {number} [payload.queue_ticket_id]
 * @param {number|string} [payload.height_cm]
 * @param {number|string} [payload.weight_kg]
 * @param {number|string} [payload.bmi]
 * @returns {Promise<Object>}
 */
export async function recordVitalSigns(payload) {
  if (!payload.citizen_id) {
    throw new Error('Citizen ID is required to record vital signs.');
  }

  const heightVal = payload.height_cm != null ? Number(payload.height_cm) : (payload.height != null ? Number(payload.height) : null);
  const weightVal = payload.weight_kg != null ? Number(payload.weight_kg) : (payload.weight != null ? Number(payload.weight) : null);
  let bmiVal = payload.bmi != null ? Number(payload.bmi) : null;
  if (!bmiVal && heightVal && weightVal && heightVal > 0 && weightVal > 0) {
    const hm = heightVal / 100;
    bmiVal = Number((weightVal / (hm * hm)).toFixed(1));
  }

  const insertData = {
    citizen_id: payload.citizen_id,
    blood_pressure: (payload.blood_pressure || '').trim() || null,
    heart_rate: payload.heart_rate != null ? Number(payload.heart_rate) : null,
    respiratory_rate: payload.respiratory_rate != null ? Number(payload.respiratory_rate) : null,
    temperature: payload.temperature != null ? Number(payload.temperature) : null,
    oxygen_saturation: payload.oxygen_saturation != null ? Number(payload.oxygen_saturation) : null,
    chief_complaint: (payload.chief_complaint || '').trim() || null,
    nurse_id: payload.nurse_id || null,
    queue_ticket_id: payload.queue_ticket_id || null,
    height_cm: heightVal,
    weight_kg: weightVal,
    bmi: bmiVal
  };

  const { data, error } = await supabase
    .from('vital_signs')
    .insert(insertData)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Failed to record vital signs.');
  }

  return data;
}
