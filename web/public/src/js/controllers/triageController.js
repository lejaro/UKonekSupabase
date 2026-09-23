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
        citizens (
          id,
          firstname,
          surname,
          age,
          contact_number
        )
      `)
      .order('created_at', { ascending: false })
      .limit(15);

    if (error) throw error;

    // Update today's triaged counter
    const countEl = document.getElementById('vitals-today-count');
    if (countEl) {
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const todayCount = (vitals || []).filter(v => new Date(v.created_at) >= todayStart).length;
      countEl.textContent = todayCount;
    }

    if (!vitals || vitals.length === 0) {
      tbody.innerHTML = '<tr><td colspan="4" style="text-align:center; padding:32px 16px; color:#94a3b8; font-size:13px;">No vital signs recorded recently.</td></tr>';
      return;
    }

    tbody.innerHTML = vitals.map(v => {
      const citizen = v.citizens;
      const patientName = citizen ? `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() : 'Walk-in Patient';
      const time = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      const statusBadge = '<span class="vitals-tag-normal"><svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="10"/></svg> Recorded</span>';

      const complaintSnippet = v.chief_complaint ? String(v.chief_complaint).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;') : '';

      return `
        <tr class="account-row vitals-table-row" title="Click to view full triage assessment" data-vitals-id="${v.id}">
          <td class="vitals-col-time">
            <span class="vitals-cell-time">${time}</span>
          </td>
          <td class="vitals-col-patient">
            <div class="vitals-cell-patient-name">${patientName}</div>
            ${complaintSnippet ? `<div class="vitals-cell-complaint" title="${complaintSnippet}">${complaintSnippet}</div>` : ''}
          </td>
          <td class="vitals-col-bp">
            <div class="vitals-bp-badge">
              <span>${v.blood_pressure || '—'}</span>
              ${v.blood_pressure ? '<span class="vitals-bp-unit">mmHg</span>' : ''}
            </div>
          </td>
          <td class="vitals-col-status">
            ${statusBadge}
          </td>
        </tr>
      `;
    }).join('');

    // Attach click-to-view modal with complete clinical assessment details
    const rows = tbody.querySelectorAll('.vitals-table-row');
    rows.forEach((tr, index) => {
      const v = vitals[index];
      if (!v) return;

      const citizen = v.citizens;
      const patientName = citizen ? `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() : 'Walk-in Patient';
      const timeFormatted = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      const dateFormatted = new Date(v.created_at).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });

      attachDetailRow(tr, () => ({
        tag: 'Vitals Triage',
        title: patientName,
        subtitle: `Triaged on ${dateFormatted} at ${timeFormatted}`,
        items: [
          { label: 'Triage Status', value: 'Recorded (Pending Physician Review)' },
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
          { label: 'Patient Age', value: citizen?.age ? `${citizen.age} years old` : '—' },
          { label: 'Contact Number', value: citizen?.contact_number || '—' }
        ]
      }));
    });

  } catch (err) {
    console.warn('Error loading recent vitals:', err);
  }
}

export async function handleVitalsSubmission() {
  const submitBtn = document.getElementById('vitals-submit-btn');
  const citizenId = document.getElementById('vitals-citizen-id')?.value;
  const name = document.getElementById('vitals-name')?.value;
  const complaint = document.getElementById('vitals-complaint')?.value;
  const bp = document.getElementById('vitals-bp')?.value;
  const rr = document.getElementById('vitals-rr')?.value;
  const temp = document.getElementById('vitals-temp')?.value;
  const spo2 = document.getElementById('vitals-spo2')?.value;
  const meds = document.getElementById('vitals-meds')?.value;
  const hr = document.getElementById('vitals-hr')?.value;

  if (!complaint || (!citizenId && !name)) {
    showToast('Patient name and chief complaint are required.', 'error');
    return;
  }

  setLoading(submitBtn, true);

  try {
    const user = sessionStore.getUser();
    let finalCitizenId = citizenId;

    if (!finalCitizenId && name) {
      const { data: created, error: createError } = await supabase
        .from('citizens')
        .insert([{
          firstname: name.split(' ')[0] || 'Unknown',
          surname: name.split(' ').slice(1).join(' ') || 'Patient',
          contact_number: document.getElementById('vitals-contact')?.value || null,
          complete_address: document.getElementById('vitals-address')?.value || null,
          age: parseInt(document.getElementById('vitals-age')?.value) || null,
          email: `walkin_${Date.now()}@ukonek.local`
        }])
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

    const { error } = await supabase.from('vital_signs').insert([payload]);
    if (error) throw error;

    showToast('Vital signs recorded successfully.', 'success');
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

export function initTriageSection() {
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const statusText = document.getElementById('qr-status');
  const formContainer = document.getElementById('vitals-form-container');
  const vitalsForm = document.getElementById('vitals-form');
  const manualBtn = document.getElementById('manual-entry-btn');
  const cancelFormBtn = document.getElementById('vitals-cancel-form-btn');

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

  if (cancelFormBtn) {
    cancelFormBtn.addEventListener('click', () => {
      vitalsForm?.reset();
      formContainer?.classList.add('hidden');
      setVitalsStationStatus('ready', 'Ready for Intake');
      activeVitalsQueueTicketId = null;
    });
  }
}
