import { supabase } from '../lib/supabaseClient.js';

/**
 * Queue Management Service
 * Encapsulates all queue-related database queries and RPC operations.
 */

/**
 * List available healthcare queue services for a given date.
 * @param {string} [date] - Optional ISO date string (YYYY-MM-DD). Defaults to today.
 * @returns {Promise<Array>}
 */
export async function listAvailableQueueServices(date) {
  const targetDate = date || new Date().toISOString().split('T')[0];
  const { data, error } = await supabase.rpc('list_available_queue_services', {
    p_date: targetDate,
  });

  if (error) {
    throw new Error(error.message || 'Unable to fetch available queue services.');
  }

  return data || [];
}

/**
 * Create a new queue ticket for a citizen.
 * @param {Object} params
 * @param {string} params.serviceKey
 * @param {string} params.serviceLabel
 * @param {string} params.citizenType - 'regular' | 'pwd' | 'pregnant'
 * @param {string} [params.reason]
 * @param {string} [params.symptoms]
 * @returns {Promise<Object>} The created queue ticket.
 */
export async function createQueueTicket({
  serviceKey,
  serviceLabel,
  citizenType = 'regular',
  reason = '',
  symptoms = '',
}) {
  if (!serviceKey || !serviceLabel) {
    throw new Error('Healthcare service selection is required.');
  }

  const { data, error } = await supabase.rpc('create_queue_ticket', {
    p_service_key: serviceKey.trim(),
    p_service_label: serviceLabel.trim(),
    p_citizen_type: citizenType.trim().toLowerCase(),
    p_reason: (reason || '').trim(),
    p_symptoms: (symptoms || '').trim(),
  });

  if (error) {
    throw new Error(error.message || 'Failed to create queue ticket.');
  }

  const rows = Array.isArray(data) ? data : [data];
  if (!rows.length || !rows[0]) {
    throw new Error('Failed to create queue ticket. Empty response returned.');
  }

  return rows[0];
}

/**
 * Fetch a queue ticket by ticket code, including citizen demographic info.
 * @param {string} ticketCode
 * @returns {Promise<Object|null>}
 */
export async function getQueueTicketByCode(ticketCode) {
  if (!ticketCode) return null;

  const { data, error } = await supabase
    .from('queue_tickets')
    .select(`
      id,
      citizen_id,
      ticket_code,
      queue_number,
      service_key,
      service_label,
      citizen_type,
      status,
      reason,
      symptoms,
      created_at,
      completed_at,
      citizens (
        id,
        username,
        firstname,
        surname,
        age,
        complete_address,
        contact_number
      )
    `)
    .eq('ticket_code', ticketCode.trim())
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Error fetching queue ticket by code.');
  }

  return data;
}

/**
 * Fetch a single ticket by its primary key.
 * @param {number|string} ticketId
 * @returns {Promise<Object|null>}
 */
export async function getQueueTicketById(ticketId) {
  const { data, error } = await supabase
    .from('queue_tickets')
    .select('id, status, service_label, queue_number, ticket_code, completed_at, created_at, citizen_id')
    .eq('id', ticketId)
    .maybeSingle();

  if (error) {
    throw new Error(error.message || 'Error fetching queue ticket.');
  }

  return data;
}

/**
 * List queue tickets with optional filters.
 * @param {Object} [options]
 * @param {string|string[]} [options.status]
 * @param {string} [options.queueDate]
 * @param {number} [options.limit=100]
 * @returns {Promise<Array>}
 */
export async function listQueueTickets({ status, queueDate, limit = 100 } = {}) {
  let query = supabase
    .from('queue_tickets')
    .select(`
      id,
      queue_number,
      ticket_code,
      service_key,
      service_label,
      citizen_type,
      status,
      created_at,
      completed_at,
      citizens (
        id,
        firstname,
        surname
      )
    `)
    .order('queue_number', { ascending: true })
    .limit(limit);

  if (status) {
    if (Array.isArray(status)) {
      query = query.in('status', status);
    } else {
      query = query.eq('status', status);
    }
  }

  if (queueDate) {
    query = query.eq('queue_date', queueDate);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message || 'Unable to list queue tickets.');
  }

  return data || [];
}

/**
 * Update the status of a queue ticket.
 * @param {number|string} ticketId
 * @param {string} targetStatus
 * @returns {Promise<Object>}
 */
export async function updateQueueTicketStatus(ticketId, targetStatus) {
  const updatePayload = { status: targetStatus };
  if (targetStatus === 'completed') {
    updatePayload.completed_at = new Date().toISOString();
  }

  const { data, error } = await supabase
    .from('queue_tickets')
    .update(updatePayload)
    .eq('id', ticketId)
    .select()
    .maybeSingle();

  if (error) {
    throw new Error(error.message || `Failed to update queue ticket status to ${targetStatus}.`);
  }

  return data;
}

/**
 * Retrieve queue limiter / capacity configuration.
 * @returns {Promise<Object>}
 */
export async function getQueueLimiterStatus() {
  const { data, error } = await supabase.rpc('get_queue_limiter_status');
  if (error) {
    throw new Error(error.message || 'Unable to fetch queue limiter status.');
  }

  const rows = Array.isArray(data) ? data : [data];
  return rows[0] || { enabled: false };
}

/**
 * Fetch formatted queue display payload for TV monitors.
 * @returns {Promise<Object>}
 */
export async function getTvQueueDisplay() {
  const { data, error } = await supabase.rpc('get_tv_queue_display');
  if (error) {
    throw new Error(error.message || 'Unable to fetch TV queue display data.');
  }

  return data || {};
}
