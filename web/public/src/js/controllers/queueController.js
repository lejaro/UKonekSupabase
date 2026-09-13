/**
 * Patient Queue Management Controller
 * Manages live queue board lanes (waiting, on_call, serving), ticket status progression,
 * drag-and-drop lane sorting, TV monitor sync, and vital signs assessment modal.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import { showToast, setLoading } from '../utils/uiHelpers.js';
import { openDialogModal } from '../utils/dialogModal.js';
import { evaluateVitalsRisk } from './triageController.js';
import { openConsultationModal } from './consultationController.js';

let queueBoardChannel = null;
let queueRefreshInterval = null;
const state = {
  tickets: [],
  loading: false
};

export function canConsultPatients() {
  const role = String(sessionStore.getUser()?.role || '').trim().toLowerCase();
  return role === 'doctor';
}

export function startConsultationFromTicket(ticket) {
  if (!ticket) return;
  if (!canConsultPatients()) {
    showToast('Only doctors can conduct consultations.', 'warning');
    return;
  }
  const citizen = ticket.citizen || {};
  const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || ticket.walkin_patient_name || 'Walk-in Patient';
  openConsultationModal({
    patientId: citizen.id ? String(citizen.id) : (ticket.walkin_patient_name || 'Walk-in Patient'),
    patientName: fullName,
    serviceLabel: ticket.service_label || 'General Consultation',
    queueTicketId: ticket.id,
    symptoms: ticket.symptoms || '',
    notes: ticket.reason || ''
  });
}

export async function openVitalAssessmentModal(ticket) {
  const vaModal = document.getElementById('vital-assessment-modal');
  const vaForm = document.getElementById('vital-assessment-form');
  if (!vaModal || !ticket) return;
  if (vaForm) vaForm.reset();

  const ticketIdInput = document.getElementById('va-queue-ticket-id');
  const citizenIdInput = document.getElementById('va-citizen-id');
  if (ticketIdInput) ticketIdInput.value = ticket.id;
  if (citizenIdInput) citizenIdInput.value = ticket.citizen?.id || '';

  const bannerEl = document.getElementById('vital-modal-patient-banner');
  const nameEl = document.getElementById('vital-modal-patient-name');
  const metaEl = document.getElementById('vital-modal-patient-meta');
  const badgeEl = document.getElementById('vital-modal-existing-badge');
  if (bannerEl) bannerEl.style.display = 'block';
  if (nameEl) nameEl.textContent = `${ticket.citizen?.firstname || ''} ${ticket.citizen?.surname || ''}`.trim() || 'Guest Patient';
  if (metaEl) {
    const age = ticket.citizen?.age ? `${ticket.citizen.age} yrs` : 'Age N/A';
    const gender = ticket.citizen?.sex || 'Sex N/A';
    metaEl.textContent = `${ticket.service_label || 'General'} | ${age} | ${gender}`;
  }
  if (badgeEl) badgeEl.style.display = 'none';

  // Wire real-time risk assessment input listeners
  ['va-bp', 'va-hr', 'va-rr', 'va-temp', 'va-spo2', 'va-height', 'va-weight'].forEach(id => {
    const el = document.getElementById(id);
    if (el && !el.dataset.riskBound) {
      el.addEventListener('input', evaluateVitalsRisk);
      el.dataset.riskBound = 'true';
    }
  });

  // Load and display patient symptoms & reason submitted during queue entry
  const symptomsSection = document.getElementById('va-patient-symptoms-section');
  const symptomsDisplay = document.getElementById('va-patient-symptoms-display');
  if (symptomsSection && symptomsDisplay) {
    let detailHtml = '';
    if (ticket.reason) {
      detailHtml += `<div style="margin-bottom:6px;"><strong>Reason for Visit:</strong><br/><span style="color:#2d3748;">${ticket.reason}</span></div>`;
    }
    if (ticket.symptoms) {
      detailHtml += `<div><strong>Symptom Description:</strong><br/><span style="color:#2d3748;">${ticket.symptoms}</span></div>`;
    }
    if (detailHtml) {
      symptomsDisplay.innerHTML = detailHtml;
      symptomsSection.style.display = 'block';
    } else {
      symptomsSection.style.display = 'none';
    }
  }

  try {
    const { data: existing } = await supabase
      .from('vital_signs')
      .select('*')
      .eq('queue_ticket_id', ticket.id)
      .maybeSingle();

    if (existing) {
      if (badgeEl) badgeEl.style.display = 'inline-flex';
      if (document.getElementById('va-chief-complaint')) document.getElementById('va-chief-complaint').value = existing.chief_complaint || '';
      if (document.getElementById('va-bp')) document.getElementById('va-bp').value = existing.blood_pressure || '';
      if (document.getElementById('va-hr')) document.getElementById('va-hr').value = existing.heart_rate || '';
      if (document.getElementById('va-rr')) document.getElementById('va-rr').value = existing.respiratory_rate || '';
      if (document.getElementById('va-temp')) document.getElementById('va-temp').value = existing.temperature || '';
      if (document.getElementById('va-spo2')) document.getElementById('va-spo2').value = existing.oxygen_saturation || '';
      if (document.getElementById('va-height')) document.getElementById('va-height').value = existing.height_cm != null ? existing.height_cm : '';
      if (document.getElementById('va-weight')) document.getElementById('va-weight').value = existing.weight_kg != null ? existing.weight_kg : '';
      if (document.getElementById('va-meds')) document.getElementById('va-meds').value = existing.current_medications || '';
      if (document.getElementById('va-notes')) document.getElementById('va-notes').value = existing.notes || '';
    } else {
      // New assessment: pre-fill chief complaint with reason + symptoms
      if (document.getElementById('va-chief-complaint')) {
        let combined = '';
        if (ticket.reason) combined += ticket.reason;
        if (ticket.symptoms) {
          if (combined) combined += ': ';
          combined += ticket.symptoms;
        }
        document.getElementById('va-chief-complaint').value = combined || '';
      }
    }
  } catch (err) {
    console.warn('Error checking existing vitals:', err);
  }

  evaluateVitalsRisk();
  vaModal.classList.remove('hidden');
  vaModal.style.display = 'flex';
}

export function closeVitalAssessmentModal() {
  const vaModal = document.getElementById('vital-assessment-modal');
  if (vaModal) {
    vaModal.classList.add('hidden');
    vaModal.style.display = 'none';
  }
  const vaForm = document.getElementById('vital-assessment-form');
  if (vaForm) {
    vaForm.reset();
  }
  evaluateVitalsRisk();
}

export function initVitalAssessmentModal() {
  const vaModal = document.getElementById('vital-assessment-modal');
  const vaForm = document.getElementById('vital-assessment-form');
  const vaCancelBtn = document.getElementById('va-cancel-btn');

  if (vaCancelBtn) {
    vaCancelBtn.addEventListener('click', closeVitalAssessmentModal);
  }

  if (vaModal) {
    vaModal.addEventListener('click', (e) => {
      if (e.target === vaModal) closeVitalAssessmentModal();
    });
  }

  // Wire real-time risk assessment and BMI calculation listeners
  ['va-bp', 'va-hr', 'va-rr', 'va-temp', 'va-spo2', 'va-height', 'va-weight'].forEach(id => {
    const el = document.getElementById(id);
    if (el && !el.dataset.riskBound) {
      el.addEventListener('input', evaluateVitalsRisk);
      el.dataset.riskBound = 'true';
    }
  });

  if (vaForm && !vaForm.dataset.bound) {
    vaForm.dataset.bound = 'true';

    // Prevent typing minus or plus signs in numeric inputs
    const numericVitals = vaForm.querySelectorAll('input[type="number"]');
    numericVitals.forEach(input => {
      input.addEventListener('keydown', (e) => {
        if (e.key === '-' || e.key === '+') {
          e.preventDefault();
        }
      });
    });

    vaForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const submitBtn = vaForm.querySelector('button[type="submit"]');
      const ticketId = document.getElementById('va-queue-ticket-id')?.value;
      const citizenId = document.getElementById('va-citizen-id')?.value;
      const complaint = document.getElementById('va-chief-complaint')?.value;
      if (!ticketId) {
        showToast('Missing queue ticket reference.', 'error');
        return;
      }

      const bp = document.getElementById('va-bp')?.value?.trim();
      const hrVal = document.getElementById('va-hr')?.value?.trim();
      const rrVal = document.getElementById('va-rr')?.value?.trim();
      const tempVal = document.getElementById('va-temp')?.value?.trim();
      const spo2Val = document.getElementById('va-spo2')?.value?.trim();

      // Validations
      if (tempVal !== undefined && tempVal !== null && tempVal !== '') {
        const temp = parseFloat(tempVal);
        if (isNaN(temp)) {
          showToast('Temperature must be a valid number.', 'warning');
          return;
        }
        if (temp < 0) {
          showToast('Temperature cannot be negative.', 'warning');
          return;
        }
        if (temp < 30.0) {
          showToast('Temperature cannot be under 30.0°C.', 'warning');
          return;
        }
        if (temp > 45.0) {
          showToast('Temperature cannot exceed 45.0°C.', 'warning');
          return;
        }
      }

      if (hrVal !== undefined && hrVal !== null && hrVal !== '') {
        const hr = parseInt(hrVal, 10);
        if (isNaN(hr)) {
          showToast('Heart Rate must be a valid number.', 'warning');
          return;
        }
        if (hr < 0) {
          showToast('Heart Rate cannot be negative.', 'warning');
          return;
        }
        if (hr > 300) {
          showToast('Heart Rate cannot exceed 300 bpm.', 'warning');
          return;
        }
      }

      if (rrVal !== undefined && rrVal !== null && rrVal !== '') {
        const rr = parseInt(rrVal, 10);
        if (isNaN(rr)) {
          showToast('Respiratory Rate must be a valid number.', 'warning');
          return;
        }
        if (rr < 0) {
          showToast('Respiratory Rate cannot be negative.', 'warning');
          return;
        }
        if (rr > 100) {
          showToast('Respiratory Rate cannot exceed 100 bpm.', 'warning');
          return;
        }
      }

      if (spo2Val !== undefined && spo2Val !== null && spo2Val !== '') {
        const spo2 = parseInt(spo2Val, 10);
        if (isNaN(spo2)) {
          showToast('Oxygen Saturation must be a valid number.', 'warning');
          return;
        }
        if (spo2 < 0) {
          showToast('Oxygen Saturation cannot be negative.', 'warning');
          return;
        }
        if (spo2 > 100) {
          showToast('Oxygen Saturation cannot exceed 100%.', 'warning');
          return;
        }
      }

      if (bp !== undefined && bp !== null && bp !== '') {
        if (bp.includes('-')) {
          showToast('Blood Pressure values cannot be negative.', 'warning');
          return;
        }
        const bpPattern = /^\d{2,3}\/\d{2,3}$/;
        if (!bpPattern.test(bp)) {
          showToast('Blood Pressure must be in format Systolic/Diastolic (e.g. 120/80).', 'warning');
          return;
        }
      }

      const heightInputVal = document.getElementById('va-height')?.value?.trim();
      let parsedHeight = null;
      if (heightInputVal !== undefined && heightInputVal !== null && heightInputVal !== '') {
        parsedHeight = parseFloat(heightInputVal);
        if (isNaN(parsedHeight) || parsedHeight <= 0) {
          showToast('Height must be a valid positive number.', 'warning');
          return;
        }
        if (parsedHeight < 30 || parsedHeight > 250) {
          showToast('Height must be between 30 and 250 cm.', 'warning');
          return;
        }
      }

      const weightInputVal = document.getElementById('va-weight')?.value?.trim();
      let parsedWeight = null;
      if (weightInputVal !== undefined && weightInputVal !== null && weightInputVal !== '') {
        parsedWeight = parseFloat(weightInputVal);
        if (isNaN(parsedWeight) || parsedWeight <= 0) {
          showToast('Weight must be a valid positive number.', 'warning');
          return;
        }
        if (parsedWeight < 1 || parsedWeight > 300) {
          showToast('Weight must be between 1 and 300 kg.', 'warning');
          return;
        }
      }

      let computedBmi = null;
      if (parsedHeight && parsedWeight) {
        const hm = parsedHeight / 100;
        computedBmi = Number((parsedWeight / (hm * hm)).toFixed(1));
      }

      setLoading(submitBtn, true);
      try {
        const rpcPayload = {
          p_queue_ticket_id: Number(ticketId),
          p_citizen_id: citizenId ? Number(citizenId) : null,
          p_chief_complaint: complaint || 'General Checkup',
          p_blood_pressure: bp || null,
          p_heart_rate: hrVal ? parseInt(hrVal, 10) : null,
          p_temperature: tempVal ? parseFloat(tempVal) : null,
          p_respiratory_rate: rrVal ? parseInt(rrVal, 10) : null,
          p_oxygen_saturation: spo2Val ? parseInt(spo2Val, 10) : null,
          p_current_medications: document.getElementById('va-meds')?.value || null,
          p_notes: document.getElementById('va-notes')?.value || null,
          p_height_cm: parsedHeight,
          p_weight_kg: parsedWeight,
          p_bmi: computedBmi
        };

        const { data: rpcRes, error: rpcError } = await supabase.rpc('upsert_vital_assessment', rpcPayload);
        if (rpcError) throw rpcError;
        if (rpcRes && rpcRes.error) throw new Error(rpcRes.error);

        showToast('Vital signs saved successfully.', 'success');
        closeVitalAssessmentModal();
        await loadQueueTickets();
      } catch (err) {
        console.error('Vitals assessment submission error:', err);
        showToast(err.message || 'Failed to save vital signs.', 'error');
      } finally {
        setLoading(submitBtn, false);
      }
    });
  }
}

export function teardownQueueRealtime() {
  if (queueBoardChannel) {
    try {
      supabase.removeChannel(queueBoardChannel);
      console.log('[Queue] Realtime channel unsubscribed.');
    } catch (_) {}
    queueBoardChannel = null;
  }
}

export async function setupRealtime() {
  try {
    teardownQueueRealtime();

    const manilaTodayStr = new Intl.DateTimeFormat('fr-CA', {
      timeZone: 'Asia/Manila',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(new Date());

    queueBoardChannel = supabase
      .channel('queue-board-updates')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'queue_tickets',
        filter: `queue_date=eq.${manilaTodayStr}`
      }, (payload) => {
        console.log('[Queue] Realtime update:', payload.eventType);
        loadQueueTickets();
      })
      .subscribe((status) => {
        console.log('[Queue] Realtime status:', status);
      });
  } catch (err) {
    console.error('[Queue] Failed to setup realtime:', err);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', teardownQueueRealtime);
}

export async function loadQueueTickets() {
  if (state.loading) return;
  if (document.querySelector('.queue-ticket-card.dragging')) return;

  state.loading = true;
  const waitCountEl = document.getElementById('queue-waiting-count');
  const oncallCountEl = document.getElementById('queue-oncall-count');
  const serveCountEl = document.getElementById('queue-serving-count');

  if (!state.tickets || state.tickets.length === 0) {
    if (waitCountEl) waitCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
    if (oncallCountEl) oncallCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
    if (serveCountEl) serveCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
  }

  try {
    const manilaTodayStr = new Intl.DateTimeFormat('fr-CA', {
      timeZone: 'Asia/Manila',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(new Date());

    const { data, error } = await supabase
      .from('queue_tickets')
      .select('id, queue_number, ticket_code, status, queue_date, citizen_type, service_label, symptoms, reason, citizen:citizens(id, firstname, surname, age, sex, contact_number), vitals:vital_signs(id)')
      .eq('queue_date', manilaTodayStr)
      .in('status', ['waiting', 'on_call', 'serving'])
      .order('queue_date', { ascending: true })
      .order('queue_number', { ascending: true });

    if (error) throw error;
    state.tickets = data || [];
    renderQueueBoard();
  } catch (err) {
    console.error('[Queue] Sync error:', err);
  } finally {
    state.loading = false;
  }
}

export function renderQueueBoard() {
  const getStatus = (t) => String(t.status || '').trim().toLowerCase();
  const lanes = {
    waiting: state.tickets.filter(t => getStatus(t) === 'waiting'),
    on_call: state.tickets.filter(t => getStatus(t) === 'on_call'),
    serving: state.tickets.filter(t => getStatus(t) === 'serving')
  };

  renderLane('queue-waiting-list', lanes.waiting);
  renderLane('queue-oncall-list', lanes.on_call);
  renderLane('queue-serving-list', lanes.serving);

  const updateText = (id, val) => {
    const el = document.getElementById(id);
    if (el) {
      el.textContent = val;
      el.classList.remove('data-loaded');
      void el.offsetWidth;
      el.classList.add('data-loaded');
    }
  };

  updateText('queue-waiting-count', lanes.waiting.length);
  updateText('queue-oncall-count', lanes.on_call.length);
  updateText('queue-serving-count', lanes.serving.length);
  updateText('queue-summary-badge', `Waiting: ${lanes.waiting.length} | On Call: ${lanes.on_call.length} | Serving: ${lanes.serving.length}`);

  const servingNumbers = lanes.serving.map(t => `#${String(t.queue_number).padStart(3, '0')}`);
  const servingBadge = document.getElementById('queue-current-serving-badge');
  if (servingBadge) {
    if (servingNumbers.length > 0) {
      servingBadge.className = 'queue-station-pill active';
      servingBadge.innerHTML = `
        <span class="queue-station-dot"></span>
        <span><strong>Now Serving:</strong> <span style="background:#2563eb;color:#fff;padding:1px 7px;border-radius:6px;font-family:monospace;font-size:11.5px;margin-left:2px;">${servingNumbers.join(', ')}</span></span>
      `;
      servingBadge.style.display = 'inline-flex';
    } else {
      servingBadge.className = 'queue-station-pill ready';
      servingBadge.innerHTML = `
        <span class="queue-station-dot"></span>
        <span>Station Ready • Queue Clear</span>
      `;
    }
  }

  const consultServingBtn = document.getElementById('queue-consult-serving-btn');
  if (consultServingBtn) {
    if (lanes.serving.length > 0 && canConsultPatients()) {
      consultServingBtn.style.display = 'inline-flex';
      consultServingBtn.innerHTML = `
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" style="vertical-align:-1px;margin-right:4px;"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
        ${lanes.serving.length === 1 ? 'Consult Serving' : `Consult Serving (${lanes.serving.length})`}
      `;
    } else {
      consultServingBtn.style.display = 'none';
    }
  }
}

export function renderLane(id, list) {
  const container = document.getElementById(id);
  if (!container) return;
  if (list.length === 0) {
    container.innerHTML = '';
    return;
  }

  const getIndicatorHtml = (type) => {
    if (type === 'pwd') {
      return `<span style="background:#fef08a;color:#854d0e;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;display:inline-flex;align-items:center;gap:4px;margin-left:6px;" title="PWD">
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="5" r="2"/><path d="M12 7v5h3"/><path d="M15 19l2-3"/><path d="M7 16a5 5 0 1 0 5-8"/></svg>
        PWD
      </span>`;
    }
    if (type === 'pregnant') {
      return `<span style="background:#fbcfe8;color:#be185d;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;display:inline-flex;align-items:center;gap:4px;margin-left:6px;" title="Pregnant">
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>
        Pregnant
      </span>`;
    }
    return '';
  };

  const getStatus = (t) => String(t.status || '').trim().toLowerCase();

  container.innerHTML = list.map(t => `
    <div class="queue-ticket-card" data-id="${t.id}" draggable="true">
      <div class="queue-ticket-top">
        <span class="queue-ticket-queue">#${String(t.queue_number).padStart(3, '0')}</span>
        ${(t.vitals && t.vitals.length > 0) ? '<span class="vitals-badge" title="Vital assessment completed">Vitals Assessed</span>' : ''}
        <span class="queue-ticket-code">${t.ticket_code}</span>
      </div>
      <div class="queue-ticket-name" style="display:flex;align-items:center;">
        ${t.citizen?.firstname ? `${t.citizen.firstname} ${t.citizen.surname || ''}` : (t.walkin_patient_name || 'Walk-in Patient')}
        ${!t.citizen?.firstname ? '<span style="background:#f0fdf4;color:#15803d;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;margin-left:6px;">Walk-in</span>' : ''}
        ${getIndicatorHtml(t.citizen_type)}
      </div>
      <div class="queue-ticket-meta">${t.service_label}</div>
      <div class="queue-ticket-actions">
        ${getStatus(t) === 'waiting' ? '<button class="queue-ticket-btn" data-action="move" data-lane="on_call">On Call</button>' : ''}
        ${getStatus(t) === 'on_call' ? ((t.vitals && t.vitals.length > 0) ? '<button class="queue-ticket-btn" data-action="move" data-lane="serving">Serve</button>' : '') + '<button class="queue-ticket-btn btn-vital" data-action="vital">Vitals</button>' : ''}
        ${getStatus(t) === 'serving' ? (canConsultPatients() ? `
          <button class="queue-ticket-btn btn-consult" data-action="consult">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;">
              <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
            </svg>
            Consultation
          </button>` : '') : ''}
      </div>
    </div>`).join('');
}

export async function handleAction(e) {
  const btn = e.target.closest('button');
  const card = e.target.closest('.queue-ticket-card');
  if (!card) return;

  const id = card.dataset.id;

  if (btn) {
    const action = btn.dataset.action;
    const lane = btn.dataset.lane;

    try {
      if (action === 'move') {
        const ticket = state.tickets.find(t => String(t.id) === String(id));
        if (ticket) {
          const { data, error } = await supabase.from('queue_tickets')
            .update({ status: lane })
            .eq('id', id)
            .eq('status', ticket.status)
            .select();
          if (!error && (!data || data.length === 0)) {
            alert('This ticket was already processed by another staff member.');
          }
        }
      } else if (action === 'complete') {
        const ticket = state.tickets.find(t => String(t.id) === String(id));
        if (ticket) {
          await supabase.from('queue_tickets')
            .update({ status: 'completed', completed_at: new Date().toISOString() })
            .eq('id', id)
            .eq('status', ticket.status);
        }
      } else if (action === 'vital') {
        const ticket = state.tickets.find(t => String(t.id) === String(id));
        if (ticket) {
          await openVitalAssessmentModal(ticket);
        }
        return;
      } else if (action === 'consult') {
        const ticket = state.tickets.find(t => String(t.id) === String(id));
        if (ticket) {
          startConsultationFromTicket(ticket);
        }
        return;
      }
      await loadQueueTickets();
    } catch (err) {
      console.error('[Queue] Action error:', err);
    }
  } else {
    openQueueTicketDetail(id);
  }
}

export function openQueueTicketDetail(id) {
  const ticket = state.tickets.find(t => String(t.id) === String(id));
  if (!ticket) return;

  const modal = document.getElementById('queue-ticket-detail-modal');
  const body = document.getElementById('queue-ticket-detail-body');
  if (!modal || !body) return;

  const citizen = ticket.citizen || {};
  const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || ticket.walkin_patient_name || 'Walk-in Patient';
  const age = citizen.age ? `${citizen.age} yrs` : 'Age N/A';
  const gender = citizen.sex || 'Sex N/A';
  const phone = citizen.contact_number || 'No phone';

  body.innerHTML = `
    <div style="background:#f8fafc; border-radius:12px; padding:16px; margin-bottom:16px; border:1px solid #e2e8f0;">
      <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Patient Info</div>
      <div style="font-size:18px; font-weight:800; color:#0f172a; margin-bottom:2px;">
        ${fullName}
        ${!citizen.firstname ? '<span style="background:#f0fdf4;color:#15803d;padding:2px 6px;border-radius:4px;font-size:11px;font-weight:700;margin-left:6px;vertical-align:middle;">Walk-in Patient</span>' : ''}
      </div>
      <div style="font-size:13px; color:#475569; font-weight:500;">${age} | ${gender} | ${phone}</div>
    </div>
    
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
      <div style="background:#fff; border:1px solid #e2e8f0; border-radius:10px; padding:12px;">
        <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Queue Info</div>
        <div style="font-size:16px; font-weight:700; color:#15803d;">#${String(ticket.queue_number).padStart(3, '0')}</div>
        <div style="font-size:12px; font-weight:600; color:#475569;">${ticket.ticket_code}</div>
      </div>
      <div style="background:#fff; border:1px solid #e2e8f0; border-radius:10px; padding:12px;">
        <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Service</div>
        <div style="font-size:14px; font-weight:700; color:#0f172a;">${ticket.service_label}</div>
        <div style="font-size:12px; color:#64748b;">${new Date(ticket.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
      </div>
    </div>

    <div style="margin-top:16px; padding:12px; background:#f0fdf4; border:1px solid #bbf7d0; border-radius:10px;">
      <div style="font-size:11px; color:#15803d; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Status</div>
      <div style="font-size:14px; font-weight:700; color:#166534; text-transform:capitalize;">${ticket.status?.replace('_', ' ') || 'Pending'}</div>
    </div>
  `;

  modal.classList.remove('hidden');

  const consultDetailBtn = document.getElementById('queue-ticket-consult-btn');
  if (consultDetailBtn) {
    if (String(ticket.status).toLowerCase() === 'serving' && canConsultPatients()) {
      consultDetailBtn.style.display = 'inline-flex';
      consultDetailBtn.onclick = () => {
        modal.classList.add('hidden');
        startConsultationFromTicket(ticket);
      };
    } else {
      consultDetailBtn.style.display = 'none';
    }
  }

  const closeBtn = document.getElementById('queue-ticket-detail-close');
  if (closeBtn) {
    closeBtn.onclick = () => modal.classList.add('hidden');
  }

  const deleteBtn = document.getElementById('queue-ticket-delete-btn');
  if (deleteBtn) {
    deleteBtn.onclick = async () => {
      const confirmation = await openDialogModal({
        title: 'Delete Queue Ticket',
        message: 'Are you sure you want to delete this queue ticket? This action cannot be undone.',
        confirmText: 'Delete',
        cancelText: 'Cancel'
      });
      if (!confirmation.confirmed) return;

      try {
        setLoading(deleteBtn, true);
        const { error } = await supabase
          .from('queue_tickets')
          .delete()
          .eq('id', Number(id));

        if (error) throw error;

        showToast('Ticket deleted successfully.', 'success');
        modal.classList.add('hidden');
        await loadQueueTickets();
      } catch (err) {
        console.error('[Queue] Delete error:', err);
        showToast(err.message || 'Failed to delete ticket.', 'error');
      } finally {
        setLoading(deleteBtn, false);
      }
    };
  }

  modal.onclick = (e) => {
    if (e.target === modal) modal.classList.add('hidden');
  };
}

export function handleDragStart(e) {
  const card = e.target.closest('.queue-ticket-card');
  if (!card) return;
  card.classList.add('dragging');
  e.dataTransfer.setData('text/plain', card.dataset.id);
  e.dataTransfer.effectAllowed = 'move';
}

export function handleDragOver(e) {
  e.preventDefault();
  const lane = e.target.closest('.queue-card-list');
  if (lane) lane.classList.add('drag-over');
}

export function handleDragLeave(e) {
  const lane = e.target.closest('.queue-card-list');
  if (lane) lane.classList.remove('drag-over');
}

export async function handleDrop(e) {
  e.preventDefault();
  const lane = e.target.closest('.queue-card-list');
  const ticketId = e.dataTransfer.getData('text/plain');
  document.querySelectorAll('.queue-card-list').forEach(l => l.classList.remove('drag-over'));
  document.querySelectorAll('.queue-ticket-card').forEach(c => c.classList.remove('dragging'));
  if (!lane || !ticketId) return;
  const targetStatus = lane.dataset.lane;
  if (!targetStatus) return;

  try {
    const { error } = await supabase.from('queue_tickets').update({ status: targetStatus }).eq('id', ticketId);
    if (error) throw error;
    await loadQueueTickets();
  } catch (err) {
    console.error('[Queue] Drop error:', err);
    showToast('Failed to update ticket status.', 'error');
  }
}

export function setupUI() {
  const refreshBtn = document.getElementById('queue-refresh-btn');
  if (refreshBtn && !refreshBtn.dataset.bound) {
    refreshBtn.addEventListener('click', loadQueueTickets);
    refreshBtn.dataset.bound = 'true';
  }

  const tvBtn = document.getElementById('open-tv-view-btn');
  if (tvBtn && !tvBtn.dataset.bound) {
    tvBtn.addEventListener('click', () => {
      window.open('tv-view.html', '_blank', 'noopener,noreferrer');
    });
    tvBtn.dataset.bound = 'true';
  }

  const consultServingBtn = document.getElementById('queue-consult-serving-btn');
  if (consultServingBtn && !consultServingBtn.dataset.bound) {
    consultServingBtn.addEventListener('click', () => {
      if (!canConsultPatients()) {
        showToast('Only doctors can conduct consultations.', 'warning');
        return;
      }
      const getStatus = (t) => String(t.status || '').trim().toLowerCase();
      const serving = state.tickets.filter(t => getStatus(t) === 'serving');
      if (serving.length === 0) {
        showToast('No patients are currently in Now Serving.', 'warning');
        return;
      }
      if (serving.length === 1) {
        startConsultationFromTicket(serving[0]);
      } else {
        showToast('Multiple patients are being served. Click Consultation on the specific ticket card.', 'info');
      }
    });
    consultServingBtn.dataset.bound = 'true';
  }

  const board = document.querySelector('.queue-board');
  if (board && !board.dataset.bound) {
    board.addEventListener('click', handleAction);
    board.addEventListener('dragstart', handleDragStart);
    board.addEventListener('dragover', handleDragOver);
    board.addEventListener('dragleave', handleDragLeave);
    board.addEventListener('drop', handleDrop);
    board.dataset.bound = 'true';
  }

  initVitalAssessmentModal();
}

export async function initQueueController() {
  setupUI();
  await setupRealtime();
  await loadQueueTickets();

  if (queueRefreshInterval) clearInterval(queueRefreshInterval);
  queueRefreshInterval = setInterval(() => {
    if (document.visibilityState === 'visible') loadQueueTickets();
  }, 60000);
}

// Preserve backwards-compatibility endpoints
if (typeof window !== 'undefined') {
  window.appointments = { init: initQueueController, loadQueueTickets };
  window.loadQueueTickets = loadQueueTickets;
  window.openVitalAssessmentModal = openVitalAssessmentModal;
}
