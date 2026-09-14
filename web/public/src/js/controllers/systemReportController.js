/**
 * UKonek System Report & Executive Intelligence Controller
 * Aggregates clinic operational census, service utilization, department load,
 * and generates formal DOH-aligned printable clinic reports.
 */

import { supabase } from '../lib/supabaseClient.js';
import { showToast, toggleChartSkeleton } from '../utils/uiHelpers.js';

let _systemTrendChart = null;
let _departmentLoadChart = null;
let _currentMetricsCache = null;

function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function getDateRange() {
  const startDate = document.getElementById('export-start-date')?.value || null;
  const endDate = document.getElementById('export-end-date')?.value || null;
  return { startDate, endDate };
}

/**
 * Load system report telemetry, update executive KPI cards, and render charts.
 */
export async function loadSystemReportData() {
  const { startDate, endDate } = getDateRange();
  console.log(`[SystemReport] Loading metrics for range: ${startDate || 'All Time'} to ${endDate || 'Present'}`);

  toggleChartSkeleton('system-trend-chart', true);
  toggleChartSkeleton('department-load-chart', true);

  try {
    // 1. Build queries with date filtering (using safe column selections)
    let consultQuery = supabase.from('consultations').select('id, consulted_at, diagnosis, created_at');
    if (startDate) consultQuery = consultQuery.gte('consulted_at', `${startDate}T00:00:00`);
    if (endDate) consultQuery = consultQuery.lte('consulted_at', `${endDate}T23:59:59`);

    let queueQuery = supabase.from('queue_tickets').select('id, queue_date, status, created_at');
    if (startDate) queueQuery = queueQuery.gte('queue_date', startDate);
    if (endDate) queueQuery = queueQuery.lte('queue_date', endDate);

    let vitalsQuery = supabase.from('vital_signs').select('id, created_at, temperature, blood_pressure');
    if (startDate) vitalsQuery = vitalsQuery.gte('created_at', `${startDate}T00:00:00`);
    if (endDate) vitalsQuery = vitalsQuery.lte('created_at', `${endDate}T23:59:59`);

    let rxQuery = supabase.from('prescription_headers').select('id, dispensing_status, issued_at');
    if (startDate) rxQuery = rxQuery.gte('issued_at', `${startDate}T00:00:00`);
    if (endDate) rxQuery = rxQuery.lte('issued_at', `${endDate}T23:59:59`);

    let labQuery = supabase.from('lab_orders').select('id, status, created_at');
    if (startDate) labQuery = labQuery.gte('created_at', `${startDate}T00:00:00`);
    if (endDate) labQuery = labQuery.lte('created_at', `${endDate}T23:59:59`);

    // Parallel fetch with RPC operational metrics fallback
    const [
      consultsRes,
      queueRes,
      vitalsRes,
      rxRes,
      labRes,
      citizensRes,
      staffRes,
      medsRes,
      opMetricsRes
    ] = await Promise.all([
      consultQuery.limit(500),
      queueQuery.limit(500),
      vitalsQuery.limit(500),
      rxQuery.limit(500),
      labQuery.limit(500),
      supabase.from('citizens').select('id, created_at', { count: 'exact' }),
      supabase.from('staff').select('id, username, role, status, is_online'),
      supabase.from('medicines').select('id, qty', { count: 'exact' }).is('archived_at', null),
      supabase.rpc('get_clinical_operations_metrics').catch(() => ({ data: null }))
    ]);

    if (consultsRes.error) console.warn('[SystemReport] Consultations fetch notice:', consultsRes.error.message);
    if (rxRes.error) console.warn('[SystemReport] Prescriptions fetch notice:', rxRes.error.message);

    let consults = consultsRes.data || [];
    const tickets = queueRes.data || [];
    const vitals = vitalsRes.data || [];
    const prescriptions = rxRes.data || [];
    const labOrders = labRes.data || [];
    const staffList = staffRes.data || [];
    const totalCitizens = citizensRes.count || (citizensRes.data || []).length || 0;
    const totalMedicines = medsRes.count || (medsRes.data || []).length || 0;

    const opMetrics = opMetricsRes?.data || null;

    // Derived Metrics
    const completedTickets = tickets.filter((t) => t.status === 'completed').length;
    const queueCompletionRate = tickets.length ? Math.round((completedTickets / tickets.length) * 100) : 100;

    const dispensedRx = prescriptions.filter((p) => (p.dispensing_status || p.status) === 'dispensed').length;
    const rxFulfillmentRate = prescriptions.length ? Math.round((dispensedRx / prescriptions.length) * 100) : (opMetrics?.dispenses_today ? 100 : 100);

    const completedLabs = labOrders.filter((l) => String(l.status || '').toLowerCase() === 'completed').length;
    const onlineStaff = staffList.filter((s) => s.is_online).length;

    // If direct select yielded 0 due to RLS but opMetrics indicates activity today without active date filter
    let displayConsultsCount = consults.length;
    if (displayConsultsCount === 0 && !startDate && !endDate && opMetrics?.consults_today) {
      displayConsultsCount = opMetrics.consults_today;
    }

    _currentMetricsCache = {
      startDate: startDate || 'All Time',
      endDate: endDate || 'Present',
      generatedAt: new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' }),
      consultationsCount: displayConsultsCount,
      queueTicketsCount: tickets.length,
      completedTickets,
      queueCompletionRate,
      vitalsCount: vitals.length || (opMetrics?.vitals_today || 0),
      prescriptionsCount: prescriptions.length,
      dispensedRx,
      rxFulfillmentRate,
      labOrdersCount: labOrders.length,
      completedLabs,
      totalCitizens,
      totalStaff: staffList.length,
      onlineStaff,
      totalMedicines,
      consults,
      tickets,
      vitals,
      prescriptions
    };

    // 2. Update KPI Card DOM elements using matching HTML element IDs
    updateKpiCard('sys-metric-consults', displayConsultsCount, `${displayConsultsCount} Clinical Encounters`);
    updateKpiCard('sys-metric-queue', tickets.length, `${queueCompletionRate}% Completion Rate`);
    updateKpiCard('sys-metric-rx', prescriptions.length || (opMetrics?.dispenses_today || 0), `${rxFulfillmentRate}% Dispensed`);
    updateKpiCard('sys-metric-lab', labOrders.length, `${completedLabs} Diagnostic Tests Done`);
    updateKpiCard('sys-metric-citizens', totalCitizens, 'Total Registered Patients');
    updateKpiCard('sys-metric-staff', onlineStaff, `${onlineStaff} of ${staffList.length} Staff Online`);

    // 3. Render Trend Chart (Last 7 days daily aggregate)
    renderSystemTrendChart(consults, vitals, tickets);

    // 4. Render Departmental Load Chart
    renderDepartmentLoadChart(vitals.length, displayConsultsCount, prescriptions.length, labOrders.length);

  } catch (err) {
    console.error('[SystemReport] Error compiling report metrics:', err);
    showToast('Failed to load full system report metrics.', 'error');
  } finally {
    toggleChartSkeleton('system-trend-chart', false);
    toggleChartSkeleton('department-load-chart', false);
  }
}

function updateKpiCard(metricId, mainVal, subVal) {
  const numEl = document.getElementById(metricId);
  const subEl = document.getElementById(`${metricId}-sub`);
  if (numEl) numEl.textContent = String(mainVal);
  if (subEl && subVal) subEl.textContent = String(subVal);
}

/**
 * Render multi-metric trend chart (Consultations, Triage, Queue Volume)
 */
function renderSystemTrendChart(consults, vitals, tickets) {
  if (typeof window.Chart === 'undefined') return;
  const canvas = document.getElementById('system-trend-chart');
  if (!canvas) return;

  if (_systemTrendChart) {
    _systemTrendChart.destroy();
    _systemTrendChart = null;
  }

  // Calculate past 7 days in Asia/Manila date string
  const last7Days = [...Array(7)].map((_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - (6 - i));
    return d.toISOString().split('T')[0];
  });

  const consultsMap = {};
  const vitalsMap = {};
  const ticketsMap = {};

  last7Days.forEach((d) => {
    consultsMap[d] = 0;
    vitalsMap[d] = 0;
    ticketsMap[d] = 0;
  });

  consults.forEach((c) => {
    const ts = c.consulted_at || c.created_at;
    if (ts) {
      const day = ts.split('T')[0];
      if (consultsMap.hasOwnProperty(day)) consultsMap[day]++;
    }
  });

  vitals.forEach((v) => {
    if (v.created_at) {
      const day = v.created_at.split('T')[0];
      if (vitalsMap.hasOwnProperty(day)) vitalsMap[day]++;
    }
  });

  tickets.forEach((t) => {
    const day = t.queue_date || (t.created_at ? t.created_at.split('T')[0] : null);
    if (day && ticketsMap.hasOwnProperty(day)) ticketsMap[day]++;
  });

  const labels = last7Days.map((d) => {
    const parts = d.split('-');
    return `${Number(parts[1])}/${Number(parts[2])}`;
  });

  _systemTrendChart = new window.Chart(canvas, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Consultations',
          data: last7Days.map((d) => consultsMap[d] || 0),
          borderColor: '#16a34a',
          backgroundColor: 'rgba(22, 163, 74, 0.08)',
          tension: 0.35,
          fill: true,
          pointRadius: 4,
          pointBackgroundColor: '#16a34a'
        },
        {
          label: 'Triage & Vitals',
          data: last7Days.map((d) => vitalsMap[d] || 0),
          borderColor: '#2563eb',
          backgroundColor: 'rgba(37, 99, 235, 0.04)',
          tension: 0.35,
          fill: true,
          pointRadius: 4,
          pointBackgroundColor: '#2563eb'
        },
        {
          label: 'Queue Tickets',
          data: last7Days.map((d) => ticketsMap[d] || 0),
          borderColor: '#f59e0b',
          backgroundColor: 'transparent',
          borderDash: [4, 4],
          tension: 0.35,
          pointRadius: 3,
          pointBackgroundColor: '#f59e0b'
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      resizeDelay: 200,
      animation: { duration: 300 },
      interaction: { mode: 'index', intersect: false },
      scales: {
        y: {
          beginAtZero: true,
          ticks: { stepSize: 1, precision: 0 }
        }
      },
      plugins: {
        legend: {
          position: 'bottom',
          labels: { boxWidth: 12, font: { size: 11 }, padding: 8 }
        }
      }
    }
  });
}

/**
 * Render Departmental Load Distribution Doughnut Chart
 */
function renderDepartmentLoadChart(vitalsCount, consultsCount, rxCount, labCount) {
  if (typeof window.Chart === 'undefined') return;
  const canvas = document.getElementById('department-load-chart');
  if (!canvas) return;

  if (_departmentLoadChart) {
    _departmentLoadChart.destroy();
    _departmentLoadChart = null;
  }

  const total = vitalsCount + consultsCount + rxCount + labCount;
  const labels = ['Triage & Assessment', 'General Consultations', 'Pharmacy Dispensing', 'Diagnostics & Lab'];
  const data = total > 0 ? [vitalsCount, consultsCount, rxCount, labCount] : [1, 1, 1, 1];
  const bgColors = total > 0
    ? ['#2563eb', '#16a34a', '#8b5cf6', '#f59e0b']
    : ['#e2e8f0', '#cbd5e1', '#e2e8f0', '#cbd5e1'];

  _departmentLoadChart = new window.Chart(canvas, {
    type: 'doughnut',
    data: {
      labels: total > 0 ? labels : ['No encounter data logged yet'],
      datasets: [{
        data,
        backgroundColor: bgColors,
        borderWidth: 2,
        borderColor: '#ffffff'
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      resizeDelay: 200,
      animation: { duration: 300 },
      plugins: {
        legend: {
          position: 'bottom',
          labels: { boxWidth: 12, font: { size: 11 }, padding: 8 }
        }
      }
    }
  });
}

/**
 * Open Official Clinic Census Modal ready for Print / PDF export
 */
export function openOfficialCensusModal() {
  if (!_currentMetricsCache) {
    showToast('Please wait while system metrics are being compiled...', 'info');
    loadSystemReportData().then(() => showCensusModalWithCache());
    return;
  }
  showCensusModalWithCache();
}

function showCensusModalWithCache() {
  const modal = document.getElementById('system-census-modal');
  if (!modal || !_currentMetricsCache) return;

  const m = _currentMetricsCache;

  // Aggregate top diagnoses
  const diagMap = {};
  m.consults.forEach((c) => {
    const diag = String(c.diagnosis || '').trim();
    if (diag && diag !== '—' && diag.toLowerCase() !== 'none') {
      diagMap[diag] = (diagMap[diag] || 0) + 1;
    }
  });
  const sortedDiags = Object.entries(diagMap).sort((a, b) => b[1] - a[1]).slice(0, 5);

  const diagRowsHtml = sortedDiags.length
    ? sortedDiags.map(([name, count]) => `<tr><td style="padding:6px 12px;">${escHtml(name)}</td><td style="text-align:right; padding:6px 12px; font-weight:700;">${count}</td></tr>`).join('')
    : '<tr><td colspan="2" style="text-align:center; padding:10px; color:#64748b;">No diagnoses recorded in this period.</td></tr>';

  const previewEl = document.getElementById('census-printable-sheet');
  if (previewEl) {
    previewEl.innerHTML = `
      <div class="official-census-sheet" style="font-family:'Inter', Arial, sans-serif; color:#0f172a; padding:16px;">
        <!-- Header -->
        <div style="text-align:center; border-bottom:2px solid #0f172a; padding-bottom:12px; margin-bottom:16px;">
          <div style="font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:0.05em; color:#475569;">Republic of the Philippines &bull; Municipal Health Services</div>
          <h2 style="margin:4px 0; font-size:20px; font-weight:800; color:#0f172a;">AFM ROQUERO MEDICAL CLINIC</h2>
          <div style="font-size:13px; font-weight:600; color:#166534;">UKONEK CLINICAL MANAGEMENT & HEALTH CENSUS REPORT</div>
          <div style="font-size:11.5px; color:#64748b; margin-top:4px;">Audit Period: <strong>${escHtml(m.startDate)}</strong> to <strong>${escHtml(m.endDate)}</strong> &bull; Generated: ${escHtml(m.generatedAt)}</div>
        </div>

        <!-- Metric Table -->
        <h4 style="font-size:13px; font-weight:700; text-transform:uppercase; color:#0f172a; margin:14px 0 6px; border-bottom:1px solid #cbd5e1; padding-bottom:4px;">I. Operational Volume & Service Utilization</h4>
        <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:14px;">
          <thead>
            <tr style="background:#f1f5f9; border-bottom:1.5px solid #cbd5e1;">
              <th style="text-align:left; padding:6px 10px;">Service Domain</th>
              <th style="text-align:center; padding:6px 10px;">Volume / Recorded</th>
              <th style="text-align:center; padding:6px 10px;">Completion / Fulfillment</th>
              <th style="text-align:left; padding:6px 10px;">Status Notes</th>
            </tr>
          </thead>
          <tbody>
            <tr style="border-bottom:1px solid #e2e8f0;">
              <td style="padding:6px 10px; font-weight:600;">Physician Consultations</td>
              <td style="text-align:center; padding:6px 10px; font-weight:700;">${m.consultationsCount}</td>
              <td style="text-align:center; padding:6px 10px;">100%</td>
              <td style="padding:6px 10px; color:#475569;">Completed medical reviews</td>
            </tr>
            <tr style="border-bottom:1px solid #e2e8f0;">
              <td style="padding:6px 10px; font-weight:600;">Patient Queue Tickets</td>
              <td style="text-align:center; padding:6px 10px; font-weight:700;">${m.queueTicketsCount}</td>
              <td style="text-align:center; padding:6px 10px;">${m.queueCompletionRate}%</td>
              <td style="padding:6px 10px; color:#475569;">${m.completedTickets} tickets fulfilled</td>
            </tr>
            <tr style="border-bottom:1px solid #e2e8f0;">
              <td style="padding:6px 10px; font-weight:600;">Nursing Triage & Vitals</td>
              <td style="text-align:center; padding:6px 10px; font-weight:700;">${m.vitalsCount}</td>
              <td style="text-align:center; padding:6px 10px;">—</td>
              <td style="padding:6px 10px; color:#475569;">Clinical triage intakes</td>
            </tr>
            <tr style="border-bottom:1px solid #e2e8f0;">
              <td style="padding:6px 10px; font-weight:600;">Prescription Medication Orders</td>
              <td style="text-align:center; padding:6px 10px; font-weight:700;">${m.prescriptionsCount}</td>
              <td style="text-align:center; padding:6px 10px;">${m.rxFulfillmentRate}%</td>
              <td style="padding:6px 10px; color:#475569;">${m.dispensedRx} dispensed at pharmacy</td>
            </tr>
            <tr style="border-bottom:1px solid #e2e8f0;">
              <td style="padding:6px 10px; font-weight:600;">Diagnostic Laboratory Tests</td>
              <td style="text-align:center; padding:6px 10px; font-weight:700;">${m.labOrdersCount}</td>
              <td style="text-align:center; padding:6px 10px;">—</td>
              <td style="padding:6px 10px; color:#475569;">${m.completedLabs} completed orders</td>
            </tr>
          </tbody>
        </table>

        <!-- Morbidity Breakdown -->
        <h4 style="font-size:13px; font-weight:700; text-transform:uppercase; color:#0f172a; margin:14px 0 6px; border-bottom:1px solid #cbd5e1; padding-bottom:4px;">II. Top Morbidity Causes (Diagnoses)</h4>
        <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:20px;">
          <thead>
            <tr style="background:#f1f5f9; border-bottom:1.5px solid #cbd5e1;">
              <th style="text-align:left; padding:6px 12px;">Clinical Diagnosis</th>
              <th style="text-align:right; padding:6px 12px;">Frequency</th>
            </tr>
          </thead>
          <tbody>
            ${diagRowsHtml}
          </tbody>
        </table>

        <!-- Signatures -->
        <div style="display:flex; justify-content:space-between; align-items:flex-end; margin-top:36px; padding-top:16px;">
          <div style="text-align:center; width:220px;">
            <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
            <div style="font-size:12px; font-weight:700;">Clinic Administrator / Nurse-on-Duty</div>
            <div style="font-size:10.5px; color:#64748b;">Prepared by</div>
          </div>
          <div style="text-align:center; width:220px;">
            <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
            <div style="font-size:12px; font-weight:700;">Medical Director / Physician</div>
            <div style="font-size:10.5px; color:#64748b;">Verified & Approved by</div>
          </div>
        </div>
      </div>
    `;
  }

  modal.classList.remove('hidden');
}

export function printOfficialCensusDocument() {
  window.print();
}

/**
 * Initialize event listeners for System Report components.
 */
export function initSystemReportController() {
  console.log('[SystemReport] Initializing System Report & Executive Intelligence Controller...');

  // Official census print buttons
  const printBtn = document.getElementById('btn-print-official-census');
  if (printBtn) {
    printBtn.addEventListener('click', (e) => {
      e.preventDefault();
      openOfficialCensusModal();
    });
  }

  const modalPrintBtn = document.getElementById('census-modal-print-btn');
  if (modalPrintBtn) {
    modalPrintBtn.addEventListener('click', (e) => {
      e.preventDefault();
      printOfficialCensusDocument();
    });
  }

  const modalCloseBtn = document.getElementById('census-modal-close-btn');
  const modal = document.getElementById('system-census-modal');
  if (modalCloseBtn && modal) {
    modalCloseBtn.addEventListener('click', () => modal.classList.add('hidden'));
  }
  if (modal) {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.add('hidden');
    });
  }

  // Date input change triggers reload
  const startInput = document.getElementById('export-start-date');
  const endInput = document.getElementById('export-end-date');
  if (startInput) startInput.addEventListener('change', () => loadSystemReportData());
  if (endInput) endInput.addEventListener('change', () => loadSystemReportData());

  // Date presets
  const presetChips = document.querySelectorAll('#export-presets .ph-filter-chip');
  presetChips.forEach((chip) => {
    chip.addEventListener('click', () => {
      setTimeout(() => loadSystemReportData(), 50);
    });
  });

  const clearBtn = document.getElementById('clear-date-range-btn');
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      setTimeout(() => loadSystemReportData(), 50);
    });
  }
}
