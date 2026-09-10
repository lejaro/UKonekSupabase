/**
 * Vitals Triage & Clinical Risk Controller
 * Manages QR camera ticket scanning (Html5Qrcode), queue patient intake,
 * vital signs recording, and real-time clinical risk evaluation.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import { showToast, setLoading } from '../utils/uiHelpers.js';

let html5QrcodeScanner = null;
let activeVitalsQueueTicketId = null;
let vitalsInitialized = false;

export function evaluateVitalsRisk() {
  // 1. Blood Pressure Risk
  const bpInput = document.getElementById('va-bp') || document.getElementById('vitals-bp');
  const bpBadge = document.getElementById('va-bp-badge');
  if (bpInput && bpBadge) {
    const val = bpInput.value.trim();
    if (val && val.includes('/')) {
      const [sysStr, diaStr] = val.split('/');
      const sys = parseInt(sysStr, 10);
      const dia = parseInt(diaStr, 10);
      if (!isNaN(sys) && !isNaN(dia)) {
        bpBadge.className = 'vital-risk-badge';
        if (sys >= 180 || dia >= 120) {
          bpBadge.classList.add('vital-risk-crisis');
          bpBadge.textContent = 'Hypertensive Crisis';
        } else if (sys >= 140 || dia >= 90) {
          bpBadge.classList.add('vital-risk-stage2');
          bpBadge.textContent = 'Stage 2 HTN Alert';
        } else if (sys >= 130 || dia >= 80) {
          bpBadge.classList.add('vital-risk-stage1');
          bpBadge.textContent = 'Stage 1 HTN';
        } else if (sys >= 120 && dia < 80) {
          bpBadge.classList.add('vital-risk-elevated');
          bpBadge.textContent = 'Elevated BP';
        } else if (sys < 120 && dia < 80 && sys >= 90 && dia >= 60) {
          bpBadge.classList.add('vital-risk-normal');
          bpBadge.textContent = 'Normal BP';
        } else if (sys < 90 || dia < 60) {
          bpBadge.classList.add('vital-risk-hypo');
          bpBadge.textContent = 'Hypotension';
        }
      } else {
        bpBadge.classList.add('hidden');
      }
    } else {
      bpBadge.classList.add('hidden');
    }
  }

  // 2. Heart Rate Risk
  const hrInput = document.getElementById('va-hr') || document.getElementById('vitals-hr');
  const hrBadge = document.getElementById('va-hr-badge');
  if (hrInput && hrBadge) {
    const hr = parseFloat(hrInput.value);
    if (!isNaN(hr) && hr > 0) {
      hrBadge.className = 'vital-risk-badge';
      if (hr > 100) {
        hrBadge.classList.add('vital-risk-tachy');
        hrBadge.textContent = 'Tachycardia (>100 bpm)';
      } else if (hr < 60) {
        hrBadge.classList.add('vital-risk-brady');
        hrBadge.textContent = 'Bradycardia (<60 bpm)';
      } else {
        hrBadge.classList.add('vital-risk-normal');
        hrBadge.textContent = 'Normal Pulse';
      }
    } else {
      hrBadge.classList.add('hidden');
    }
  }

  // 3. Respiratory Rate Risk
  const rrInput = document.getElementById('va-rr') || document.getElementById('vitals-rr');
  const rrBadge = document.getElementById('va-rr-badge');
  if (rrInput && rrBadge) {
    const rr = parseFloat(rrInput.value);
    if (!isNaN(rr) && rr > 0) {
      rrBadge.className = 'vital-risk-badge';
      if (rr > 20) {
        rrBadge.classList.add('vital-risk-tachy');
        rrBadge.textContent = 'Tachypnea (>20 bpm)';
      } else if (rr < 12) {
        rrBadge.classList.add('vital-risk-brady');
        rrBadge.textContent = 'Bradypnea (<12 bpm)';
      } else {
        rrBadge.classList.add('vital-risk-normal');
        rrBadge.textContent = 'Normal RR';
      }
    } else {
      rrBadge.classList.add('hidden');
    }
  }

  // 4. Temperature Risk
  const tempInput = document.getElementById('va-temp') || document.getElementById('vitals-temp');
  const tempBadge = document.getElementById('va-temp-badge');
  if (tempInput && tempBadge) {
    const temp = parseFloat(tempInput.value);
    if (!isNaN(temp) && temp > 0) {
      tempBadge.className = 'vital-risk-badge';
      if (temp >= 38.0) {
        tempBadge.classList.add('vital-risk-fever');
        tempBadge.textContent = 'High Fever (≥38.0°C)';
      } else if (temp >= 37.5) {
        tempBadge.classList.add('vital-risk-elevated');
        tempBadge.textContent = 'Low-Grade Fever';
      } else if (temp < 35.5) {
        tempBadge.classList.add('vital-risk-hypo');
        tempBadge.textContent = 'Hypothermia Alert';
      } else {
        tempBadge.classList.add('vital-risk-normal');
        tempBadge.textContent = 'Afebrile (Normal)';
      }
    } else {
      tempBadge.classList.add('hidden');
    }
  }

  // 5. Oxygen Saturation Risk
  const spo2Input = document.getElementById('va-spo2') || document.getElementById('vitals-spo2');
  const spo2Badge = document.getElementById('va-spo2-badge');
  if (spo2Input && spo2Badge) {
    const spo2 = parseFloat(spo2Input.value);
    if (!isNaN(spo2) && spo2 > 0) {
      spo2Badge.className = 'vital-risk-badge';
      if (spo2 < 90) {
        spo2Badge.classList.add('vital-risk-hypoxia');
        spo2Badge.textContent = 'Critical Hypoxia (<90%)';
      } else if (spo2 < 95) {
        spo2Badge.classList.add('vital-risk-stage2');
        spo2Badge.textContent = 'Low SpO₂ (Hypoxia)';
      } else {
        spo2Badge.classList.add('vital-risk-normal');
        spo2Badge.textContent = 'Normal SpO₂ (≥95%)';
      }
    } else {
      spo2Badge.classList.add('hidden');
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
  const tbody = document.getElementById('recent-vitals-tbody');
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
        chief_complaint,
        citizens (
          firstname,
          surname
        )
      `)
      .order('created_at', { ascending: false })
      .limit(10);

    if (error) throw error;

    if (!vitals || vitals.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:20px; color:#94a3b8;">No vital signs recorded recently.</td></tr>';
      return;
    }

    let normalCount = 0;
    let flaggedCount = 0;

    tbody.innerHTML = vitals.map(v => {
      const citizen = v.citizens;
      const patientName = citizen ? `${citizen.firstname} ${citizen.surname}` : 'Walk-in Patient';
      const time = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

      let isFlagged = false;
      if (v.temperature && parseFloat(v.temperature) >= 38.0) isFlagged = true;
      if (v.oxygen_saturation && parseInt(v.oxygen_saturation) < 95) isFlagged = true;

      if (isFlagged) flaggedCount++;
      else normalCount++;

      const statusBadge = isFlagged
        ? '<span class="status-badge alert">Flagged</span>'
        : '<span class="status-badge normal">Normal</span>';

      return `
        <tr>
          <td><strong style="color:#0f172a;">${patientName}</strong><div style="font-size:11px;color:#64748b;">${time}</div></td>
          <td>${v.blood_pressure || '—'}</td>
          <td>${v.heart_rate ? `${v.heart_rate} bpm` : '—'}</td>
          <td>${v.temperature ? `${v.temperature}°C` : '—'}</td>
          <td>${v.oxygen_saturation ? `${v.oxygen_saturation}%` : '—'}</td>
          <td>${statusBadge}</td>
        </tr>
      `;
    }).join('');

    const normEl = document.getElementById('vitals-stat-normal');
    if (normEl) normEl.textContent = normalCount;
    const flagEl = document.getElementById('vitals-stat-flagged');
    if (flagEl) flagEl.textContent = flaggedCount;

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
