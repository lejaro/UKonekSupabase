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

      const statusBadge = '<span>Recorded</span>';

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
