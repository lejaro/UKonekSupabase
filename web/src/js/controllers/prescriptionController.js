/**
 * Prescription Controller
 * Handles prescription generation wizard, real-time allergy detection,
 * dosage and duration quantity calculations, and database recording.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import { showToast, setLoading } from '../utils/uiHelpers.js';
import { sanitizeText } from '../utils/dataDetailModal.js';
import { completeQueueTicket } from './consultationController.js';
import { medicines, refreshMedicineData } from './pharmacyController.js';
import { listMedicines } from '../services/pharmacyService.js';

export let cachedClinicMedicines = [];

export function normalizeMedName(str) {
  return String(str || '')
    .toLowerCase()
    .replace(/(\d+(\.\d+)?\s*(mg|g|mcg|ml|iu|%|meq)(\s*\/\s*\d+\s*(ml|l))?)/gi, '')
    .replace(/\b(capsule|tablet|cap|tab|suspension|susp|syrup|syr|drops|solution|ointment|cream|injection|inj|ampoule|vial)\b/gi, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function populateMedicineDatalist(medList) {
  const dl = document.getElementById('medicine-list');
  if (!dl || !Array.isArray(medList) || medList.length === 0) return;

  const newOptions = medList.map(m => {
    if (!m.name) return '';
    const desc = m.description ? ` • ${m.description}` : '';
    const stock = ` (${m.qty ?? 0} in stock)`;
    return `<option value="${m.name}">${m.name}${desc}${stock}</option>`;
  }).filter(Boolean);

  if (newOptions.length > 0) {
    dl.innerHTML = newOptions.join('');
  }
}

export function findMatchingMedicine(name, medList = cachedClinicMedicines) {
  if (!name || !Array.isArray(medList) || medList.length === 0) return null;
  const clean = String(name).trim().toLowerCase();

  // 1. Exact match
  const exact = medList.find(m => String(m.name || '').trim().toLowerCase() === clean);
  if (exact) return exact;

  // 2. Normalized generic name + matching dosage number (e.g. '500')
  const norm = normalizeMedName(clean);
  const numMatch = clean.match(/\d+/);
  if (norm) {
    if (numMatch) {
      const withNum = medList.find(m => {
        const mNorm = normalizeMedName(m.name);
        const mNum = String(m.name || '').match(/\d+/);
        return mNorm === norm && mNum && mNum[0] === numMatch[0];
      });
      if (withNum) return withNum;
    }
    const normMatch = medList.find(m => normalizeMedName(m.name) === norm);
    if (normMatch) return normMatch;
  }

  // 3. Substring containment
  const sub = medList.find(m => {
    const mClean = String(m.name || '').trim().toLowerCase();
    return (clean.length >= 4 && mClean.includes(clean)) || (mClean.length >= 4 && clean.includes(mClean));
  });
  return sub || null;
}

let activePatientAllergies = [];

export function canCreatePrescriptions() {
  const role = String(sessionStore.getUser()?.role || '').trim().toLowerCase();
  return role === 'doctor';
}

export function resolveCitizenId(patientIdentifier) {
  const raw = String(patientIdentifier || '').trim();
  if (!raw) return null;

  const citMatch = /^CIT-(\d+)$/i.exec(raw);
  if (citMatch) {
    const num = Number(citMatch[1]);
    return Number.isFinite(num) ? num : null;
  }

  const num = Number(raw);
  if (Number.isFinite(num) && num > 0) {
    return num;
  }

  return null;
}

export function calculatePrescriptionQty(freq = '', duration = '') {
  let dosesPerDay = 1;
  const f = freq.toLowerCase().trim();
  if (f.includes('bid') || f.includes('twice') || f.includes('q12h')) dosesPerDay = 2;
  else if (f.includes('tid') || f.includes('three') || f.includes('q8h')) dosesPerDay = 3;
  else if (f.includes('qid') || f.includes('four') || f.includes('q6h')) dosesPerDay = 4;
  else if (f.includes('q4h')) dosesPerDay = 6;
  else if (f.includes('q2h')) dosesPerDay = 12;
  else if (f.includes('stat')) dosesPerDay = 1;

  let days = 0;
  const d = duration.toLowerCase().trim();
  const numMatch = d.match(/(\d+)/);
  if (numMatch) {
    days = parseInt(numMatch[1], 10);
    if (d.includes('week')) days *= 7;
    else if (d.includes('month')) days *= 30;
  } else if (d.includes('maintenance')) {
    days = 30;
  }

  return dosesPerDay * (days || 1);
}

export async function openPrescriptionModalForPatient(patientId = '', consultationDbId = null, patientName = '', queueTicketId = null) {
  const modal = document.getElementById('prescription-modal');
  const patientInput = document.getElementById('prescription-patient');
  const displayEl = document.getElementById('prescription-patient-display');
  const form = document.getElementById('prescription-form');
  const lines = document.getElementById('prescription-lines');
  if (!modal) return;

  modal.classList.remove('hidden');

  if (patientInput) patientInput.value = patientId || '';
  if (displayEl) displayEl.textContent = patientName || patientId || '—';

  if (form) {
    form.dataset.consultationDbId = consultationDbId ? String(consultationDbId) : '';
    form.dataset.patientName = patientName || '';
    form.dataset.queueTicketId = queueTicketId ? String(queueTicketId) : '';
  }

  // Load and cache patient allergies
  activePatientAllergies = [];
  const currentAllergiesInput = document.getElementById('consult-allergies');
  if (currentAllergiesInput && currentAllergiesInput.value.trim() && currentAllergiesInput.value.trim() !== 'None') {
    const parts = currentAllergiesInput.value.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
    activePatientAllergies.push(...parts);
  }

  const cleanPatientId = String(patientId || '').trim();
  if (cleanPatientId) {
    try {
      const citizenId = resolveCitizenId(cleanPatientId);
      if (citizenId) {
        const { data: citizen } = await supabase
          .from('citizens')
          .select('allergies')
          .eq('id', citizenId)
          .maybeSingle();

        if (citizen?.allergies && citizen.allergies !== 'None') {
          const parts = citizen.allergies.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
          activePatientAllergies.push(...parts);
        }
      }
    } catch (err) {
      console.warn('Error fetching patient allergies:', err);
    }
  }

  activePatientAllergies = [...new Set(activePatientAllergies)];

  const prescAllergyBanner = document.getElementById('prescription-allergy-banner');
  const prescAllergyText = document.getElementById('prescription-allergy-text');
  if (prescAllergyBanner && prescAllergyText) {
    if (activePatientAllergies.length > 0) {
      prescAllergyBanner.style.display = 'block';
      prescAllergyText.textContent = `Patient is allergic to: ${activePatientAllergies.map(a => a.toUpperCase()).join(', ')}`;
    } else {
      prescAllergyBanner.style.display = 'none';
    }
  }

  // Load and populate real clinic inventory medicines
  try {
    const data = await listMedicines({ limit: 300 });
    cachedClinicMedicines = Array.isArray(data) ? data : [];
    populateMedicineDatalist(cachedClinicMedicines);
  } catch (err) {
    console.warn('Error loading medicines catalog for prescription modal:', err);
  }

  if (lines) {
    lines.innerHTML = '';
    addPrescriptionLine();
  }
}

export function closePrescriptionModal() {
  const modal = document.getElementById('prescription-modal');
  const form = document.getElementById('prescription-form');
  if (modal) modal.classList.add('hidden');
  if (form) {
    form.dataset.consultationDbId = '';
    form.dataset.queueTicketId = '';
    form.dataset.patientName = '';
    form.reset();
  }
}

export function addPrescriptionLine() {
  const container = document.getElementById('prescription-lines');
  if (!container) return;

  const line = document.createElement('div');
  line.className = 'field prescription-line-item';
  line.style.cssText = 'padding: 16px; background: #f8fafc; border-radius: 12px; margin-bottom: 16px; border: 1px solid #e2e8f0; box-shadow: 0 1px 2px rgba(0,0,0,0.05);';
  line.innerHTML = `
    <div style="display: grid; grid-template-columns: 2fr 0.6fr 1fr 1fr 1fr auto; gap: 10px; align-items: end;">
      <div class="field medicine-container" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Medicine Name</label>
        <input type="text" class="pres-med" list="medicine-list" placeholder="Search medicine (e.g. Amoxicillin)..." style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Qty</label>
        <input type="number" class="pres-qty" value="1" min="1" style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Dosage</label>
        <input type="text" class="pres-dosage" list="dosage-list" placeholder="e.g. 500 mg" style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Frequency</label>
        <input type="text" class="pres-freq" list="frequency-list" placeholder="e.g. TID" style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Duration</label>
        <input type="text" class="pres-duration" list="duration-list" placeholder="e.g. 7 days" style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <button type="button" class="btn small btn-delete" data-action="remove-line" style="height: 38px; width: 38px; min-width: 38px; display: flex; align-items: center; justify-content: center; font-size: 18px; line-height: 1; padding: 0; background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; margin: 0; border-radius: 8px; cursor: pointer;">&times;</button>
    </div>
    <div style="margin-top: 12px; padding-top: 12px; border-top: 1px dashed #e2e8f0;">
      <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Special Instructions / Remarks</label>
      <textarea class="pres-instructions" placeholder="Specific instructions for the patient (e.g. Take after meals, complete the full course)..." rows="2" style="width: 100%; box-sizing: border-box; resize: vertical; font-size: 13px; padding: 8px 10px; border-radius: 8px; border: 1px solid #e2e8f0; background: white; display: block;"></textarea>
    </div>
    <div class="allergy-warning-msg" style="display: none; font-size: 11px; font-weight: 700; color: #ef4444; margin-top: 6px;"></div>
  `;
  container.appendChild(line);

  const medInput = line.querySelector('.pres-med');
  const qtyInput = line.querySelector('.pres-qty');
  const freqInput = line.querySelector('.pres-freq');
  const durInput = line.querySelector('.pres-duration');
  const warningEl = line.querySelector('.allergy-warning-msg');

  const checkAllergy = () => {
    const medName = String(medInput?.value || '').toLowerCase().trim();
    if (!medName || activePatientAllergies.length === 0) {
      if (warningEl) warningEl.style.display = 'none';
      if (medInput) {
        medInput.style.borderColor = '#cbd5e1';
        medInput.style.background = '#ffffff';
      }
      return;
    }

    let foundAllergy = null;
    for (const allergy of activePatientAllergies) {
      const term = allergy.trim();
      if (term && (medName.includes(term) || term.includes(medName))) {
        foundAllergy = term;
        break;
      }
    }

    if (foundAllergy) {
      if (warningEl) {
        warningEl.textContent = `ALLERGY DETECTED: Patient has documented allergy to "${foundAllergy.toUpperCase()}"!`;
        warningEl.style.display = 'block';
      }
      if (medInput) {
        medInput.style.borderColor = '#ef4444';
        medInput.style.background = '#fef2f2';
      }
    } else {
      if (warningEl) warningEl.style.display = 'none';
      if (medInput) {
        medInput.style.borderColor = '#cbd5e1';
        medInput.style.background = '#ffffff';
      }
    }
  };

  const updateQty = () => {
    const freq = freqInput?.value || '';
    const dur = durInput?.value || '';
    if (freq || dur) {
      const calculated = calculatePrescriptionQty(freq, dur);
      if (calculated > 0 && qtyInput) {
        qtyInput.value = calculated;
      }
    }
  };

  medInput?.addEventListener('input', checkAllergy);
  medInput?.addEventListener('change', checkAllergy);
  freqInput?.addEventListener('input', updateQty);
  durInput?.addEventListener('input', updateQty);

  line.querySelector('[data-action="remove-line"]')?.addEventListener('click', () => {
    line.remove();
  });
}

export async function createPrescription({ patientId, consultationDbId, items }) {
  const cleanPatientId = String(patientId || '').trim();
  if (!cleanPatientId) throw new Error('Patient ID required.');

  const normalizedItems = Array.isArray(items)
    ? items
        .map((it) => ({
          name: String(it?.name || '').trim(),
          qty: Number(it?.qty) || 0,
          unit: String(it?.unit || '').trim(),
          dosage: String(it?.dosage || '').trim(),
          frequency: String(it?.frequency || '').trim(),
          duration: String(it?.duration || '').trim(),
          instructions: String(it?.instructions || '').trim()
        }))
        .filter((it) => it.name && it.qty > 0)
    : [];

  if (!normalizedItems.length) {
    throw new Error('Add at least one valid medicine.');
  }

  // Final Allergy Check Safeguard
  if (activePatientAllergies.length > 0) {
    for (const item of normalizedItems) {
      const medName = item.name.toLowerCase().trim();
      for (const allergy of activePatientAllergies) {
        const term = allergy.trim();
        if (term && (medName.includes(term) || term.includes(medName))) {
          throw new Error(`CRITICAL ALLERGY ALERT: Patient is allergic to "${term.toUpperCase()}". Cannot prescribe "${item.name}".`);
        }
      }
    }
  }

  const user = sessionStore.getUser();
  const doctorStaffId = Number(user?.id) || null;
  if (!doctorStaffId) {
    throw new Error('Unable to resolve doctor session. Please refresh and log in.');
  }

  let citizenId = resolveCitizenId(cleanPatientId);
  const consultId = Number.isFinite(Number(consultationDbId)) && Number(consultationDbId) > 0 ? Number(consultationDbId) : null;
  if (!citizenId && consultId) {
    try {
      const { data: conRow } = await supabase
        .from('consultations')
        .select('patient_citizen_id')
        .eq('id', consultId)
        .maybeSingle();
      if (conRow?.patient_citizen_id) {
        citizenId = conRow.patient_citizen_id;
      }
    } catch (_) {}
  }

  const headerPayload = {
    consultation_id: consultId,
    patient_identifier: cleanPatientId,
    patient_citizen_id: citizenId,
    doctor_staff_id: doctorStaffId,
    issued_at: new Date().toISOString()
  };

  let { data: header, error: headerError } = await supabase
    .from('prescription_headers')
    .insert(headerPayload)
    .select('id')
    .single();

  if (headerError && headerError.message && headerError.message.toLowerCase().includes('patient_citizen_id')) {
    delete headerPayload.patient_citizen_id;
    const retry = await supabase
      .from('prescription_headers')
      .insert(headerPayload)
      .select('id')
      .single();
    header = retry.data;
    headerError = retry.error;
  }

  if (headerError) throw new Error(headerError.message || 'Unable to create prescription header.');
  const headerId = header?.id;

  const itemRows = normalizedItems.map((it) => {
    let medId = null;
    const match = findMatchingMedicine(it.name, cachedClinicMedicines);
    if (match) {
      medId = match.id;
    }
    const row = {
      prescription_id: headerId,
      medicine_name: it.name,
      quantity: it.qty,
      unit: it.unit || match?.unit || 'pcs',
      dosage: it.dosage || null,
      frequency: it.frequency || null,
      duration: it.duration || null,
      instructions: it.instructions || null
    };
    if (medId) row.medicine_id = medId;
    return row;
  });

  let { error: itemsError } = await supabase
    .from('prescription_items')
    .insert(itemRows);

  if (itemsError && itemsError.message && itemsError.message.toLowerCase().includes('medicine_id')) {
    const fallbackRows = itemRows.map(({ medicine_id, ...rest }) => rest);
    const { error: retryErr } = await supabase
      .from('prescription_items')
      .insert(fallbackRows);
    itemsError = retryErr;
  }

  if (itemsError) throw new Error(itemsError.message || 'Unable to save prescription items.');

  return { id: headerId, patient: cleanPatientId, items: normalizedItems };
}

export function initPrescriptionController() {
  const addLineBtn = document.getElementById('add-prescription-line');
  const cancelBtn = document.getElementById('cancel-prescription');
  const modal = document.getElementById('prescription-modal');
  const form = document.getElementById('prescription-form');
  const modalCloseBtn = document.getElementById('prescription-modal-close');

  if (addLineBtn && !addLineBtn.dataset.bound) {
    addLineBtn.dataset.bound = 'true';
    addLineBtn.addEventListener('click', (e) => {
      e.preventDefault();
      addPrescriptionLine();
    });
  }

  if (cancelBtn && !cancelBtn.dataset.bound) {
    cancelBtn.dataset.bound = 'true';
    cancelBtn.addEventListener('click', (e) => {
      e.preventDefault();
      closePrescriptionModal();
    });
  }

  if (modalCloseBtn && !modalCloseBtn.dataset.bound) {
    modalCloseBtn.dataset.bound = 'true';
    modalCloseBtn.addEventListener('click', (e) => {
      e.preventDefault();
      closePrescriptionModal();
    });
  }

  if (modal && !modal.dataset.bound) {
    modal.dataset.bound = 'true';
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closePrescriptionModal();
    });
  }

  // Dosage shortcut preset chips
  document.querySelectorAll('.rx-preset-chip').forEach((btn) => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = 'true';
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const dosage = btn.getAttribute('data-dosage') || '';
      const sig = btn.getAttribute('data-sig') || '';

      const lines = document.getElementById('prescription-lines');
      let lastLine = lines?.lastElementChild;
      if (!lastLine) {
        addPrescriptionLine();
        lastLine = lines?.lastElementChild;
      }

      if (lastLine) {
        const dosageInput = lastLine.querySelector('.pres-dosage');
        const instructionsInput = lastLine.querySelector('.pres-instructions');
        if (dosageInput && dosage) dosageInput.value = dosage;
        if (instructionsInput && sig) instructionsInput.value = sig;
        showToast('Prescription shortcut applied.', 'info');
      }
    });
  });

  // Prescription Form Submit Handler
  if (form && !form.dataset.bound) {
    form.dataset.bound = 'true';
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (!canCreatePrescriptions()) {
        showToast('Only doctors can issue prescriptions.', 'warning');
        return;
      }

      const patientId = document.getElementById('prescription-patient')?.value?.trim();
      if (!patientId) {
        showToast('Patient identifier is missing.', 'warning');
        return;
      }

      const medInputs = form.querySelectorAll('.pres-med');
      const qtyInputs = form.querySelectorAll('.pres-qty');
      const dosageInputs = form.querySelectorAll('.pres-dosage');
      const freqInputs = form.querySelectorAll('.pres-freq');
      const durInputs = form.querySelectorAll('.pres-duration');
      const instrInputs = form.querySelectorAll('.pres-instructions');

      const items = [];
      for (let i = 0; i < medInputs.length; i++) {
        const name = medInputs[i]?.value?.trim();
        const qty = Number(qtyInputs[i]?.value) || 0;
        if (name && qty > 0) {
          items.push({
            name,
            qty,
            dosage: dosageInputs[i]?.value?.trim() || '',
            frequency: freqInputs[i]?.value?.trim() || '',
            duration: durInputs[i]?.value?.trim() || '',
            instructions: instrInputs[i]?.value?.trim() || ''
          });
        }
      }

      if (items.length === 0) {
        showToast('Please add at least one valid medication item.', 'warning');
        return;
      }

      const submitBtn = form.querySelector('button[type="submit"]');
      try {
        setLoading(submitBtn, true);
        await createPrescription({
          patientId,
          consultationDbId: Number(form.dataset.consultationDbId) || null,
          items
        });

        showToast('Prescription created successfully!', 'success');

        // Complete the queue ticket if linked
        const qId = form.dataset.queueTicketId;
        if (qId) {
          await completeQueueTicket(qId);
        }

        closePrescriptionModal();

        if (typeof window !== 'undefined' && window.loadQueueTickets) {
          window.loadQueueTickets();
        }
      } catch (err) {
        console.error('Prescription creation failed:', err);
        showToast(err.message || 'Failed to create prescription.', 'error');
      } finally {
        setLoading(submitBtn, false);
      }
    });
  }
}
