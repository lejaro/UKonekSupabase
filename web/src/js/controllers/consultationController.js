/**
 * Consultation Room & Clinical EHR Controller
 * Manages dual-pane physician consultation room, physical exam parser,
 * laboratory orders entry, and clinical diagnoses.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as consultationService from '../services/consultationService.js';
import { showToast, swapContainer, renderTableSkeleton, setLoading } from '../utils/uiHelpers.js';
import { formatPhysicalExam, cleanNone } from '../utils/clinicalFormatters.js';
import { attachDetailRow, sanitizeText } from '../utils/dataDetailModal.js';
import { showSection } from './navigationController.js';
import { openPrescriptionModalForPatient, resolveCitizenId } from './prescriptionController.js';
import { exportConsultationReport } from '../reports.js';

export let consultations = [];
export let consultationQueueTickets = [];
let consultSearchQuery = '';
let consultActiveFilterRange = 'all';

export function getManilaTodayStr() {
  const now = new Date();
  const manilaDate = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Manila' }));
  const year = manilaDate.getFullYear();
  const month = String(manilaDate.getMonth() + 1).padStart(2, '0');
  const day = String(manilaDate.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export async function loadConsultationData() {
  const tbody = document.getElementById('consultations-tbody');
  if (tbody) renderTableSkeleton(tbody, 5, 5);

  try {
    const data = await consultationService.listConsultations({ limit: 100 });
    consultations = Array.isArray(data) ? data : [];
    renderConsultations();
  } catch (err) {
    console.error('Failed to load consultations:', err);
    consultations = [];
    if (tbody) tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:24px; color:#94a3b8;">No consultations recorded.</td></tr>';
  }
}

export function renderConsultations() {
  const tbody = document.getElementById('consultations-tbody');
  if (!tbody) return;

  const dateFromInput = document.getElementById('consult-date-from');
  const dateToInput = document.getElementById('consult-date-to');
  const fromDate = dateFromInput?.value || '';
  const toDate = dateToInput?.value || '';

  const filtered = consultations.filter((c) => {
    const patientName = `${c.patient?.firstname || ''} ${c.patient?.surname || ''}`.toLowerCase();
    const diagnosis = String(c.diagnosis || '').toLowerCase();
    const matchesSearch = !consultSearchQuery || patientName.includes(consultSearchQuery) || diagnosis.includes(consultSearchQuery);

    const cDate = (c.consulted_at || c.created_at || '').slice(0, 10);
    let matchesDate = true;
    if (fromDate && cDate < fromDate) matchesDate = false;
    if (toDate && cDate > toDate) matchesDate = false;

    return matchesSearch && matchesDate;
  });

  const sortSelect = document.getElementById('consult-sort-select');
  const sortVal = sortSelect?.value || 'date-desc';
  filtered.sort((a, b) => {
    if (sortVal === 'date-asc') {
      return (a.consulted_at || a.created_at || '').localeCompare(b.consulted_at || b.created_at || '');
    } else if (sortVal === 'name-asc') {
      const nameA = `${a.patient?.firstname || ''} ${a.patient?.surname || ''}`.trim() || a.patient_identifier || '';
      const nameB = `${b.patient?.firstname || ''} ${b.patient?.surname || ''}`.trim() || b.patient_identifier || '';
      return nameA.localeCompare(nameB);
    }
    return (b.consulted_at || b.created_at || '').localeCompare(a.consulted_at || a.created_at || '');
  });

  if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:28px; color:#94a3b8;">No matching consultation records found.</td></tr>';
    return;
  }

  tbody.innerHTML = filtered.map((c) => {
    const patientName = `${c.patient?.firstname || ''} ${c.patient?.surname || ''}`.trim() || c.patient_identifier || 'Walk-in Patient';
    const patientId = c.patient_citizen_id ? `#${c.patient_citizen_id}` : '—';
    const diagnosis = c.diagnosis || 'General Checkup';
    const consultedDate = c.consulted_at ? new Date(c.consulted_at).toLocaleDateString() : '—';
    const followUp = c.follow_up_date || '—';

    return `
      <tr>
        <td class="table-cell"><strong style="color:#0f172a;">${sanitizeText(patientName)}</strong></td>
        <td class="table-cell">${sanitizeText(patientId)}</td>
        <td class="table-cell"><span class="clinical-diagnosis-pill">${sanitizeText(diagnosis)}</span></td>
        <td class="table-cell">${sanitizeText(followUp)}</td>
        <td class="table-cell">${sanitizeText(consultedDate)}</td>
        <td class="table-cell" style="text-align:right;">
          <button type="button" class="btn small outline" data-action="view-consult" data-id="${c.id}" style="padding:3px 10px; font-size:11.5px; border-radius:9999px;">View Notes</button>
        </td>
      </tr>
    `;
  }).join('');

  tbody.querySelectorAll('tr').forEach((tr, index) => {
    const c = filtered[index];
    if (!c) return;

    attachDetailRow(tr, () => ({
      tag: 'Clinical Consultation',
      title: `${c.patient?.firstname || ''} ${c.patient?.surname || ''}`.trim() || 'Patient Record',
      subtitle: `Consulted on ${c.consulted_at ? new Date(c.consulted_at).toLocaleDateString() : '—'}`,
      items: [
        { label: 'Diagnosis', value: c.diagnosis || '—' },
        { label: 'Chief Complaint / Symptoms', value: c.symptoms || '—' },
        { label: 'Attending Doctor', value: c.doctor ? `Dr. ${c.doctor.first_name || ''} ${c.doctor.last_name || ''}`.trim() : 'Attending Physician' },
        { label: 'Clinical Notes', value: c.notes || '—' }
      ]
    }));
  });
}

export function initConsultationQuickDiagnosis() {
  const diagInput = document.getElementById('consult-diagnosis');
  document.querySelectorAll('.diag-chip, .quick-diag-chip').forEach((btn) => {
    if (btn.dataset.bound === 'true') return;
    btn.dataset.bound = 'true';
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const diagVal = btn.getAttribute('data-diag') || btn.getAttribute('data-val');
      if (diagInput && diagVal) {
        diagInput.value = diagVal;
        showToast(`Diagnosis applied: ${diagVal}`, 'info');

        // Switch to Diagnosis tab so the physician sees the populated field
        const diagTabBtn = document.querySelector('#consultation-modal .modal-tab[data-tab="tab-diagnosis"]');
        if (diagTabBtn) {
          diagTabBtn.click();
        }
        diagInput.focus();
      }
    });
  });
}

export function initConsultationTabs() {
  const modal = document.getElementById('consultation-modal');
  const tabs = document.querySelectorAll('#consultation-modal .modal-tab');
  const nextBtn = document.getElementById('consult-next-btn');
  const prevBtn = document.getElementById('consult-prev-btn');
  const submitBtn = document.getElementById('consult-submit-btn');

  const updateButtons = (activeTabId) => {
    if (!nextBtn || !prevBtn || !submitBtn) return;

    if (activeTabId === 'tab-history') {
      prevBtn.classList.add('hidden');
      nextBtn.classList.remove('hidden');
      submitBtn.classList.add('hidden');
    } else if (activeTabId === 'tab-exam') {
      prevBtn.classList.remove('hidden');
      nextBtn.classList.remove('hidden');
      submitBtn.classList.add('hidden');
    } else if (activeTabId === 'tab-diagnosis') {
      prevBtn.classList.remove('hidden');
      nextBtn.classList.add('hidden');
      submitBtn.classList.remove('hidden');
    }
  };

  tabs.forEach((tab) => {
    if (tab.dataset.bound === 'true') return;
    tab.dataset.bound = 'true';
    tab.addEventListener('click', (e) => {
      e.preventDefault();
      const targetId = tab.dataset.tab;

      tabs.forEach((t) => t.classList.remove('active'));
      tab.classList.add('active');

      document.querySelectorAll('#consultation-modal .tab-content').forEach((content) => {
        content.classList.remove('active');
      });
      const targetContent = document.getElementById(targetId);
      if (targetContent) {
        targetContent.classList.add('active');
      }

      updateButtons(targetId);
    });
  });

  if (nextBtn && !nextBtn.dataset.bound) {
    nextBtn.dataset.bound = 'true';
    nextBtn.addEventListener('click', (e) => {
      e.preventDefault();
      const activeTab = document.querySelector('#consultation-modal .modal-tab.active');
      const curTab = activeTab?.dataset.tab;
      if (curTab === 'tab-history') {
        document.querySelector('#consultation-modal .modal-tab[data-tab="tab-exam"]')?.click();
      } else if (curTab === 'tab-exam') {
        document.querySelector('#consultation-modal .modal-tab[data-tab="tab-diagnosis"]')?.click();
      }
    });
  }

  if (prevBtn && !prevBtn.dataset.bound) {
    prevBtn.dataset.bound = 'true';
    prevBtn.addEventListener('click', (e) => {
      e.preventDefault();
      const activeTab = document.querySelector('#consultation-modal .modal-tab.active');
      const curTab = activeTab?.dataset.tab;
      if (curTab === 'tab-exam') {
        document.querySelector('#consultation-modal .modal-tab[data-tab="tab-history"]')?.click();
      } else if (curTab === 'tab-diagnosis') {
        document.querySelector('#consultation-modal .modal-tab[data-tab="tab-exam"]')?.click();
      }
    });
  }

  const activeTabId = document.querySelector('#consultation-modal .modal-tab.active')?.dataset.tab || 'tab-history';
  updateButtons(activeTabId);
}

export async function handleDoctorConsultationReport(btn) {
  if (!btn) return;
  const originalHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = `
    <span class="loading-spinner" style="width:13px; height:13px; border:2px solid #cbd5e1; border-top-color:#0284c7; border-radius:50%; display:inline-block; animation:spin 0.8s linear infinite;"></span>
    <span>Exporting...</span>
  `;

  try {
    const dateFromInput = document.getElementById('consult-date-from');
    const dateToInput = document.getElementById('consult-date-to');
    const startDate = dateFromInput?.value || null;
    const endDate = dateToInput?.value || null;
    const searchInput = document.getElementById('consult-search-input');
    const searchQuery = searchInput?.value || consultSearchQuery || '';

    const result = await exportConsultationReport(startDate, endDate, searchQuery);

    if (result && result.count > 0) {
      showToast(`Consultation report exported successfully! (${result.count} records)`, 'success');
    } else {
      showToast('No consultation records found matching current criteria.', 'info');
    }
  } catch (err) {
    console.error('Failed to export consultation report:', err);
    showToast(err.message || 'Unable to generate consultation report.', 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = originalHtml;
  }
}

export function initConsultationToolbar() {
  const searchInput = document.getElementById('consult-search-input');
  if (searchInput && !searchInput.dataset.initialized) {
    searchInput.dataset.initialized = 'true';
    searchInput.addEventListener('input', (e) => {
      consultSearchQuery = e.target.value.trim().toLowerCase();
      renderConsultations();
    });
  }

  const chips = document.querySelectorAll('.consult-preset-chip');
  chips.forEach((chip) => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        chips.forEach((c) => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        consultActiveFilterRange = chip.dataset.range;

        const dateFromInput = document.getElementById('consult-date-from');
        const dateToInput = document.getElementById('consult-date-to');
        const todayStr = getManilaTodayStr();

        if (consultActiveFilterRange === 'today') {
          if (dateFromInput) dateFromInput.value = todayStr;
          if (dateToInput) dateToInput.value = todayStr;
        } else if (consultActiveFilterRange === 'week') {
          const d = new Date();
          d.setDate(d.getDate() - 7);
          if (dateFromInput) dateFromInput.value = d.toISOString().slice(0, 10);
          if (dateToInput) dateToInput.value = todayStr;
        } else if (consultActiveFilterRange === 'month') {
          const d = new Date();
          d.setDate(d.getDate() - 30);
          if (dateFromInput) dateFromInput.value = d.toISOString().slice(0, 10);
          if (dateToInput) dateToInput.value = todayStr;
        } else {
          if (dateFromInput) dateFromInput.value = '';
          if (dateToInput) dateToInput.value = '';
        }
        renderConsultations();
      });
    }
  });

  const dateFromInput = document.getElementById('consult-date-from');
  const dateToInput = document.getElementById('consult-date-to');
  const clearBtn = document.getElementById('consult-date-clear');
  const sortSelect = document.getElementById('consult-sort-select');

  if (dateFromInput && !dateFromInput.dataset.bound) {
    dateFromInput.dataset.bound = 'true';
    dateFromInput.addEventListener('change', () => renderConsultations());
  }
  if (dateToInput && !dateToInput.dataset.bound) {
    dateToInput.dataset.bound = 'true';
    dateToInput.addEventListener('change', () => renderConsultations());
  }
  if (clearBtn && !clearBtn.dataset.bound) {
    clearBtn.dataset.bound = 'true';
    clearBtn.addEventListener('click', (e) => {
      e.preventDefault();
      if (dateFromInput) dateFromInput.value = '';
      if (dateToInput) dateToInput.value = '';
      chips.forEach((c) => c.classList.toggle('is-active', c.dataset.range === 'all'));
      renderConsultations();
    });
  }
  if (sortSelect && !sortSelect.dataset.bound) {
    sortSelect.dataset.bound = 'true';
    sortSelect.addEventListener('change', () => renderConsultations());
  }

  const reportBtn = document.getElementById('consult-report-btn');
  if (reportBtn && !reportBtn.dataset.bound) {
    reportBtn.dataset.bound = 'true';
    reportBtn.addEventListener('click', (e) => {
      e.preventDefault();
      handleDoctorConsultationReport(reportBtn);
    });
  }
}

export async function initLabSection() {
  const tbody = document.getElementById('lab-orders-tbody');
  if (!tbody) return;

  try {
    const { data: orders, error } = await supabase
      .from('lab_orders')
      .select(`
        id,
        test_name,
        status,
        created_at,
        citizen:citizens (
          firstname,
          surname
        )
      `)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) throw error;

    if (!orders || orders.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:20px; color:#94a3b8;">No laboratory orders active.</td></tr>';
      return;
    }

    tbody.innerHTML = orders.map((o) => {
      const patientName = o.citizen ? `${o.citizen.firstname} ${o.citizen.surname}` : 'Walk-in Patient';
      const statusClass = o.status === 'Completed' ? 'badge-success' : 'badge-warning';
      const actionBtn = o.status === 'Pending'
        ? `<button class="btn small" onclick="updateLabOrderStatus('${o.id}', 'Completed')">Mark Done</button>`
        : '—';

      return `
        <tr>
          <td><strong style="color:#0f172a;">${sanitizeText(patientName)}</strong></td>
          <td>${sanitizeText(o.test_name || 'Laboratory Test')}</td>
          <td><span class="badge ${statusClass}">${sanitizeText(o.status || 'Pending')}</span></td>
          <td>${o.created_at ? new Date(o.created_at).toLocaleDateString() : '—'}</td>
          <td style="text-align:right;">${actionBtn}</td>
        </tr>
      `;
    }).join('');
  } catch (err) {
    console.warn('Error loading lab orders:', err);
  }
}

export async function updateLabOrderStatus(orderId, status) {
  try {
    const { error } = await supabase
      .from('lab_orders')
      .update({ status, completed_at: new Date().toISOString() })
      .eq('id', orderId);

    if (error) throw error;
    showToast('Lab order updated.', 'success');
    initLabSection();
  } catch (err) {
    console.error('Update lab order error:', err);
    showToast('Failed to update lab order.', 'error');
  }
}

// Preserve window global for dynamic button click handler
if (typeof window !== 'undefined') {
  window.updateLabOrderStatus = updateLabOrderStatus;
}

export function initPrescriptionDosagePresets() {
  document.querySelectorAll('.rx-preset-chip').forEach(btn => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = 'true';
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const dosage = btn.getAttribute('data-dosage');
      const sig = btn.getAttribute('data-sig');

      const linesContainer = document.getElementById('prescription-lines');
      let lastLine = linesContainer?.lastElementChild;
      if (!lastLine) {
        const addBtn = document.getElementById('add-prescription-line');
        if (addBtn) {
          addBtn.click();
          lastLine = linesContainer?.lastElementChild;
        }
      }

      if (lastLine) {
        const dosageInput = lastLine.querySelector('.rx-dosage-input') || lastLine.querySelector('input[placeholder*="Dosage"]');
        const sigInput = lastLine.querySelector('.rx-instructions-input') || lastLine.querySelector('input[placeholder*="Instructions"]');
        if (dosageInput && dosage) dosageInput.value = dosage;
        if (sigInput && sig) sigInput.value = sig;
        showToast('Prescription dosage shortcut applied.', 'info');
      }
    });
  });
}

export async function loadVitalsForConsultation(queueTicketId) {
  if (!queueTicketId) return;
  try {
    const { data, error } = await supabase.rpc('get_vitals_for_ticket', {
      p_queue_ticket_id: Number(queueTicketId)
    });
    if (error || !data) return;

    const banner = document.getElementById('consult-vitals-banner');
    const grid = document.getElementById('consult-vitals-grid');
    const complaintEl = document.getElementById('consult-vitals-complaint');
    const notesEl = document.getElementById('consult-vitals-notes');
    const allergyBox = document.getElementById('consult-allergy-alert');
    const allergyText = document.getElementById('consult-allergy-text');
    if (!banner || !grid) return;

    // Check for critical allergy warning
    const allergies = data.allergies || data.drug_allergies || (data.notes && data.notes.toLowerCase().includes('allerg') ? data.notes : null);
    if (allergies && allergyBox && allergyText) {
      allergyText.textContent = allergies;
      allergyBox.classList.remove('hidden');
      const allergyInput = document.getElementById('consult-allergies');
      if (allergyInput && (!allergyInput.value || allergyInput.value === 'None')) {
        allergyInput.value = allergies;
      }
    } else if (allergyBox) {
      allergyBox.classList.add('hidden');
    }

    const vitals = [
      { label: 'BP', value: data.blood_pressure ? `${data.blood_pressure} mmHg` : null },
      { label: 'HR', value: data.heart_rate ? `${data.heart_rate} bpm` : null },
      { label: 'Temp', value: data.temperature ? `${data.temperature} °C` : null },
      { label: 'RR', value: data.respiratory_rate ? `${data.respiratory_rate} bpm` : null },
      { label: 'SpO₂', value: data.oxygen_saturation ? `${data.oxygen_saturation}%` : null },
      { label: 'Height', value: data.height_cm ? `${data.height_cm} cm` : null },
      { label: 'Weight', value: data.weight_kg ? `${data.weight_kg} kg` : null },
      { label: 'BMI', value: data.bmi ? `${data.bmi}` : null },
    ].filter(v => v.value);

    if (vitals.length === 0 && !data.chief_complaint) return;

    grid.innerHTML = vitals.map(v => `
      <div class="vitals-mini-card">
        <div class="v-label">${v.label}</div>
        <div class="v-val">${v.value}</div>
      </div>
    `).join('');

    if (complaintEl) {
      complaintEl.innerHTML = data.chief_complaint
        ? `<strong>Chief Complaint:</strong> ${data.chief_complaint}`
        : '';
    }
    if (notesEl) {
      const nurseName = data.nurse_name ? ` (${data.nurse_name})` : '';
      notesEl.innerHTML = data.notes
        ? `<strong>Nurse Notes${nurseName}:</strong> ${data.notes}`
        : (nurseName ? `<span style="color:#6b7280;">Assessed by${nurseName}</span>` : '');
      if (data.current_medications) {
        notesEl.innerHTML += `<br><strong>Current Meds:</strong> ${data.current_medications}`;
      }
    }

    const hpiInput = document.getElementById('consult-hpi');
    if (hpiInput && (!hpiInput.value || hpiInput.value === 'None') && data.chief_complaint) {
      hpiInput.value = data.chief_complaint;
    }

    banner.style.display = 'block';
  } catch (_) {
    // Non-critical — vitals banner just stays hidden
  }
}

export function openConsultationModal(prefill = {}) {
  const consultationModal = document.getElementById('consultation-modal');
  const consultationForm = document.getElementById('consultation-form');
  if (!consultationModal) return;
  if (consultationForm) consultationForm.reset();

  // Reset tab to History
  consultationModal.querySelectorAll('.modal-tab').forEach(t => t.classList.remove('active'));
  consultationModal.querySelector('.modal-tab[data-tab="tab-history"]')?.classList.add('active');
  consultationModal.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  consultationModal.querySelector('#tab-history')?.classList.add('active');

  // Reset navigation buttons
  const nextBtn = document.getElementById('consult-next-btn');
  const prevBtn = document.getElementById('consult-prev-btn');
  const submitBtn = document.getElementById('consult-submit-btn');
  if (prevBtn) prevBtn.classList.add('hidden');
  if (nextBtn) nextBtn.classList.remove('hidden');
  if (submitBtn) submitBtn.classList.add('hidden');

  const patientInput = document.getElementById('consult-patient-id');
  const displayId = document.getElementById('consult-display-id');
  if (patientInput && prefill.patientId) patientInput.value = prefill.patientId;

  // Show patient name + service in modal header
  if (displayId) {
    const namePart = prefill.patientName ? `<strong>${sanitizeText(prefill.patientName)}</strong>` : '';
    const idPart = prefill.patientId ? `<span style="color:#cbd5e1">(${sanitizeText(String(prefill.patientId))})</span>` : '—';
    const servicePart = prefill.serviceLabel ? ` &mdash; <em>${sanitizeText(prefill.serviceLabel)}</em>` : '';
    displayId.innerHTML = `${namePart} ${idPart}${servicePart}`.trim();
  }

  // Store queue ticket id on form for later use
  if (consultationForm) {
    consultationForm.dataset.queueTicketId = prefill.queueTicketId ? String(prefill.queueTicketId) : '';
    consultationForm.dataset.patientName = prefill.patientName || '';
  }

  // Pre-fill fields answerable by "None" when no answers
  const defaultNoneFields = [
    { id: 'consult-pmh', val: prefill.pmh },
    { id: 'consult-allergies', val: prefill.allergies },
    { id: 'consult-immunization', val: prefill.immunization },
    { id: 'consult-social', val: prefill.social },
    { id: 'exam-heent', val: prefill.exam_heent },
    { id: 'exam-chest', val: prefill.exam_chest },
    { id: 'exam-abdomen', val: prefill.exam_abdomen },
    { id: 'exam-extremities', val: prefill.exam_extremities },
    { id: 'exam-others', val: prefill.exam_others },
    { id: 'consult-differential', val: prefill.differential },
    { id: 'consult-lab-orders', val: prefill.lab_orders },
    { id: 'consult-notes', val: prefill.notes }
  ];

  defaultNoneFields.forEach(({ id, val }) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.value = (val && String(val).trim()) ? String(val).trim() : 'None';
    if (!el.dataset.noneBehaviorAttached) {
      el.dataset.noneBehaviorAttached = 'true';
      el.addEventListener('focus', function () {
        if (this.value === 'None') this.select();
      });
      el.addEventListener('blur', function () {
        if (!this.value.trim()) this.value = 'None';
      });
    }
  });

  const hpiInput = document.getElementById('consult-hpi');
  if (hpiInput) {
    const initialHpi = prefill.symptoms || prefill.hpi;
    hpiInput.value = (initialHpi && String(initialHpi).trim()) ? String(initialHpi).trim() : 'None';
    if (!hpiInput.dataset.noneBehaviorAttached) {
      hpiInput.dataset.noneBehaviorAttached = 'true';
      hpiInput.addEventListener('focus', function () {
        if (this.value === 'None') this.select();
      });
      hpiInput.addEventListener('blur', function () {
        if (!this.value.trim()) this.value = 'None';
      });
    }
  }

  // Hide vitals banner initially, then fetch if ticket linked
  const vitalsBanner = document.getElementById('consult-vitals-banner');
  if (vitalsBanner) vitalsBanner.style.display = 'none';
  if (prefill.queueTicketId) {
    loadVitalsForConsultation(Number(prefill.queueTicketId));
  }

  initConsultationTabs();
  initConsultationQuickDiagnosis();
  initPrescriptionDosagePresets();
  consultationModal.classList.remove('hidden');
}

export function closeConsultationModal() {
  const consultationModal = document.getElementById('consultation-modal');
  const consultationForm = document.getElementById('consultation-form');
  if (!consultationModal) return;
  consultationModal.classList.add('hidden');
  if (consultationForm) consultationForm.reset();
}

export async function completeQueueTicket(ticketId) {
  if (!ticketId) return;
  try {
    await supabase
      .from('queue_tickets')
      .update({ status: 'completed', completed_at: new Date().toISOString() })
      .eq('id', Number(ticketId));
    if (typeof window !== 'undefined' && window.loadQueueTickets) {
      window.loadQueueTickets();
    }
  } catch (err) {
    console.warn('Could not complete queue ticket:', err);
  }
}

export function initConsultationSection() {
  initConsultationToolbar();
  initConsultationQuickDiagnosis();
  initConsultationTabs();
  initPrescriptionDosagePresets();
  loadConsultationData();
  initLabSection();

  const openModalBtn = document.getElementById('open-consult-modal-btn');
  const consultModal = document.getElementById('consultation-modal');
  const closeIcon = document.getElementById('consult-modal-close-icon');
  const cancelBtn = document.getElementById('consultation-cancel-btn');
  const consultationForm = document.getElementById('consultation-form');

  if (openModalBtn) {
    openModalBtn.addEventListener('click', () => {
      const user = sessionStore.getUser();
      if (String(user?.role || '').toLowerCase() !== 'doctor') {
        showToast('Only doctors can conduct consultations.', 'warning');
        return;
      }
      openConsultationModal();
    });
  }

  if (closeIcon) {
    closeIcon.addEventListener('click', closeConsultationModal);
  }

  if (cancelBtn) {
    cancelBtn.addEventListener('click', closeConsultationModal);
  }

  if (consultModal) {
    consultModal.addEventListener('click', (e) => {
      if (e.target === consultModal) closeConsultationModal();
    });
  }

  if (consultationForm && !consultationForm.dataset.bound) {
    consultationForm.dataset.bound = 'true';
    consultationForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const user = sessionStore.getUser();
      if (String(user?.role || '').toLowerCase() !== 'doctor') {
        showToast('Only doctors can conduct consultations.', 'warning');
        return;
      }

      const submitBtn = document.getElementById('consult-submit-btn');
      const patientId = document.getElementById('consult-patient-id')?.value || '';
      const patientName = consultationForm.dataset.patientName || '';
      const diagnosis = document.getElementById('consult-diagnosis')?.value || '';

      if (!diagnosis) {
        showToast('Diagnosis is required.', 'warning');
        document.querySelector('[data-tab="tab-diagnosis"]')?.click();
        return;
      }

      try {
        setLoading(submitBtn, true);
        const doctorStaffId = Number(user?.id) || null;
        if (!doctorStaffId) {
          throw new Error('Unable to resolve doctor staff session.');
        }

        const citizenId = resolveCitizenId(patientId);

        const payload = {
          patient_identifier: String(patientId || '').trim(),
          patient_citizen_id: citizenId,
          doctor_staff_id: doctorStaffId,
          symptoms: cleanNone(document.getElementById('consult-hpi')?.value),
          diagnosis: String(diagnosis).trim(),
          notes: cleanNone(document.getElementById('consult-notes')?.value),
          hpi: cleanNone(document.getElementById('consult-hpi')?.value),
          pmh: cleanNone(document.getElementById('consult-pmh')?.value),
          allergies: cleanNone(document.getElementById('consult-allergies')?.value),
          immunization_status: cleanNone(document.getElementById('consult-immunization')?.value),
          social_history: cleanNone(document.getElementById('consult-social')?.value),
          physical_exam: {
            heent: cleanNone(document.getElementById('exam-heent')?.value || document.getElementById('consult-heent')?.value),
            chest: cleanNone(document.getElementById('exam-chest')?.value || document.getElementById('consult-chest')?.value),
            heart: cleanNone(document.getElementById('consult-heart')?.value),
            abdomen: cleanNone(document.getElementById('exam-abdomen')?.value || document.getElementById('consult-abdomen')?.value),
            extremities: cleanNone(document.getElementById('exam-extremities')?.value || document.getElementById('consult-extremities')?.value),
            neurological: cleanNone(document.getElementById('consult-neurological')?.value),
            others: cleanNone(document.getElementById('exam-others')?.value)
          },
          differential_diagnosis: cleanNone(document.getElementById('consult-differential')?.value),
          lab_orders: cleanNone(document.getElementById('consult-lab-orders')?.value),
          follow_up_date: document.getElementById('consult-followup')?.value || null,
          consulted_at: new Date().toISOString()
        };

        const { data, error } = await supabase
          .from('consultations')
          .insert(payload)
          .select('*')
          .single();

        if (error) throw error;

        // Lab orders
        if (payload.lab_orders && payload.lab_orders !== 'None') {
          const tests = payload.lab_orders.split(',').map(t => t.trim()).filter(t => t && t !== 'None');
          if (tests.length > 0) {
            const orderRows = tests.map(test => ({
              consultation_id: data.id,
              patient_citizen_id: citizenId,
              doctor_staff_id: doctorStaffId,
              test_name: test,
              status: 'Pending'
            }));
            await supabase.from('lab_orders').insert(orderRows);
          }
        }

        showToast('Consultation saved successfully.', 'success');
        closeConsultationModal();
        await loadConsultationData();

        // Complete queue ticket if present, or search for any active queue ticket for this citizen today
        let qId = consultationForm.dataset.queueTicketId;
        if (!qId && citizenId) {
          try {
            const { data: activeTickets } = await supabase
              .from('queue_tickets')
              .select('id')
              .eq('citizen_id', citizenId)
              .in('status', ['serving', 'on_call', 'waiting'])
              .order('created_at', { ascending: false })
              .limit(1);
            if (activeTickets && activeTickets.length > 0) {
              qId = String(activeTickets[0].id);
            }
          } catch (qErr) {
            console.warn('Could not auto-resolve queue ticket for citizen:', qErr);
          }
        }

        if (qId) {
          await completeQueueTicket(qId);
        }

        // Seamlessly transition doctor to prescription modal
        await openPrescriptionModalForPatient(patientId, data.id, patientName, qId);
      } catch (err) {
        console.error('Failed to save consultation:', err);
        showToast(err.message || 'Unable to save consultation.', 'error');
      } finally {
        setLoading(submitBtn, false);
      }
    });
  }
}

