/**
 * Vitals Triage & Clinical Risk Controller
 * Manages QR camera ticket scanning (Html5Qrcode), queue patient intake,
 * vital signs recording, and real-time clinical risk evaluation.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import { showToast, setLoading } from '../utils/uiHelpers.js';
import { attachDetailRow } from '../utils/dataDetailModal.js';

let html5QrcodeScanner = null;
let activeVitalsQueueTicketId = null;
let vitalsInitialized = false;

export function evaluateVitalsRisk() {
  // Clinical diagnoses (Hypertensive, Hypothermia, Fever, Tachycardia, Hypoxia, etc.)
  // are solely evaluated by the attending physician during consultation, not by the intake system.

  // Purely calculate mathematical BMI metric if height and weight are provided
  const heightInput = document.getElementById('va-height') || document.getElementById('vitals-height');
  const weightInput = document.getElementById('va-weight') || document.getElementById('vitals-weight');
  const bmiValEl = document.getElementById('va-bmi-value');

  if (bmiValEl) {
    const h = heightInput ? parseFloat(heightInput.value) : NaN;
    const w = weightInput ? parseFloat(weightInput.value) : NaN;

    if (!isNaN(h) && !isNaN(w) && h > 0 && w > 0) {
      const hMeters = h / 100;
      const bmi = w / (hMeters * hMeters);
      const roundedBmi = Math.round(bmi * 10) / 10;
      bmiValEl.textContent = roundedBmi.toFixed(1);
    } else {
      bmiValEl.innerHTML = '&mdash;';
    }
  }
}

export function setVitalsStationStatus(status, label) {
  const badge = document.getElementById('vitals-station-status');
  if (badge) {
    badge.className = `station-status-pill status-${status}`;
    badge.innerHTML = `<span class="pill-dot"></span> ${label}`;
  }
}

let rawVitalsData = [];
let currentFilter = 'all';
let searchQuery = '';

export function evaluateBp(bp) {
  if (!bp) return { level: 'normal', text: '', sub: '' };
  const parts = String(bp).trim().split('/');
  const sys = parseInt(parts[0], 10);
  const dia = parseInt(parts[1], 10);
  if (isNaN(sys)) return { level: 'normal', text: bp, sub: '' };
  if (sys >= 140 || dia >= 90) return { level: 'alert', text: bp, sub: 'Elevated' };
  if (sys >= 120 || dia >= 80) return { level: 'amber', text: bp, sub: 'Pre-HTN' };
  return { level: 'normal', text: bp, sub: 'Normal' };
}

export function evaluateHr(hr) {
  if (!hr) return { level: 'normal', text: '', sub: '' };
  const val = parseInt(hr, 10);
  if (isNaN(val)) return { level: 'normal', text: hr, sub: '' };
  if (val > 100) return { level: 'alert', text: `${val} bpm`, sub: 'Tachycardia' };
  if (val < 50) return { level: 'alert', text: `${val} bpm`, sub: 'Bradycardia' };
  if (val > 90) return { level: 'amber', text: `${val} bpm`, sub: 'Borderline' };
  return { level: 'normal', text: `${val} bpm`, sub: 'Normal' };
}

export function evaluateTemp(temp) {
  if (!temp) return { level: 'normal', text: '', sub: '' };
  const val = parseFloat(temp);
  if (isNaN(val)) return { level: 'normal', text: temp, sub: '' };
  if (val >= 38.0) return { level: 'alert', text: `${val.toFixed(1)}°C`, sub: 'Fever' };
  if (val >= 37.5) return { level: 'amber', text: `${val.toFixed(1)}°C`, sub: 'Elevated' };
  return { level: 'normal', text: `${val.toFixed(1)}°C`, sub: 'Normal' };
}

export function evaluateSpo2(spo2) {
  if (!spo2) return { level: 'normal', text: '', sub: '' };
  const val = parseInt(spo2, 10);
  if (isNaN(val)) return { level: 'normal', text: spo2, sub: '' };
  if (val < 95) return { level: 'alert', text: `${val}%`, sub: 'Low SpO2' };
  return { level: 'normal', text: `${val}%`, sub: 'Normal' };
}

export function renderVitalsTable() {
  const tbody = document.getElementById('vitals-recent-tbody') || document.getElementById('recent-vitals-tbody');
  if (!tbody) return;

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);

  // Compute shift telemetry KPI figures
  const todayAssessments = rawVitalsData.filter(v => new Date(v.created_at) >= todayStart);
  const totalToday = todayAssessments.length;
  const alertToday = todayAssessments.filter(v => v._isAlert).length;
  const normalToday = totalToday - alertToday;
  const waitingToday = todayAssessments.filter(v => v._queueStatus === 'waiting' || v._queueStatus === 'on_call').length;

  const statTotalEl = document.getElementById('vitals-stat-total');
  const statNormalEl = document.getElementById('vitals-stat-normal');
  const statAlertEl = document.getElementById('vitals-stat-alert');
  const statQueueEl = document.getElementById('vitals-stat-queue');
  if (statTotalEl) statTotalEl.textContent = totalToday;
  if (statNormalEl) statNormalEl.textContent = normalToday;
  if (statAlertEl) statAlertEl.textContent = alertToday;
  if (statQueueEl) statQueueEl.textContent = waitingToday;

  // Update filter pill counts
  const countAllEl = document.getElementById('vitals-filter-all-count');
  const countAlertEl = document.getElementById('vitals-filter-alert-count');
  const countStableEl = document.getElementById('vitals-filter-stable-count');
  const countWaitingEl = document.getElementById('vitals-filter-waiting-count');
  if (countAllEl) countAllEl.textContent = rawVitalsData.length;
  if (countAlertEl) countAlertEl.textContent = rawVitalsData.filter(v => v._isAlert).length;
  if (countStableEl) countStableEl.textContent = rawVitalsData.filter(v => !v._isAlert).length;
  if (countWaitingEl) countWaitingEl.textContent = rawVitalsData.filter(v => v._queueStatus === 'waiting' || v._queueStatus === 'on_call').length;

  // Filter items
  const filtered = rawVitalsData.filter(v => {
    if (currentFilter === 'alert' && !v._isAlert) return false;
    if (currentFilter === 'stable' && v._isAlert) return false;
    if (currentFilter === 'waiting' && v._queueStatus !== 'waiting' && v._queueStatus !== 'on_call') return false;

    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      const name = (v._patientName || '').toLowerCase();
      const complaint = (v.chief_complaint || '').toLowerCase();
      const bp = (v.blood_pressure || '').toLowerCase();
      const code = (v._ticketCode || '').toLowerCase();
      if (!name.includes(q) && !complaint.includes(q) && !bp.includes(q) && !code.includes(q)) {
        return false;
      }
    }
    return true;
  });

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="9" style="text-align:center; padding:36px 16px; color:#94a3b8; font-size:13.5px;">
          ${searchQuery || currentFilter !== 'all' ? 'No triaged assessments match the active filter.' : 'No vital signs recorded recently. Click "New Walk-In Intake" or "Scan Citizen QR" to begin.'}
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(v => {
    const timeFormatted = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const bp = evaluateBp(v.blood_pressure);
    const hr = evaluateHr(v.heart_rate);
    const temp = evaluateTemp(v.temperature);
    const spo2 = evaluateSpo2(v.oxygen_saturation);

    const complaintSnippet = v.chief_complaint
      ? String(v.chief_complaint).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
      : 'Routine triage check';

    const ticketCodeBadge = v._ticketCode
      ? `<div style="display:inline-block; margin-top:3px; font-size:10px; font-weight:700; color:#4338ca; background:#e0e7ff; padding:1px 6px; border-radius:4px; font-family:monospace;">${v._ticketCode}</div>`
      : '';

    let severityHtml = '<span class="vitals-severity-badge severity-stable"><span style="width:6px; height:6px; border-radius:50%; background:#16a34a;"></span> Stable</span>';
    if (v._isAlert) {
      severityHtml = '<span class="vitals-severity-badge severity-alert"><span style="width:6px; height:6px; border-radius:50%; background:#e11d48;"></span> Attention</span>';
    }

    let queueStatusHtml = '<span class="vitals-queue-badge status-waiting">Waiting Consult</span>';
    if (v._queueStatus === 'serving' || v._queueStatus === 'on_call') {
      queueStatusHtml = '<span class="vitals-queue-badge status-serving">In Consult</span>';
    } else if (v._queueStatus === 'completed') {
      queueStatusHtml = '<span class="vitals-queue-badge status-completed">Completed</span>';
    }

    return `
      <tr class="account-row vitals-table-row" data-vitals-id="${v.id}" title="Click row to inspect clinical telemetry" style="cursor:pointer;">
        <td style="white-space:nowrap; vertical-align:middle;">
          <div style="font-weight:700; font-size:12.5px; color:#1e293b;">${timeFormatted}</div>
          ${ticketCodeBadge}
        </td>
        <td style="vertical-align:middle;">
          <div style="font-weight:700; font-size:13.5px; color:#0f172a;">${v._patientName}</div>
          <div style="font-size:11.5px; color:#64748b; margin-top:2px; max-width:280px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${complaintSnippet}">
            ${complaintSnippet}
          </div>
        </td>
        <td style="vertical-align:middle;">
          <span class="vitals-metric-pill pill-${bp.level}">
            ${bp.text ? `${bp.text} <span style="font-size:9.5px; font-weight:600; opacity:0.75;">mmHg</span>` : '—'}
          </span>
        </td>
        <td style="vertical-align:middle;">
          <span class="vitals-metric-pill pill-${hr.level}">
            ${hr.text || '—'}
          </span>
        </td>
        <td style="vertical-align:middle;">
          <span class="vitals-metric-pill pill-${temp.level}">
            ${temp.text || '—'}
          </span>
        </td>
        <td style="vertical-align:middle;">
          <span class="vitals-metric-pill pill-${spo2.level}">
            ${spo2.text || '—'}
          </span>
        </td>
        <td style="vertical-align:middle;">
          ${severityHtml}
        </td>
        <td style="vertical-align:middle;">
          ${queueStatusHtml}
        </td>
        <td style="vertical-align:middle; text-align:center;">
          <button type="button" class="chip-btn chip-btn-outline vitals-row-action-btn" style="padding:4px 10px; font-size:11px; font-weight:700; border-radius:8px; height:auto; color:#0f172a; border-color:#cbd5e1; background:#ffffff;">
            Details
          </button>
        </td>
      </tr>
    `;
  }).join('');

  // Attach modal detail viewers
  const rows = tbody.querySelectorAll('.vitals-table-row');
  rows.forEach((tr, index) => {
    const v = filtered[index];
    if (!v) return;

    const timeFormatted = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const dateFormatted = new Date(v.created_at).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });

    attachDetailRow(tr, () => ({
      tag: 'Vitals Triage Telemetry',
      title: v._patientName,
      subtitle: `Triaged on ${dateFormatted} at ${timeFormatted}`,
      items: [
        { label: 'Triage Severity', value: v._isAlert ? 'Needs Attention (Elevated / Out of Range)' : 'Stable (Normal Hemodynamic Parameters)' },
        { label: 'Queue Status', value: v._queueStatus ? v._queueStatus.toUpperCase() : 'TRIAGED' },
        { label: 'Queue Ticket', value: v._ticketCode || 'Direct Encounter' },
        { label: 'Blood Pressure', value: v.blood_pressure ? `${v.blood_pressure} mmHg` : '—' },
        { label: 'Heart Rate / Pulse', value: v.heart_rate ? `${v.heart_rate} bpm` : '—' },
        { label: 'Body Temperature', value: v.temperature ? `${v.temperature} °C` : '—' },
        { label: 'Oxygen Saturation (SpO2)', value: v.oxygen_saturation ? `${v.oxygen_saturation}%` : '—' },
        { label: 'Respiratory Rate', value: v.respiratory_rate ? `${v.respiratory_rate} breaths/min` : '—' },
        { label: 'Height', value: v.height_cm ? `${v.height_cm} cm` : '—' },
        { label: 'Weight', value: v.weight_kg ? `${v.weight_kg} kg` : '—' },
        { label: 'BMI', value: v.bmi ? `${v.bmi} kg/m²` : '—' },
        { label: 'Chief Complaint', value: v.chief_complaint || 'No complaint specified' },
        { label: 'Current Medications', value: v.current_medications || 'None declared' },
        { label: 'Patient Age', value: v.citizens?.age ? `${v.citizens.age} years old` : '—' },
        { label: 'Contact Number', value: v.citizens?.contact_number || '—' }
      ]
    }));
  });
}

export async function loadRecentVitals() {
  const tbody = document.getElementById('vitals-recent-tbody') || document.getElementById('recent-vitals-tbody');
  if (!tbody) return;

  try {
    const { data: vitals, error } = await supabase
      .from('vital_signs')
      .select(`
        id,
        created_at,
        blood_pressure,
        heart_rate,
        temperature,
        oxygen_saturation,
        respiratory_rate,
        chief_complaint,
        current_medications,
        height_cm,
        weight_kg,
        bmi,
        queue_ticket_id,
        queue_tickets (
          id,
          ticket_code,
          status,
          queue_number
        ),
        citizens (
          id,
          firstname,
          surname,
          age,
          contact_number,
          complete_address,
          allergies
        )
      `)
      .order('created_at', { ascending: false })
      .limit(30);

    if (error) throw error;

    // Normalize records and pre-evaluate alert statuses
    rawVitalsData = (vitals || []).map(v => {
      const citizen = v.citizens;
      const patientName = citizen ? `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() : 'Walk-in Patient';
      const bp = evaluateBp(v.blood_pressure);
      const hr = evaluateHr(v.heart_rate);
      const temp = evaluateTemp(v.temperature);
      const spo2 = evaluateSpo2(v.oxygen_saturation);
      const isAlert = bp.level === 'alert' || hr.level === 'alert' || temp.level === 'alert' || spo2.level === 'alert';

      const ticket = v.queue_tickets;
      const queueStatus = ticket?.status || 'waiting';
      const ticketCode = ticket?.ticket_code || (v.queue_ticket_id ? `Q-${v.queue_ticket_id}` : '');

      return {
        ...v,
        _patientName: patientName,
        _ticketCode: ticketCode,
        _queueStatus: queueStatus,
        _isAlert: isAlert
      };
    });

    renderVitalsTable();
  } catch (err) {
    console.warn('Error loading recent vitals:', err);
  }
}

export async function handleVitalsSubmission() {
  const submitBtn = document.getElementById('vitals-submit-btn');
  const citizenId = document.getElementById('vitals-citizen-id')?.value;
  const name = document.getElementById('vitals-name')?.value?.trim();
  const complaint = document.getElementById('vitals-complaint')?.value?.trim();
  const bp = document.getElementById('vitals-bp')?.value?.trim();
  const rr = document.getElementById('vitals-rr')?.value?.trim();
  const temp = document.getElementById('vitals-temp')?.value?.trim();
  const spo2 = document.getElementById('vitals-spo2')?.value?.trim();
  const meds = document.getElementById('vitals-meds')?.value?.trim();
  const hr = document.getElementById('vitals-hr')?.value?.trim();
  const sex = document.getElementById('vitals-sex')?.value?.trim();
  const allergies = document.getElementById('vitals-allergies')?.value?.trim();
  const contact = document.getElementById('vitals-contact')?.value?.trim();
  const address = document.getElementById('vitals-address')?.value?.trim();
  const age = document.getElementById('vitals-age')?.value?.trim();

  if (!complaint || (!citizenId && !name)) {
    showToast('Patient name and chief complaint are required.', 'error');
    return;
  }

  setLoading(submitBtn, true);

  try {
    const user = sessionStore.getUser();
    let finalCitizenId = citizenId ? Number(citizenId) : null;

    // Check if citizen exists by contact number or ID
    if (!finalCitizenId && contact) {
      try {
        const { data: matched } = await supabase
          .from('citizens')
          .select('id, firstname, surname, allergies')
          .eq('contact_number', contact)
          .maybeSingle();

        if (matched?.id) {
          finalCitizenId = matched.id;
          // Update allergies or address if newly provided
          const updates = {};
          if (allergies && (!matched.allergies || matched.allergies === 'None')) updates.allergies = allergies;
          if (address) updates.complete_address = address;
          if (Object.keys(updates).length > 0) {
            await supabase.from('citizens').update(updates).eq('id', finalCitizenId);
          }
        }
      } catch (cErr) {
        console.warn('Could not match citizen by contact:', cErr);
      }
    }

    // If new walk-in patient, register clinic record
    if (!finalCitizenId && name) {
      const nameParts = name.split(/\s+/);
      const firstname = nameParts[0] || 'Unknown';
      const surname = nameParts.length > 1 ? nameParts.slice(1).join(' ') : 'Patient';

      const citizenPayload = {
        firstname,
        surname,
        contact_number: contact || null,
        complete_address: address || null,
        age: parseInt(age) || null,
        sex: sex || null,
        allergies: allergies || null,
        email: contact ? `walkin_${contact.replace(/\D/g, '')}@ukonek.local` : `walkin_${Date.now()}@ukonek.local`
      };

      const { data: created, error: createError } = await supabase
        .from('citizens')
        .insert([citizenPayload])
        .select()
        .single();

      if (createError) throw createError;
      finalCitizenId = created.id;
    }

    const payload = {
      citizen_id: finalCitizenId,
      nurse_id: user?.id || null,
      chief_complaint: complaint,
      blood_pressure: bp || null,
      heart_rate: hr ? parseInt(hr) : null,
      respiratory_rate: rr ? parseInt(rr) : null,
      temperature: temp ? parseFloat(temp) : null,
      oxygen_saturation: spo2 ? parseInt(spo2) : null,
      current_medications: meds || null
    };

    if (activeVitalsQueueTicketId) {
      payload.queue_ticket_id = Number(activeVitalsQueueTicketId);
    }

    const { data: vitalsRow, error: vitalsError } = await supabase
      .from('vital_signs')
      .insert([payload])
      .select('id')
      .single();

    if (vitalsError) throw vitalsError;

    // If no queue ticket was linked, auto-issue a walk-in queue ticket so patient appears in the doctor queue
    if (!activeVitalsQueueTicketId && finalCitizenId) {
      try {
        const manilaDateStr = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
        const { data: nextNumData } = await supabase
          .from('queue_tickets')
          .select('queue_number')
          .eq('queue_date', manilaDateStr)
          .order('queue_number', { ascending: false })
          .limit(1);

        const nextNum = (nextNumData?.[0]?.queue_number || 0) + 1;
        const codeNum = String(nextNum).padStart(3, '0');
        const ticketCode = `Q-${manilaDateStr.replace(/-/g, '')}-GEN-${codeNum}`;

        const { data: newTicket } = await supabase
          .from('queue_tickets')
          .insert([{
            queue_date: manilaDateStr,
            service_key: 'general_consultation',
            service_label: 'General Consultation',
            queue_number: nextNum,
            ticket_code: ticketCode,
            citizen_id: finalCitizenId,
            citizen_type: 'regular',
            reason: complaint || 'Walk-in Consultation',
            symptoms: complaint || '',
            status: 'waiting',
            walkin_patient_name: name
          }])
          .select('id')
          .single();

        if (newTicket?.id && vitalsRow?.id) {
          await supabase
            .from('vital_signs')
            .update({ queue_ticket_id: newTicket.id })
            .eq('id', vitalsRow.id);
        }

        if (typeof window !== 'undefined' && window.loadQueueTickets) {
          window.loadQueueTickets();
        }
      } catch (qErr) {
        console.warn('Could not auto-generate queue ticket for triaged walk-in:', qErr);
      }
    }

    showToast('Vital signs recorded and patient queued for consultation.', 'success');
    activeVitalsQueueTicketId = null;

    document.getElementById('vitals-form')?.reset();
    document.getElementById('vitals-form-container')?.classList.add('hidden');
    setVitalsStationStatus('ready', 'Ready for Intake');
    loadRecentVitals();
  } catch (err) {
    console.error('Vitals submission error:', err);
    showToast('Failed to record vital signs.', 'error');
  } finally {
    setLoading(submitBtn, false);
  }
}

async function handleScannedCode(code) {
  if (!code) return;
  showToast(`Processing scanned code: ${code}`, 'info');

  try {
    const formContainer = document.getElementById('vitals-form-container');
    const vitalsForm = document.getElementById('vitals-form');

    // 1. Check if it's a queue ticket
    const { data: ticket } = await supabase
      .from('queue_tickets')
      .select('id, ticket_code, reason, symptoms, citizen_id, citizens(id, firstname, surname, age, sex, contact_number, complete_address, allergies)')
      .or(`ticket_code.eq.${code},id.eq.${parseInt(code) || 0}`)
      .maybeSingle();

    if (ticket) {
      activeVitalsQueueTicketId = ticket.id;
      const citizen = ticket.citizens;
      const patientName = citizen ? `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() : (ticket.walkin_patient_name || 'Queued Citizen');

      if (vitalsForm) {
        vitalsForm.reset();
        const cIdEl = document.getElementById('vitals-citizen-id');
        const nameEl = document.getElementById('vitals-name');
        const ageEl = document.getElementById('vitals-age');
        const sexEl = document.getElementById('vitals-sex');
        const contactEl = document.getElementById('vitals-contact');
        const addressEl = document.getElementById('vitals-address');
        const allergiesEl = document.getElementById('vitals-allergies');
        const complaintEl = document.getElementById('vitals-complaint');

        if (cIdEl) cIdEl.value = citizen?.id || ticket.citizen_id || '';
        if (nameEl) nameEl.value = patientName;
        if (ageEl && citizen?.age) ageEl.value = citizen.age;
        if (sexEl && citizen?.sex) sexEl.value = citizen.sex;
        if (contactEl && citizen?.contact_number) contactEl.value = citizen.contact_number;
        if (addressEl && citizen?.complete_address) addressEl.value = citizen.complete_address;
        if (allergiesEl && citizen?.allergies) allergiesEl.value = citizen.allergies;
        if (complaintEl) complaintEl.value = ticket.symptoms || ticket.reason || '';
      }

      formContainer?.classList.remove('hidden');
      setVitalsStationStatus('active', `Triage: ${patientName} (${ticket.ticket_code})`);
      showToast(`Loaded ticket ${ticket.ticket_code} for ${patientName}`, 'success');
      return;
    }

    // 2. Check if it's a Citizen ID (e.g. 104 or CIT-104)
    const citizenNumericId = parseInt(code.replace(/\D/g, ''), 10);
    if (citizenNumericId) {
      const { data: citizen } = await supabase
        .from('citizens')
        .select('*')
        .eq('id', citizenNumericId)
        .maybeSingle();

      if (citizen) {
        activeVitalsQueueTicketId = null;
        const patientName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim();

        if (vitalsForm) {
          vitalsForm.reset();
          const cIdEl = document.getElementById('vitals-citizen-id');
          const nameEl = document.getElementById('vitals-name');
          const ageEl = document.getElementById('vitals-age');
          const sexEl = document.getElementById('vitals-sex');
          const contactEl = document.getElementById('vitals-contact');
          const addressEl = document.getElementById('vitals-address');
          const allergiesEl = document.getElementById('vitals-allergies');

          if (cIdEl) cIdEl.value = citizen.id;
          if (nameEl) nameEl.value = patientName;
          if (ageEl && citizen.age) ageEl.value = citizen.age;
          if (sexEl && citizen.sex) sexEl.value = citizen.sex;
          if (contactEl && citizen.contact_number) contactEl.value = citizen.contact_number;
          if (addressEl && citizen.complete_address) addressEl.value = citizen.complete_address;
          if (allergiesEl && citizen.allergies) allergiesEl.value = citizen.allergies;
        }

        formContainer?.classList.remove('hidden');
        setVitalsStationStatus('active', `Triage: ${patientName}`);
        showToast(`Loaded citizen record for ${patientName}`, 'success');
        return;
      }
    }

    showToast(`No patient record found for scanned code "${code}". Please enter details manually.`, 'warning');
    formContainer?.classList.remove('hidden');
  } catch (err) {
    console.error('Error handling scanned QR:', err);
    showToast('Could not process scanned QR code.', 'error');
  }
}

async function startQrScanner() {
  const wrap = document.getElementById('vitals-scanner-wrap');
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const statusText = document.getElementById('qr-status');

  if (wrap) wrap.classList.remove('hidden');
  if (startBtn) startBtn.classList.add('hidden');
  if (stopBtn) stopBtn.classList.remove('hidden');
  if (statusText) statusText.textContent = 'Camera active. Position citizen QR code within the view...';

  if (typeof Html5Qrcode === 'undefined') {
    showToast('Camera scanner library is loading. Please try again.', 'warning');
    stopQrScanner();
    return;
  }

  if (!html5QrcodeScanner) {
    html5QrcodeScanner = new Html5Qrcode('reader');
  }

  const config = { fps: 10, qrbox: { width: 250, height: 250 } };

  try {
    await html5QrcodeScanner.start(
      { facingMode: 'environment' },
      config,
      async (decodedText) => {
        await stopQrScanner();
        await handleScannedCode(decodedText.trim());
      }
    );
  } catch (err) {
    console.error('Camera scanner start error:', err);
    showToast('Camera access denied or unavailable.', 'error');
    stopQrScanner();
  }
}

async function stopQrScanner() {
  const wrap = document.getElementById('vitals-scanner-wrap');
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const statusText = document.getElementById('qr-status');

  if (wrap) wrap.classList.add('hidden');
  if (startBtn) startBtn.classList.remove('hidden');
  if (stopBtn) stopBtn.classList.add('hidden');
  if (statusText) statusText.textContent = 'Position citizen QR slip within the frame';

  if (html5QrcodeScanner && html5QrcodeScanner.isScanning) {
    try {
      await html5QrcodeScanner.stop();
    } catch (err) {
      console.warn('Scanner stop error:', err);
    }
  }
}

export function initTriageSection() {
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const formContainer = document.getElementById('vitals-form-container');
  const vitalsForm = document.getElementById('vitals-form');
  const manualBtn = document.getElementById('manual-entry-btn');
  const cancelFormBtn = document.getElementById('vitals-cancel-form-btn');
  const closeModalXBtn = document.getElementById('vitals-close-modal');

  loadRecentVitals();

  ['vitals-bp', 'vitals-hr', 'vitals-rr', 'vitals-temp', 'vitals-spo2'].forEach(id => {
    document.getElementById(id)?.addEventListener('input', evaluateVitalsRisk);
  });

  if (vitalsForm) {
    vitalsForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      await handleVitalsSubmission();
    });
  }

  if (startBtn) startBtn.addEventListener('click', startQrScanner);
  if (stopBtn) stopBtn.addEventListener('click', stopQrScanner);

  if (manualBtn) {
    manualBtn.addEventListener('click', () => {
      setVitalsStationStatus('active', 'Walk-In Intake Active');
      formContainer?.classList.remove('hidden');
      vitalsForm?.reset();
      const cId = document.getElementById('vitals-citizen-id');
      if (cId) cId.value = '';
      activeVitalsQueueTicketId = null;
    });
  }

  [cancelFormBtn, closeModalXBtn].forEach(btn => {
    if (btn) {
      btn.addEventListener('click', () => {
        vitalsForm?.reset();
        formContainer?.classList.add('hidden');
        setVitalsStationStatus('ready', 'Ready for Intake');
        activeVitalsQueueTicketId = null;
      });
    }
  });

  // Search input live filtering
  const searchInput = document.getElementById('vitals-search-input');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      searchQuery = e.target.value.trim();
      renderVitalsTable();
    });
  }

  // Filter chips
  const filterChips = document.querySelectorAll('#vitals-filter-chips .ph-filter-chip');
  filterChips.forEach(chip => {
    chip.addEventListener('click', () => {
      filterChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      currentFilter = chip.dataset.filter || 'all';
      renderVitalsTable();
    });
  });
}
