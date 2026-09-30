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
import { evaluateBp, evaluateHr, evaluateTemp, evaluateSpo2 } from './triageController.js';

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
    if (tbody) tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:24px; color:#94a3b8;">No consultations recorded.</td></tr>';
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
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:28px; color:#94a3b8;">No matching consultation records found.</td></tr>';
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

export let rawTriagedWaiting = [];
let triagedWaitingSearchQuery = '';

export async function loadTriagedWaitingPatients() {
  const tbody = document.getElementById('triaged-waiting-tbody');
  const countBadge = document.getElementById('triaged-waiting-count');
  if (!tbody) return;

  if (!rawTriagedWaiting || rawTriagedWaiting.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="10" style="text-align:center; padding:32px; color:#64748b;">
          <span class="loading-spinner" style="width:16px; height:16px; border:2px solid #cbd5e1; border-top-color:#0284c7; border-radius:50%; display:inline-block; animation:spin 0.8s linear infinite; vertical-align:middle; margin-right:8px;"></span>
          <span style="font-size:13px; font-weight:500;">Loading triaged patients awaiting consultation...</span>
        </td>
      </tr>
    `;
  }

  try {
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    const { data: vitals, error: vError } = await supabase
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
        notes,
        height_cm,
        weight_kg,
        bmi,
        queue_ticket_id,
        queue_tickets (
          id,
          ticket_code,
          status,
          queue_number,
          service_label,
          created_at,
          queue_date
        ),
        citizens (
          id,
          firstname,
          surname,
          middle_initial,
          age,
          sex,
          contact_number,
          complete_address,
          allergies
        )
      `)
      .gte('created_at', twentyFourHoursAgo)
      .order('created_at', { ascending: false })
      .limit(60);

    if (vError) throw vError;

    // Fetch consultations from the last 24h to exclude completed citizen consultations
    const { data: completedConsults } = await supabase
      .from('consultations')
      .select('patient_citizen_id, patient_identifier, created_at')
      .gte('created_at', twentyFourHoursAgo);

    const completedCitizenIds = new Set((completedConsults || []).map(c => c.patient_citizen_id).filter(Boolean));

    const seenCitizenIds = new Set();
    const seenTicketIds = new Set();

    const normalized = (vitals || []).map(v => {
      const citizen = v.citizens;
      const patientName = citizen
        ? `${citizen.firstname || ''} ${citizen.middle_initial ? citizen.middle_initial + '. ' : ''}${citizen.surname || ''}`.trim()
        : 'Walk-in Patient';

      const bp = evaluateBp(v.blood_pressure);
      const hr = evaluateHr(v.heart_rate);
      const temp = evaluateTemp(v.temperature);
      const spo2 = evaluateSpo2(v.oxygen_saturation);
      const isAlert = bp.level === 'alert' || hr.level === 'alert' || temp.level === 'alert' || spo2.level === 'alert';

      const ticket = v.queue_tickets;
      const queueStatus = ticket?.status || 'waiting';
      const ticketCode = ticket?.ticket_code || (v.queue_ticket_id ? `Q-${v.queue_ticket_id}` : 'Walk-in');

      return {
        ...v,
        _patientName: patientName,
        _ticketCode: ticketCode,
        _queueStatus: queueStatus,
        _isAlert: isAlert
      };
    });

    rawTriagedWaiting = normalized.filter(v => {
      // Exclude completed or cancelled queue tickets
      if (v._queueStatus === 'completed' || v._queueStatus === 'cancelled') {
        return false;
      }

      // Exclude citizens who already had their consultation completed today
      if (v.citizens?.id && completedCitizenIds.has(v.citizens.id)) {
        return false;
      }

      // Deduplicate: Keep only the most recent triage record per patient
      if (v.citizens?.id) {
        if (seenCitizenIds.has(v.citizens.id)) return false;
        seenCitizenIds.add(v.citizens.id);
      } else if (v.queue_ticket_id) {
        if (seenTicketIds.has(v.queue_ticket_id)) return false;
        seenTicketIds.add(v.queue_ticket_id);
      }

      // Active waiting triage status
      return v._queueStatus === 'waiting' || v._queueStatus === 'on_call' || v._queueStatus === 'serving';
    });

    renderTriagedWaitingTable();
  } catch (err) {
    console.warn('[Consultation] Error loading triaged waiting patients:', err);
    if (tbody) {
      tbody.innerHTML = `
        <tr>
          <td colspan="10" style="text-align:center; padding:28px 16px; color:#ef4444; font-size:13px;">
            Unable to load triaged patients queue. Please click "Refresh" to try again.
          </td>
        </tr>
      `;
    }
    if (countBadge) countBadge.textContent = '0';
  }
}

export function renderTriagedWaitingTable() {
  const tbody = document.getElementById('triaged-waiting-tbody');
  const countBadge = document.getElementById('triaged-waiting-count');
  if (!tbody) return;

  if (countBadge) {
    countBadge.textContent = rawTriagedWaiting.length;
  }

  const query = (triagedWaitingSearchQuery || '').toLowerCase().trim();
  const filtered = rawTriagedWaiting.filter(v => {
    if (!query) return true;
    const name = (v._patientName || '').toLowerCase();
    const complaint = (v.chief_complaint || '').toLowerCase();
    const code = (v._ticketCode || '').toLowerCase();
    const citizenId = v.citizens?.id ? `cit-${v.citizens.id}` : '';
    return name.includes(query) || complaint.includes(query) || code.includes(query) || citizenId.includes(query);
  });

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="10" style="text-align:center; padding:48px 16px; color:#64748b; font-size:13.5px;">
          <div style="display:flex; flex-direction:column; align-items:center; gap:10px;">
            <div style="width:48px; height:48px; border-radius:50%; background:#f1f5f9; display:flex; align-items:center; justify-content:center; color:#94a3b8;">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
                <circle cx="9" cy="7" r="4" />
                <polyline points="16 11 18 13 22 9" />
              </svg>
            </div>
            <div style="font-weight:700; color:#1e293b; font-size:15px;">
              ${query ? 'No matching triaged patients found' : 'No triaged patients awaiting consultation'}
            </div>
            <div style="font-size:13px; max-width:440px; color:#64748b; line-height:1.5;">
              ${query ? `No patients match the filter "${triagedWaitingSearchQuery}". Clear the search box to see all waiting patients.` : 'All triaged patients have been attended to or completed. New patients triaged by the nurse station will appear here immediately.'}
            </div>
          </div>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(v => {
    const createdDate = new Date(v.created_at);
    const timeFormatted = createdDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const diffMins = Math.max(0, Math.floor((Date.now() - createdDate.getTime()) / 60000));
    const waitTimeText = diffMins < 1 ? 'Just now' : `${diffMins}m wait`;

    const bp = evaluateBp(v.blood_pressure);
    const hr = evaluateHr(v.heart_rate);
    const temp = evaluateTemp(v.temperature);
    const spo2 = evaluateSpo2(v.oxygen_saturation);

    const citizen = v.citizens;
    const patientName = sanitizeText(v._patientName);
    const patientTag = citizen?.id ? `CIT-${citizen.id}` : 'Walk-in';
    const demoParts = [];
    if (citizen?.age) demoParts.push(`${citizen.age} yo`);
    if (citizen?.sex) demoParts.push(citizen.sex);
    if (citizen?.contact_number) demoParts.push(`📞 ${citizen.contact_number}`);
    const demoText = demoParts.join(' • ') || 'Walk-in Patient';

    const complaintSnippet = v.chief_complaint
      ? sanitizeText(v.chief_complaint)
      : 'Routine triage check';

    let severityHtml = '<span class="vitals-severity-badge severity-stable"><span style="width:6px; height:6px; border-radius:50%; background:#16a34a;"></span> Stable</span>';
    if (v._isAlert) {
      severityHtml = '<span class="vitals-severity-badge severity-alert"><span style="width:6px; height:6px; border-radius:50%; background:#e11d48;"></span> Attention</span>';
    }

    let queueStatusHtml = '<span class="vitals-queue-badge status-waiting">Waiting Consult</span>';
    if (v._queueStatus === 'serving' || v._queueStatus === 'on_call') {
      queueStatusHtml = '<span class="vitals-queue-badge status-serving">In Consult</span>';
    }

    const ticketCodeBadge = v._ticketCode
      ? `<div style="display:inline-block; font-size:10.5px; font-weight:700; color:#4338ca; background:#e0e7ff; padding:2px 7px; border-radius:5px; font-family:monospace; margin-bottom:3px;">${sanitizeText(v._ticketCode)}</div>`
      : '';

    return `
      <tr class="account-row triaged-waiting-row" data-vitals-id="${v.id}" title="Click row to inspect clinical telemetry" style="cursor:pointer;">
        <td style="white-space:nowrap; vertical-align:middle;">
          ${ticketCodeBadge}
          <div style="font-weight:700; font-size:12.5px; color:#1e293b;">${timeFormatted}</div>
          <span style="font-size:11px; color:#64748b; font-weight:600;">${waitTimeText}</span>
        </td>
        <td style="vertical-align:middle;">
          <div style="display:flex; align-items:center; gap:6px;">
            <strong style="font-size:13.5px; color:#0f172a;">${patientName}</strong>
            <span style="font-size:10px; font-weight:700; background:#f1f5f9; color:#475569; padding:1px 5px; border-radius:4px;">${patientTag}</span>
          </div>
          <div style="font-size:11.5px; color:#64748b; margin-top:2px;">
            ${sanitizeText(demoText)}
          </div>
        </td>
        <td style="vertical-align:middle;">
          <div style="font-size:12.5px; color:#334155; font-weight:500; max-width:240px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${complaintSnippet}">
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
        <td style="vertical-align:middle; text-align:center; white-space:nowrap;">
          <button type="button" class="chip-btn chip-btn-primary start-triaged-consult-btn" data-vitals-id="${v.id}" style="padding:6px 12px; font-size:11.5px; font-weight:700; border-radius:8px; gap:5px; height:auto; box-shadow:0 2px 4px rgba(2,132,199,0.2);">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
              <path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/>
              <path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/>
              <path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/>
              <path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/>
            </svg>
            Start Consult
          </button>
        </td>
      </tr>
    `;
  }).join('');

  tbody.querySelectorAll('.start-triaged-consult-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const vitalsId = Number(btn.getAttribute('data-vitals-id'));
      const record = rawTriagedWaiting.find(v => v.id === vitalsId);
      if (record) {
        startConsultationForTriagedPatient(record);
      }
    });
  });

  tbody.querySelectorAll('.triaged-waiting-row').forEach(tr => {
    const vitalsId = Number(tr.getAttribute('data-vitals-id'));
    const v = rawTriagedWaiting.find(r => r.id === vitalsId);
    if (!v) return;

    const timeFormatted = new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const dateFormatted = new Date(v.created_at).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });

    attachDetailRow(tr, () => ({
      tag: 'Triaged Patient Telemetry',
      title: v._patientName,
      subtitle: `Triaged on ${dateFormatted} at ${timeFormatted} • Status: Waiting Consult`,
      items: [
        { label: 'Triage Severity', value: v._isAlert ? 'Needs Attention (Elevated / Out of Range)' : 'Stable (Normal Hemodynamic Parameters)' },
        { label: 'Queue Status', value: v._queueStatus ? v._queueStatus.toUpperCase() : 'WAITING' },
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
        { label: 'Allergies', value: v.citizens?.allergies || 'None declared' },
        { label: 'Patient Age', value: v.citizens?.age ? `${v.citizens.age} years old` : '—' },
        { label: 'Contact Number', value: v.citizens?.contact_number || '—' }
      ]
    }));
  });
}

export async function startConsultationForTriagedPatient(v) {
  const user = sessionStore.getUser();
  if (String(user?.role || '').toLowerCase() !== 'doctor') {
    showToast('Only doctors can conduct consultations.', 'warning');
    return;
  }

  const citizen = v.citizens;
  const fullName = citizen
    ? `${citizen.firstname || ''} ${citizen.middle_initial ? citizen.middle_initial + '. ' : ''}${citizen.surname || ''}`.trim()
    : (v._patientName || 'Walk-in Patient');

  const ticket = v.queue_tickets;
  const ticketId = ticket?.id || v.queue_ticket_id || null;

  await openConsultationModal({
    patientId: citizen ? `CIT-${citizen.id}` : (ticket?.ticket_code || 'Walk-in Patient'),
    patientName: fullName,
    serviceLabel: ticket?.service_label || 'General Consultation',
    queueTicketId: ticketId,
    symptoms: v.chief_complaint || '',
    notes: v.current_medications ? `Current Meds: ${v.current_medications}` : ''
  });

  if (citizen?.id) {
    loadLatestVitalsForCitizen(citizen.id);
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

let activeConsultPatient = null;
let citizenSearchDebounceTimer = null;
let patientSelectorInitialized = false;

function updateLeftPaneDemographics(info = {}) {
  const card = document.getElementById('consult-patient-side-card');
  const avatar = document.getElementById('consult-side-avatar');
  const nameEl = document.getElementById('consult-side-name');
  const subEl = document.getElementById('consult-side-sub');
  const contactEl = document.getElementById('consult-side-contact');
  const addressEl = document.getElementById('consult-side-address');

  if (!card) return;

  const name = String(info.name || '').trim();
  if (!name) {
    card.style.display = 'none';
    return;
  }

  const nameParts = name.replace(/^(walk-in:\s*)/i, '').trim().split(/\s+/);
  const initials = (nameParts.length >= 2
    ? `${nameParts[0][0]}${nameParts[nameParts.length - 1][0]}`
    : `${nameParts[0]?.[0] || 'P'}${nameParts[0]?.[1] || 'T'}`
  ).toUpperCase();

  if (avatar) avatar.textContent = initials;
  if (nameEl) nameEl.textContent = name;

  const subParts = [];
  if (info.id) subParts.push(info.id);
  if (info.age) subParts.push(`${info.age} yo`);
  if (info.sex) subParts.push(info.sex);
  if (subEl) subEl.textContent = subParts.join(' • ') || '—';

  if (contactEl) contactEl.textContent = info.contact || 'None';
  if (addressEl) addressEl.textContent = info.address || 'None';

  card.style.display = 'block';
}

function clearLeftPaneDemographics() {
  const card = document.getElementById('consult-patient-side-card');
  if (card) card.style.display = 'none';
}

export async function loadLatestVitalsForCitizen(citizenId) {
  if (!citizenId) return;
  try {
    const { data, error } = await supabase
      .from('vital_signs')
      .select('id, queue_ticket_id, citizen_id, chief_complaint, blood_pressure, heart_rate, temperature, respiratory_rate, oxygen_saturation, current_medications, notes, height_cm, weight_kg, bmi, created_at')
      .eq('citizen_id', citizenId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error || !data) return;

    const banner = document.getElementById('consult-vitals-banner');
    const grid = document.getElementById('consult-vitals-grid');
    const complaintEl = document.getElementById('consult-vitals-complaint');
    const notesEl = document.getElementById('consult-vitals-notes');
    if (!banner || !grid) return;

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
        <div class="v-label">${sanitizeText(v.label)}</div>
        <div class="v-val">${sanitizeText(v.value)}</div>
      </div>
    `).join('');

    if (complaintEl) {
      complaintEl.innerHTML = data.chief_complaint
        ? `<strong>Chief Complaint:</strong> ${sanitizeText(data.chief_complaint)}`
        : '';
    }
    if (notesEl) {
      notesEl.innerHTML = data.notes
        ? `<strong>Nurse Notes:</strong> ${sanitizeText(data.notes)}`
        : '';
      if (data.current_medications) {
        notesEl.innerHTML += `<br><strong>Current Meds:</strong> ${sanitizeText(data.current_medications)}`;
      }
    }

    const hpiInput = document.getElementById('consult-hpi');
    if (hpiInput && (!hpiInput.value || hpiInput.value === 'None') && data.chief_complaint) {
      hpiInput.value = data.chief_complaint;
    }

    banner.style.display = 'block';
  } catch (err) {
    console.warn('Could not load vitals for citizen:', err);
  }
}

async function executeCitizenSearch(query) {
  const dropdown = document.getElementById('consult-citizen-dropdown');
  if (!dropdown) return;

  const trimmed = String(query || '').trim();
  if (trimmed.length < 1) {
    dropdown.innerHTML = '';
    dropdown.classList.add('hidden');
    return;
  }

  dropdown.innerHTML = '<div style="padding:12px; text-align:center; color:#64748b; font-size:12px;">Searching registered citizens...</div>';
  dropdown.classList.remove('hidden');

  try {
    const cleanNum = trimmed.replace(/[^0-9]/g, '');
    let filterOrs = [];
    if (cleanNum && cleanNum.length <= 10) {
      filterOrs.push(`id.eq.${cleanNum}`);
    }
    filterOrs.push(`firstname.ilike.%${trimmed}%`);
    filterOrs.push(`surname.ilike.%${trimmed}%`);
    filterOrs.push(`contact_number.ilike.%${trimmed}%`);

    const { data: citizens, error } = await supabase
      .from('citizens')
      .select('id, firstname, surname, middle_initial, age, sex, contact_number, complete_address, allergies, date_of_birth')
      .or(filterOrs.join(','))
      .order('surname', { ascending: true })
      .limit(8);

    if (error) throw error;

    if (!citizens || citizens.length === 0) {
      dropdown.innerHTML = `
        <div style="padding:16px; text-align:center; color:#64748b; font-size:12.5px; line-height:1.5;">
          <div style="font-weight:600; color:#334155; margin-bottom:4px;">No patient health record matching "<strong>${sanitizeText(trimmed)}</strong>"</div>
          <div style="font-size:11.5px; color:#94a3b8;">
            Unregistered walk-in patients must first complete <strong>Vitals & Triage Intake</strong> at the Nurse Station before consultation.
          </div>
        </div>
      `;
      return;
    }

    dropdown.innerHTML = citizens.map(c => {
      const fullName = `${c.firstname || ''} ${c.middle_initial ? c.middle_initial + '. ' : ''}${c.surname || ''}`.trim();
      const initials = `${(c.firstname || 'P')[0]}${(c.surname || 'T')[0]}`.toUpperCase();
      const isWalkin = c.email && c.email.includes('walkin_');
      const metaParts = [];
      if (c.age) metaParts.push(`${c.age} yo`);
      if (c.sex) metaParts.push(c.sex);
      if (c.contact_number) metaParts.push(`📞 ${c.contact_number}`);
      const metaLine = metaParts.join(' • ');
      const hasAllergy = c.allergies && c.allergies !== 'None' && c.allergies.trim().length > 0;

      return `
        <div class="citizen-dropdown-item" data-citizen-id="${c.id}">
          <div class="citizen-avatar">${sanitizeText(initials)}</div>
          <div class="citizen-info">
            <div class="citizen-name-line">
              <span>${sanitizeText(fullName)}</span>
              <span class="citizen-id-badge">${isWalkin ? 'Walk-in' : 'CIT-' + c.id}</span>
            </div>
            <div class="citizen-sub-line">${sanitizeText(metaLine)}</div>
            ${hasAllergy ? `<div style="font-size:11px; color:#dc2626; font-weight:600; margin-top:2px;">⚠️ Allergies: ${sanitizeText(c.allergies)}</div>` : ''}
          </div>
        </div>
      `;
    }).join('');

    dropdown.querySelectorAll('.citizen-dropdown-item').forEach(item => {
      item.addEventListener('click', () => {
        const id = Number(item.dataset.citizenId);
        const citizen = citizens.find(c => c.id === id);
        if (citizen) {
          bindCitizenToConsultation(citizen);
        }
      });
    });
  } catch (err) {
    console.error('Citizen search error:', err);
    dropdown.innerHTML = '<div style="padding:12px; text-align:center; color:#ef4444; font-size:12px;">Error searching patient records. Please try again.</div>';
  }
}

function bindCitizenToConsultation(citizen) {
  const form = document.getElementById('consultation-form');
  const patientInput = document.getElementById('consult-patient-id');
  const displayId = document.getElementById('consult-display-id');
  const dropdown = document.getElementById('consult-citizen-dropdown');
  const confirmedBanner = document.getElementById('consult-confirmed-patient-banner');
  const searchView = document.getElementById('consult-citizen-search-view');
  const changeBtn = document.getElementById('consult-confirmed-change-btn');

  if (dropdown) dropdown.classList.add('hidden');

  const fullName = `${citizen.firstname || ''} ${citizen.middle_initial ? citizen.middle_initial + '. ' : ''}${citizen.surname || ''}`.trim();
  const initials = `${(citizen.firstname || 'P')[0]}${(citizen.surname || 'T')[0]}`.toUpperCase();
  const isWalkin = citizen.email && citizen.email.includes('walkin_');

  activeConsultPatient = {
    mode: isWalkin ? 'walkin' : 'citizen',
    id: citizen.id,
    name: fullName,
    citizen: citizen
  };

  if (patientInput) patientInput.value = `CIT-${citizen.id}`;
  if (form) {
    form.dataset.patientName = fullName;
    form.dataset.patientCitizenId = String(citizen.id);
    form.dataset.patientMode = isWalkin ? 'walkin' : 'citizen';
  }

  if (displayId) {
    const servicePart = form?.dataset.serviceLabel ? ` &mdash; <em>${sanitizeText(form.dataset.serviceLabel)}</em>` : '';
    displayId.innerHTML = `<strong>${sanitizeText(fullName)}</strong> <span style="color:#cbd5e1">(${isWalkin ? 'Triaged Walk-in' : 'CIT-' + citizen.id})</span>${servicePart}`;
  }

  const confAvatar = document.getElementById('consult-confirmed-avatar');
  const confName = document.getElementById('consult-confirmed-name');
  const confTag = document.getElementById('consult-confirmed-tag');
  const confSource = document.getElementById('consult-confirmed-source');
  const confMeta = document.getElementById('consult-confirmed-meta');

  if (confAvatar) confAvatar.textContent = initials;
  if (confName) confName.textContent = fullName;
  if (confTag) confTag.textContent = isWalkin ? `Walk-in #${citizen.id}` : `CIT-${citizen.id}`;
  if (confSource) {
    confSource.textContent = isWalkin ? 'Triaged Patient' : 'Registered Citizen';
    confSource.className = isWalkin ? 'confirmed-source-tag' : 'confirmed-source-tag';
  }
  if (confMeta) {
    const metaParts = [];
    if (citizen.age) metaParts.push(`${citizen.age} yo`);
    if (citizen.sex) metaParts.push(citizen.sex);
    if (citizen.contact_number) metaParts.push(`📞 ${citizen.contact_number}`);
    if (citizen.complete_address) metaParts.push(citizen.complete_address);
    confMeta.textContent = metaParts.join(' • ') || 'No extra demographics recorded';
  }

  if (changeBtn) changeBtn.style.display = form?.dataset.queueTicketId ? 'none' : 'inline-block';
  if (confirmedBanner) confirmedBanner.classList.remove('hidden');
  if (searchView) searchView.classList.add('hidden');

  updateLeftPaneDemographics({
    name: fullName,
    id: isWalkin ? `Walk-in #${citizen.id}` : `CIT-${citizen.id}`,
    age: citizen.age,
    sex: citizen.sex,
    contact: citizen.contact_number,
    address: citizen.complete_address
  });

  const allergyBox = document.getElementById('consult-allergy-alert');
  const allergyText = document.getElementById('consult-allergy-text');
  const allergyInput = document.getElementById('consult-allergies');
  if (citizen.allergies && citizen.allergies !== 'None' && citizen.allergies.trim()) {
    if (allergyText) allergyText.textContent = citizen.allergies;
    if (allergyBox) allergyBox.classList.remove('hidden');
    if (allergyInput && (!allergyInput.value || allergyInput.value === 'None')) {
      allergyInput.value = citizen.allergies;
    }
  } else {
    if (allergyBox) allergyBox.classList.add('hidden');
  }

  if (!form?.dataset.queueTicketId) {
    loadLatestVitalsForCitizen(citizen.id);
  }
}

function resetPatientSelection() {
  activeConsultPatient = null;
  const form = document.getElementById('consultation-form');
  const patientInput = document.getElementById('consult-patient-id');
  const displayId = document.getElementById('consult-display-id');
  const confirmedBanner = document.getElementById('consult-confirmed-patient-banner');
  const searchView = document.getElementById('consult-citizen-search-view');
  const searchInput = document.getElementById('consult-citizen-search-input');
  const dropdown = document.getElementById('consult-citizen-dropdown');

  if (patientInput) patientInput.value = '';
  if (form) {
    form.dataset.patientName = '';
    form.dataset.patientCitizenId = '';
    form.dataset.patientMode = 'citizen';
  }
  if (displayId) displayId.innerHTML = '—';
  if (searchInput) searchInput.value = '';
  if (dropdown) {
    dropdown.innerHTML = '';
    dropdown.classList.add('hidden');
  }

  if (confirmedBanner) confirmedBanner.classList.add('hidden');
  if (searchView) searchView.classList.remove('hidden');

  clearLeftPaneDemographics();
  document.getElementById('consult-allergy-alert')?.classList.add('hidden');
  const vitalsBanner = document.getElementById('consult-vitals-banner');
  if (vitalsBanner) vitalsBanner.style.display = 'none';

  setTimeout(() => searchInput?.focus(), 120);
}

export function initConsultationPatientSelector() {
  if (patientSelectorInitialized) return;
  patientSelectorInitialized = true;

  const searchView = document.getElementById('consult-citizen-search-view');
  const searchInput = document.getElementById('consult-citizen-search-input');
  const dropdown = document.getElementById('consult-citizen-dropdown');
  const changeBtn = document.getElementById('consult-confirmed-change-btn');

  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      clearTimeout(citizenSearchDebounceTimer);
      const val = e.target.value;
      citizenSearchDebounceTimer = setTimeout(() => {
        executeCitizenSearch(val);
      }, 250);
    });

    searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && dropdown) {
        dropdown.classList.add('hidden');
      }
    });
  }

  document.addEventListener('click', (e) => {
    if (!dropdown || dropdown.classList.contains('hidden')) return;
    if (!dropdown.contains(e.target) && e.target !== searchInput) {
      dropdown.classList.add('hidden');
    }
  });

  if (changeBtn) {
    changeBtn.addEventListener('click', () => {
      resetPatientSelection();
    });
  }
}

export async function openConsultationModal(prefill = {}) {
  const consultationModal = document.getElementById('consultation-modal');
  const consultationForm = document.getElementById('consultation-form');
  if (!consultationModal) return;
  if (consultationForm) consultationForm.reset();

  initConsultationPatientSelector();

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

  // Store queue ticket id and service label on form for later use
  if (consultationForm) {
    consultationForm.dataset.queueTicketId = prefill.queueTicketId ? String(prefill.queueTicketId) : '';
    consultationForm.dataset.patientName = prefill.patientName || '';
    consultationForm.dataset.serviceLabel = prefill.serviceLabel || '';
  }

  // Handle Patient Binding (Prefilled Ticket vs Fresh Form)
  if (prefill.queueTicketId || prefill.patientId) {
    const rawPatientId = prefill.patientId || '';
    const citizenId = resolveCitizenId(rawPatientId);

    if (citizenId) {
      try {
        const { data: citizen } = await supabase
          .from('citizens')
          .select('id, firstname, surname, middle_initial, age, sex, contact_number, complete_address, allergies, date_of_birth')
          .eq('id', citizenId)
          .maybeSingle();

        if (citizen) {
          bindCitizenToConsultation(citizen);
        } else {
          updateLeftPaneDemographics({
            name: prefill.patientName || rawPatientId,
            id: rawPatientId,
            age: '',
            sex: ''
          });
        }
      } catch (cErr) {
        console.warn('Could not fetch citizen details for consultation prefill:', cErr);
      }
    } else {
      const pName = prefill.patientName || rawPatientId || 'Walk-in Patient';
      if (consultationForm) {
        consultationForm.dataset.patientName = pName;
        consultationForm.dataset.patientCitizenId = '';
        consultationForm.dataset.patientMode = 'walkin';
      }

      const confirmedBanner = document.getElementById('consult-confirmed-patient-banner');
      const confAvatar = document.getElementById('consult-confirmed-avatar');
      const confName = document.getElementById('consult-confirmed-name');
      const confTag = document.getElementById('consult-confirmed-tag');
      const confSource = document.getElementById('consult-confirmed-source');
      const confMeta = document.getElementById('consult-confirmed-meta');
      const changeBtn = document.getElementById('consult-confirmed-change-btn');
      const toggles = document.getElementById('consult-type-toggles');
      const searchView = document.getElementById('consult-citizen-search-view');
      const walkinView = document.getElementById('consult-walkin-view');

      if (confAvatar) confAvatar.textContent = (pName[0] || 'W').toUpperCase();
      if (confName) confName.textContent = pName;
      if (confTag) confTag.textContent = prefill.queueTicketId ? `Ticket #${prefill.queueTicketId}` : 'Walk-in';
      if (confSource) {
        confSource.textContent = 'Walk-in Queue';
        confSource.className = 'confirmed-source-tag';
      }
      if (confMeta) confMeta.textContent = prefill.serviceLabel || 'Walk-in Patient';
      if (changeBtn) changeBtn.style.display = 'none';

      if (confirmedBanner) confirmedBanner.classList.remove('hidden');
      if (toggles) toggles.style.display = 'none';
      if (searchView) searchView.classList.add('hidden');
      if (walkinView) walkinView.classList.add('hidden');

      updateLeftPaneDemographics({
        name: pName,
        id: prefill.queueTicketId ? `Ticket #${prefill.queueTicketId}` : 'Walk-in',
        age: '',
        sex: '',
        contact: 'Walk-in Patient',
        address: 'Walk-in'
      });
    }

    if (displayId) {
      const namePart = prefill.patientName ? `<strong>${sanitizeText(prefill.patientName)}</strong>` : '';
      const idPart = prefill.patientId ? `<span style="color:#cbd5e1">(${sanitizeText(String(prefill.patientId))})</span>` : '—';
      const servicePart = prefill.serviceLabel ? ` &mdash; <em>${sanitizeText(prefill.serviceLabel)}</em>` : '';
      displayId.innerHTML = `${namePart} ${idPart}${servicePart}`.trim();
    }
  } else {
    resetPatientSelection();
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
  const dropdown = document.getElementById('consult-citizen-dropdown');
  if (dropdown) dropdown.classList.add('hidden');
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
  initConsultationPatientSelector();
  loadConsultationData();
  loadTriagedWaitingPatients();
  initLabSection();

  if (typeof window !== 'undefined') {
    window.loadTriagedWaitingPatients = loadTriagedWaitingPatients;
  }

  // Wire search input for triaged waiting patients
  const searchInput = document.getElementById('triaged-waiting-search-input');
  if (searchInput && !searchInput.dataset.bound) {
    searchInput.dataset.bound = 'true';
    searchInput.addEventListener('input', (e) => {
      triagedWaitingSearchQuery = e.target.value;
      renderTriagedWaitingTable();
    });
  }

  // Wire refresh button for triaged waiting patients
  const refreshBtn = document.getElementById('refresh-triaged-waiting-btn');
  if (refreshBtn && !refreshBtn.dataset.bound) {
    refreshBtn.dataset.bound = 'true';
    refreshBtn.addEventListener('click', async (e) => {
      e.preventDefault();
      const orig = refreshBtn.innerHTML;
      refreshBtn.disabled = true;
      refreshBtn.innerHTML = `
        <span class="loading-spinner" style="width:12px; height:12px; border:2px solid #cbd5e1; border-top-color:#0284c7; border-radius:50%; display:inline-block; animation:spin 0.8s linear infinite;"></span>
        <span>Refreshing...</span>
      `;
      await loadTriagedWaitingPatients();
      refreshBtn.disabled = false;
      refreshBtn.innerHTML = orig;
      showToast('Triaged patients queue refreshed.', 'info');
    });
  }

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
      let patientId = document.getElementById('consult-patient-id')?.value || '';
      let patientName = consultationForm.dataset.patientName || '';
      const diagnosis = document.getElementById('consult-diagnosis')?.value || '';

      // Validate patient selection: consultations are strictly allowed only on triaged patients or existing clinic records
      let citizenId = resolveCitizenId(patientId) || resolveCitizenId(consultationForm.dataset.patientCitizenId);

      if (!citizenId) {
        showToast('Please search and select a triaged patient or existing clinic record. Un-triaged walk-in patients must first complete intake at the Nurse Triage Station.', 'warning');
        document.getElementById('consult-citizen-search-input')?.focus();
        return;
      }
      patientId = `CIT-${citizenId}`;

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

        const finalNotes = cleanNone(document.getElementById('consult-notes')?.value);

        const payload = {
          patient_identifier: String(patientId).trim(),
          patient_citizen_id: citizenId,
          doctor_staff_id: doctorStaffId,
          symptoms: cleanNone(document.getElementById('consult-hpi')?.value),
          diagnosis: String(diagnosis).trim(),
          notes: finalNotes,
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

        // Live update the triaged waiting list on doctor desk
        await loadTriagedWaitingPatients();

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

