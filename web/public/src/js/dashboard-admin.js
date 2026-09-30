/**
 * UKonek Standalone Administrator Console Controller
 * Orchestrates Executive Analytics, Users Management, Reports Exports,
 * Doctor Schedules, Announcements, System Backup & Restore, and Account Security.
 */

import { supabase } from './lib/supabaseClient.js';
import * as staffService from './services/staffService.js';
import * as scheduleService from './services/scheduleService.js';
import {
  exportPatientReport,
  exportConsultationReport,
  exportDoctorActivityReport,
  exportQueueReport,
  exportSystemUsageReport
} from './reports.js';
import { showToast } from './utils/uiHelpers.js';

// Polyfill loadSupabaseModule on window so reports.js has direct access
if (typeof window !== 'undefined') {
  window.supabase = supabase;
  window.loadSupabaseModule = async () => ({ supabase });
  window.showToast = showToast;
}

// ── Global State ─────────────────────────────────────────────────────────────
let currentUser = null;
let staffList = [];
let doctorList = [];
let scheduleList = [];
let announcementList = [];
let systemMetrics = null;

let trendsChartInstance = null;
let deptLoadChartInstance = null;

let activeStaffRoleFilter = 'all';
let staffSearchQuery = '';
let activeAnnouncementAudience = 'all';
let parsedBackupData = null;

// ── Authentication & Session Guard ───────────────────────────────────────────
async function ensureAdminSession() {
  try {
    const { data: authData, error: authError } = await supabase.auth.getUser();
    const user = authData?.user;

    if (authError || !user) {
      console.warn('[Admin] No active session found. Redirecting to login...');
      window.location.replace('./index.html');
      return null;
    }

    // Fetch staff record
    let staffRecord = null;
    const { data: staffData, error: staffErr } = await supabase
      .from('staff')
      .select('id, first_name, last_name, username, email, role, status, employee_id')
      .eq('auth_user_id', user.id)
      .maybeSingle();

    if (!staffErr && staffData) {
      staffRecord = staffData;
    } else {
      // Fallback check by email
      const { data: emailMatch } = await supabase
        .from('staff')
        .select('id, first_name, last_name, username, email, role, status, employee_id')
        .eq('email', user.email)
        .maybeSingle();
      if (emailMatch) staffRecord = emailMatch;
    }

    const role = String(staffRecord?.role || sessionStorage.getItem('ukonek_role') || '').trim().toLowerCase();

    // Verify Admin authorization
    if (role !== 'admin') {
      console.warn(`[Admin] Unauthorized access attempt by role '${role}'. Redirecting...`);
      if (role === 'pharmacist') {
        window.location.replace('./dashboard-pharmacist.html');
      } else if (role === 'doctor' || role === 'nurse') {
        window.location.replace('./dashboard.html');
      } else {
        window.location.replace('./index.html');
      }
      return null;
    }

    currentUser = {
      ...user,
      ...staffRecord,
      role: 'admin',
      displayName: [staffRecord?.first_name, staffRecord?.last_name].filter(Boolean).join(' ') || staffRecord?.username || 'Administrator'
    };

    updateHeaderProfile(currentUser);
    return currentUser;
  } catch (err) {
    console.error('[Admin] Session verification exception:', err);
    window.location.replace('./index.html');
    return null;
  }
}

function updateHeaderProfile(user) {
  const displayEl = document.getElementById('admin-user-display');
  const avatarEl = document.getElementById('admin-user-avatar');
  if (displayEl) displayEl.textContent = `${user.displayName} (Admin)`;
  if (avatarEl) {
    const initials = user.displayName.split(' ').map(n => n[0]).slice(0, 2).join('').toUpperCase() || 'A';
    avatarEl.textContent = initials;
  }
}

// ── Tab Navigation ───────────────────────────────────────────────────────────
function initNavigation() {
  const navTabs = document.querySelectorAll('#admin-main-nav .admin-nav-tab');
  const sections = document.querySelectorAll('.admin-view-section');

  navTabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const targetSectionId = tab.getAttribute('data-section');
      if (!targetSectionId) return;

      navTabs.forEach(t => t.classList.remove('is-active'));
      tab.classList.add('is-active');

      sections.forEach(sec => {
        if (sec.id === targetSectionId) {
          sec.classList.remove('hidden');
        } else {
          sec.classList.add('hidden');
        }
      });

      // Lazy load section data
      if (targetSectionId === 'section-analytics') {
        loadAnalyticsData();
      } else if (targetSectionId === 'section-users') {
        loadStaffUsers();
      } else if (targetSectionId === 'section-schedules') {
        loadDoctorSchedulesSection();
      } else if (targetSectionId === 'section-reports') {
        // Ready for reports export
      } else if (targetSectionId === 'section-announcements') {
        loadAnnouncementsSection();
      }
    });
  });

  const headerSecurityBtn = document.getElementById('btn-header-security');
  if (headerSecurityBtn) {
    headerSecurityBtn.addEventListener('click', () => {
      const secTab = document.querySelector('[data-section="section-security"]');
      if (secTab) secTab.click();
    });
  }

  const logoutBtn = document.getElementById('admin-logout-btn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', async () => {
      try {
        await supabase.auth.signOut();
        sessionStorage.clear();
        localStorage.removeItem('supabase.auth.token');
        showToast('Signed out successfully.', 'info');
        setTimeout(() => { window.location.href = './index.html'; }, 600);
      } catch (err) {
        window.location.href = './index.html';
      }
    });
  }
}

// ── Section 1: Dashboard & Analytics ─────────────────────────────────────────
async function loadAnalyticsData() {
  const timeFilter = document.getElementById('analytics-time-filter')?.value || '7';

  let startDate = null;
  const now = new Date();
  if (timeFilter === 'today') {
    startDate = now.toISOString().split('T')[0];
  } else if (timeFilter === '7') {
    const d = new Date(now.getTime() - 7 * 86400000);
    startDate = d.toISOString().split('T')[0];
  } else if (timeFilter === '30') {
    const d = new Date(now.getTime() - 30 * 86400000);
    startDate = d.toISOString().split('T')[0];
  }

  try {
    let consultQuery = supabase.from('consultations').select('id, consulted_at, created_at, diagnosis');
    if (startDate) consultQuery = consultQuery.gte('consulted_at', `${startDate}T00:00:00`);

    let queueQuery = supabase.from('queue_tickets').select('id, queue_date, status, created_at');
    if (startDate) queueQuery = queueQuery.gte('queue_date', startDate);

    let vitalsQuery = supabase.from('vital_signs').select('id, created_at');
    if (startDate) vitalsQuery = vitalsQuery.gte('created_at', `${startDate}T00:00:00`);

    let rxQuery = supabase.from('prescription_headers').select('id, issued_at');
    if (startDate) rxQuery = rxQuery.gte('issued_at', `${startDate}T00:00:00`);

    let labQuery = supabase.from('lab_orders').select('id, created_at');
    if (startDate) labQuery = labQuery.gte('created_at', `${startDate}T00:00:00`);

    const [
      citizensCountRes,
      consultRes,
      queueRes,
      vitalsRes,
      rxRes,
      labRes,
      staffRes
    ] = await Promise.all([
      supabase.from('citizens').select('*', { count: 'exact', head: true }),
      consultQuery.limit(2000),
      queueQuery.limit(2000),
      vitalsQuery.limit(2000),
      rxQuery.limit(2000),
      labQuery.limit(2000),
      supabase.from('staff').select('id, role, status, is_online')
    ]);

    const totalCitizens = citizensCountRes.count || 0;
    const consults = consultRes.data || [];
    const queueTickets = queueRes.data || [];
    const vitals = vitalsRes.data || [];
    const prescriptions = rxRes.data || [];
    const labOrders = labRes.data || [];
    const allStaff = staffRes.data || [];

    const activeStaffCount = allStaff.filter(s => (s.status || '').toLowerCase() === 'active').length;
    const onlineStaffCount = allStaff.filter(s => Boolean(s.is_online)).length;

    // Cache metrics for census reporting
    systemMetrics = {
      totalCitizens,
      consultationsCount: consults.length,
      queueTicketsCount: queueTickets.length,
      vitalsCount: vitals.length,
      prescriptionsCount: prescriptions.length,
      labOrdersCount: labOrders.length,
      consults,
      startDate: startDate || 'All Time',
      endDate: now.toISOString().split('T')[0],
      generatedAt: now.toLocaleString()
    };

    // Update KPI UI
    const kpiCitizens = document.getElementById('kpi-total-citizens');
    const kpiConsults = document.getElementById('kpi-total-consults');
    const kpiQueue = document.getElementById('kpi-total-queue');
    const kpiActiveStaff = document.getElementById('kpi-active-staff');
    const kpiOnlineStaff = document.getElementById('kpi-online-staff');

    if (kpiCitizens) kpiCitizens.textContent = totalCitizens.toLocaleString();
    if (kpiConsults) kpiConsults.textContent = consults.length.toLocaleString();
    if (kpiQueue) kpiQueue.textContent = queueTickets.length.toLocaleString();
    if (kpiActiveStaff) kpiActiveStaff.textContent = activeStaffCount.toLocaleString();
    if (kpiOnlineStaff) kpiOnlineStaff.textContent = onlineStaffCount.toLocaleString();

    // Render Charts
    renderTrendsChart(consults, vitals, queueTickets);
    renderDeptLoadChart(vitals.length, consults.length, prescriptions.length, labOrders.length);
  } catch (err) {
    console.error('[Admin] Error loading analytics data:', err);
    showToast('Failed to load operational analytics.', 'error');
  }
}

function renderTrendsChart(consults, vitals, tickets) {
  const canvas = document.getElementById('admin-trends-chart');
  if (!canvas || typeof window.Chart === 'undefined') return;

  const last7Days = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    last7Days.push(d.toISOString().split('T')[0]);
  }

  const consultsMap = {};
  const vitalsMap = {};
  const ticketsMap = {};

  last7Days.forEach(d => {
    consultsMap[d] = 0;
    vitalsMap[d] = 0;
    ticketsMap[d] = 0;
  });

  consults.forEach(c => {
    const date = (c.consulted_at || c.created_at || '').split('T')[0];
    if (consultsMap.hasOwnProperty(date)) consultsMap[date]++;
  });

  vitals.forEach(v => {
    const date = (v.created_at || '').split('T')[0];
    if (vitalsMap.hasOwnProperty(date)) vitalsMap[date]++;
  });

  tickets.forEach(t => {
    const date = t.queue_date || (t.created_at || '').split('T')[0];
    if (ticketsMap.hasOwnProperty(date)) ticketsMap[date]++;
  });

  const labels = last7Days.map(d => {
    const parts = d.split('-');
    return `${Number(parts[1])}/${Number(parts[2])}`;
  });

  if (trendsChartInstance) {
    trendsChartInstance.destroy();
    trendsChartInstance = null;
  }

  trendsChartInstance = new window.Chart(canvas, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Consultations',
          data: last7Days.map(d => consultsMap[d]),
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.08)',
          fill: true,
          tension: 0.35,
          pointRadius: 4,
          pointBackgroundColor: '#10b981'
        },
        {
          label: 'Vitals Triage',
          data: last7Days.map(d => vitalsMap[d]),
          borderColor: '#0284c7',
          backgroundColor: 'rgba(2, 132, 199, 0.04)',
          fill: true,
          tension: 0.35,
          pointRadius: 4,
          pointBackgroundColor: '#0284c7'
        },
        {
          label: 'Queue Tickets',
          data: last7Days.map(d => ticketsMap[d]),
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
      scales: {
        y: {
          beginAtZero: true,
          ticks: { precision: 0 }
        }
      },
      plugins: {
        legend: {
          position: 'bottom',
          labels: { boxWidth: 12, font: { size: 11 } }
        }
      }
    }
  });
}

function renderDeptLoadChart(vitalsCount, consultsCount, rxCount, labCount) {
  const canvas = document.getElementById('admin-dept-load-chart');
  if (!canvas || typeof window.Chart === 'undefined') return;

  const total = vitalsCount + consultsCount + rxCount + labCount;
  const data = total > 0 ? [vitalsCount, consultsCount, rxCount, labCount] : [1, 1, 1, 1];
  const bgColors = total > 0
    ? ['#0284c7', '#10b981', '#6366f1', '#f59e0b']
    : ['#e2e8f0', '#cbd5e1', '#e2e8f0', '#cbd5e1'];

  if (deptLoadChartInstance) {
    deptLoadChartInstance.destroy();
    deptLoadChartInstance = null;
  }

  deptLoadChartInstance = new window.Chart(canvas, {
    type: 'doughnut',
    data: {
      labels: total > 0
        ? ['Triage Vitals', 'Consultations', 'Pharmacy Dispensing', 'Diagnostic Labs']
        : ['No Encounter Data Recorded'],
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
      plugins: {
        legend: {
          position: 'bottom',
          labels: { boxWidth: 12, font: { size: 11 } }
        }
      }
    }
  });
}

// ── Section 2: Reports & CSV Exports ─────────────────────────────────────────
function initReportsExports() {
  const btnPatient = document.getElementById('btn-export-patient');
  const btnConsult = document.getElementById('btn-export-consultation');
  const btnDoctor = document.getElementById('btn-export-doctor-activity');
  const btnQueue = document.getElementById('btn-export-queue');
  const btnSystem = document.getElementById('btn-export-system-usage');
  const btnClear = document.getElementById('btn-clear-report-dates');
  const presetChips = document.querySelectorAll('#report-preset-chips .admin-filter-chip');

  const getReportDates = () => {
    const start = document.getElementById('report-start-date')?.value || null;
    const end = document.getElementById('report-end-date')?.value || null;
    return { start, end };
  };

  presetChips.forEach(chip => {
    chip.addEventListener('click', () => {
      presetChips.forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');

      const preset = chip.getAttribute('data-preset');
      const startInp = document.getElementById('report-start-date');
      const endInp = document.getElementById('report-end-date');
      const now = new Date();
      const todayStr = now.toISOString().split('T')[0];

      if (preset === 'today') {
        if (startInp) startInp.value = todayStr;
        if (endInp) endInp.value = todayStr;
      } else if (preset === '7d') {
        const d = new Date(now.getTime() - 7 * 86400000);
        if (startInp) startInp.value = d.toISOString().split('T')[0];
        if (endInp) endInp.value = todayStr;
      } else if (preset === '30d') {
        const d = new Date(now.getTime() - 30 * 86400000);
        if (startInp) startInp.value = d.toISOString().split('T')[0];
        if (endInp) endInp.value = todayStr;
      } else {
        if (startInp) startInp.value = '';
        if (endInp) endInp.value = '';
      }
    });
  });

  if (btnClear) {
    btnClear.addEventListener('click', () => {
      const startInp = document.getElementById('report-start-date');
      const endInp = document.getElementById('report-end-date');
      if (startInp) startInp.value = '';
      if (endInp) endInp.value = '';
      presetChips.forEach(c => c.classList.remove('is-active'));
      document.querySelector('#report-preset-chips [data-preset="all"]')?.classList.add('is-active');
    });
  }

  const handleExport = async (btn, exportFn, reportName) => {
    const { start, end } = getReportDates();
    const origHtml = btn.innerHTML;
    try {
      btn.disabled = true;
      btn.innerHTML = '<span>Exporting...</span>';
      showToast(`Compiling ${reportName}...`, 'info');
      const result = await exportFn(start, end);
      showToast(`${reportName} exported successfully (${result?.count || 0} rows).`, 'success');
    } catch (err) {
      console.error(`[Admin] Failed to export ${reportName}:`, err);
      showToast(`Export failed: ${err.message || err}`, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = origHtml;
    }
  };

  if (btnPatient) btnPatient.addEventListener('click', () => handleExport(btnPatient, exportPatientReport, 'Patient Report'));
  if (btnConsult) btnConsult.addEventListener('click', () => handleExport(btnConsult, exportConsultationReport, 'Consultation Report'));
  if (btnDoctor) btnDoctor.addEventListener('click', () => handleExport(btnDoctor, exportDoctorActivityReport, 'Doctor Activity Report'));
  if (btnQueue) btnQueue.addEventListener('click', () => handleExport(btnQueue, exportQueueReport, 'Queue Report'));
  if (btnSystem) btnSystem.addEventListener('click', () => handleExport(btnSystem, exportSystemUsageReport, 'System Usage Report'));

  // Official Clinic Census Modal & Print
  const openCensusBtn = document.getElementById('btn-open-census-modal');
  const printCensusBtn = document.getElementById('btn-print-census-sheet');
  const censusModal = document.getElementById('modal-census-sheet');

  if (openCensusBtn) {
    openCensusBtn.addEventListener('click', async () => {
      if (!systemMetrics) await loadAnalyticsData();
      renderCensusSheet();
      if (censusModal) censusModal.classList.remove('hidden');
    });
  }

  if (printCensusBtn) {
    printCensusBtn.addEventListener('click', () => {
      window.print();
    });
  }
}

function renderCensusSheet() {
  const sheet = document.getElementById('census-printable-sheet');
  if (!sheet || !systemMetrics) return;

  const m = systemMetrics;

  // Aggregate top diagnoses
  const diagMap = {};
  (m.consults || []).forEach(c => {
    const diag = String(c.diagnosis || '').trim();
    if (diag && diag !== '—' && diag.toLowerCase() !== 'none') {
      diagMap[diag] = (diagMap[diag] || 0) + 1;
    }
  });

  const sortedDiags = Object.entries(diagMap).sort((a, b) => b[1] - a[1]).slice(0, 5);
  const diagRowsHtml = sortedDiags.length
    ? sortedDiags.map(([name, count]) => `<tr><td style="padding:6px 12px; border-bottom:1px solid #e2e8f0;">${name}</td><td style="text-align:right; padding:6px 12px; font-weight:700; border-bottom:1px solid #e2e8f0;">${count}</td></tr>`).join('')
    : '<tr><td colspan="2" style="text-align:center; padding:10px; color:#64748b;">No diagnosis records logged in this period.</td></tr>';

  sheet.innerHTML = `
    <div style="font-family:'Inter', Arial, sans-serif; color:#0f172a; padding:24px;">
      <div style="text-align:center; border-bottom:2px solid #0f172a; padding-bottom:14px; margin-bottom:18px;">
        <div style="font-size:11.5px; font-weight:700; text-transform:uppercase; letter-spacing:0.05em; color:#475569;">Republic of the Philippines &bull; Municipal Health Services</div>
        <h2 style="margin:4px 0; font-size:20px; font-weight:800; color:#0f172a;">AFM ROQUERO MEDICAL CLINIC</h2>
        <div style="font-size:13px; font-weight:700; color:#0284c7;">UKONEK CLINICAL MANAGEMENT & HEALTH CENSUS REPORT</div>
        <div style="font-size:11.5px; color:#64748b; margin-top:4px;">Period: <strong>${m.startDate}</strong> to <strong>${m.endDate}</strong> &bull; Generated: ${m.generatedAt}</div>
      </div>

      <h4 style="font-size:13px; font-weight:700; text-transform:uppercase; color:#0f172a; margin:14px 0 6px;">I. Operational Volume & Service Utilization</h4>
      <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:18px;">
        <thead>
          <tr style="background:#f1f5f9; border-bottom:1.5px solid #cbd5e1;">
            <th style="text-align:left; padding:6px 10px;">Clinical Service Domain</th>
            <th style="text-align:center; padding:6px 10px;">Total Recorded</th>
            <th style="text-align:left; padding:6px 10px;">Operational Notes</th>
          </tr>
        </thead>
        <tbody>
          <tr><td style="padding:6px 10px; font-weight:600; border-bottom:1px solid #e2e8f0;">Physician Consultations</td><td style="text-align:center; padding:6px 10px; font-weight:700; border-bottom:1px solid #e2e8f0;">${m.consultationsCount}</td><td style="padding:6px 10px; color:#475569; border-bottom:1px solid #e2e8f0;">Completed medical chartings</td></tr>
          <tr><td style="padding:6px 10px; font-weight:600; border-bottom:1px solid #e2e8f0;">Patient Queue Encounters</td><td style="text-align:center; padding:6px 10px; font-weight:700; border-bottom:1px solid #e2e8f0;">${m.queueTicketsCount}</td><td style="padding:6px 10px; color:#475569; border-bottom:1px solid #e2e8f0;">Service tickets issued</td></tr>
          <tr><td style="padding:6px 10px; font-weight:600; border-bottom:1px solid #e2e8f0;">Nursing Triage & Vitals</td><td style="text-align:center; padding:6px 10px; font-weight:700; border-bottom:1px solid #e2e8f0;">${m.vitalsCount}</td><td style="padding:6px 10px; color:#475569; border-bottom:1px solid #e2e8f0;">Intake assessments completed</td></tr>
          <tr><td style="padding:6px 10px; font-weight:600; border-bottom:1px solid #e2e8f0;">Prescriptions Issued</td><td style="text-align:center; padding:6px 10px; font-weight:700; border-bottom:1px solid #e2e8f0;">${m.prescriptionsCount}</td><td style="padding:6px 10px; color:#475569; border-bottom:1px solid #e2e8f0;">Outpatient medical prescriptions</td></tr>
          <tr><td style="padding:6px 10px; font-weight:600; border-bottom:1px solid #e2e8f0;">Diagnostic Laboratory Tests</td><td style="text-align:center; padding:6px 10px; font-weight:700; border-bottom:1px solid #e2e8f0;">${m.labOrdersCount}</td><td style="padding:6px 10px; color:#475569; border-bottom:1px solid #e2e8f0;">Laboratory testing orders</td></tr>
        </tbody>
      </table>

      <h4 style="font-size:13px; font-weight:700; text-transform:uppercase; color:#0f172a; margin:14px 0 6px;">II. Top Morbidity Causes (Diagnoses)</h4>
      <table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:28px;">
        <thead>
          <tr style="background:#f1f5f9; border-bottom:1.5px solid #cbd5e1;">
            <th style="text-align:left; padding:6px 12px;">Clinical Diagnosis</th>
            <th style="text-align:right; padding:6px 12px;">Recorded Frequency</th>
          </tr>
        </thead>
        <tbody>
          ${diagRowsHtml}
        </tbody>
      </table>

      <div style="display:flex; justify-content:space-between; align-items:flex-end; margin-top:36px; padding-top:16px;">
        <div style="text-align:center; width:220px;">
          <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
          <div style="font-size:11.5px; font-weight:700;">Clinic Administrator</div>
          <div style="font-size:10.5px; color:#64748b;">Prepared by</div>
        </div>
        <div style="text-align:center; width:220px;">
          <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
          <div style="font-size:11.5px; font-weight:700;">Medical Director / Attending Physician</div>
          <div style="font-size:10.5px; color:#64748b;">Verified & Approved by</div>
        </div>
      </div>
    </div>
  `;
}

// ── Section 3: Users Management ──────────────────────────────────────────────
async function loadStaffUsers() {
  const tbody = document.getElementById('staff-tbody');
  if (tbody) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding:24px; color:#64748b;">Loading registered staff accounts...</td></tr>`;
  }

  try {
    const data = await staffService.listStaff();

    staffList = data || [];
    doctorList = staffList.filter(s => (s.role || '').toLowerCase() === 'doctor');

    // Update nav counter
    const navUsersCount = document.getElementById('nav-count-users');
    if (navUsersCount) navUsersCount.textContent = staffList.length;

    renderStaffTable();
  } catch (err) {
    console.error('[Admin] Error loading staff:', err);
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding:24px; color:#ef4444;">Failed to load staff accounts: ${err.message || err}</td></tr>`;
    }
  }
}

function renderStaffTable() {
  const tbody = document.getElementById('staff-tbody');
  if (!tbody) return;

  let filtered = staffList;

  // Filter by role chip
  if (activeStaffRoleFilter !== 'all') {
    filtered = filtered.filter(s => (s.role || '').toLowerCase() === activeStaffRoleFilter);
  }

  // Filter by search query
  if (staffSearchQuery) {
    const q = staffSearchQuery.toLowerCase();
    filtered = filtered.filter(s => {
      const name = `${s.first_name || ''} ${s.last_name || ''} ${s.username || ''} ${s.employee_id || ''}`.toLowerCase();
      return name.includes(q);
    });
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5" style="text-align:center; padding:36px; color:#64748b;">
          No staff accounts found matching your search criteria.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(staff => {
    const fullName = [staff.first_name, staff.last_name].filter(Boolean).join(' ') || staff.username || 'Staff';
    const initials = fullName.split(' ').map(n => n[0]).slice(0, 2).join('').toUpperCase() || 'S';
    const role = (staff.role || 'staff').toLowerCase();
    const isSelf = currentUser && (staff.id === currentUser.id || staff.auth_user_id === currentUser.id);
    const status = (staff.status || 'Active').toLowerCase() === 'active' ? 'Active' : 'Disabled';

    return `
      <tr data-staff-id="${staff.id}">
        <td class="col-left">
          <div class="admin-user-cell">
            <div class="user-initials">${initials}</div>
            <div>
              <div style="font-weight:700; color:#0f172a; font-size:13.5px;">
                ${fullName}
                ${isSelf ? '<span style="font-size:10.5px; background:#dcfce7; color:#15803d; padding:1px 6px; border-radius:9999px; margin-left:4px; font-weight:700;">You</span>' : ''}
              </div>
              <div style="font-size:11.5px; color:#64748b;">@${staff.username || '—'} &bull; ${staff.email || 'No email'}</div>
            </div>
          </div>
        </td>
        <td class="col-left"><span class="employee-badge-mono">${staff.employee_id || '—'}</span></td>
        <td class="col-center"><span class="badge-role ${role}">${role}</span></td>
        <td class="col-center"><span class="badge-status ${status.toLowerCase()}">${status}</span></td>
        <td class="col-right" style="padding-right: 22px;">
          <div class="admin-actions-cell">
            <button type="button" class="admin-btn admin-btn-outline admin-btn-sm btn-staff-toggle-status" data-id="${staff.id}" data-name="${fullName}" data-username="${staff.username || ''}" data-status="${status}" ${isSelf ? 'disabled title="Cannot disable your own account"' : ''}>
              ${status === 'Active' ? 'Disable' : 'Enable'}
            </button>
            <button type="button" class="admin-btn admin-btn-outline admin-btn-sm btn-staff-reset-pwd" data-id="${staff.id}" data-name="${fullName}">
              Reset Password
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join('');

  // Bind row actions
  tbody.querySelectorAll('.btn-staff-toggle-status').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const id = btn.getAttribute('data-id');
      const name = btn.getAttribute('data-name');
      const username = btn.getAttribute('data-username');
      const currentStatus = btn.getAttribute('data-status');
      const newStatus = currentStatus === 'Active' ? 'Disabled' : 'Active';

      openToggleStatusModal(id, name, username, currentStatus, newStatus);
    });
  });

  tbody.querySelectorAll('.btn-staff-reset-pwd').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const id = btn.getAttribute('data-id');
      const name = btn.getAttribute('data-name');
      openResetPasswordModal(id, name);
    });
  });
}

function openToggleStatusModal(staffId, staffName, username, currentStatus, newStatus) {
  const modal = document.getElementById('modal-toggle-status');
  if (!modal) return;

  const idInp = document.getElementById('toggle-status-staff-id');
  const actionInp = document.getElementById('toggle-status-target-action');
  const titleEl = document.getElementById('toggle-status-modal-title');
  const headingEl = document.getElementById('toggle-status-heading');
  const descEl = document.getElementById('toggle-status-desc');
  const warningBox = document.getElementById('toggle-status-warning-box');
  const iconWrap = document.getElementById('toggle-status-icon-wrap');
  const confirmBtn = document.getElementById('btn-confirm-toggle-status');
  const btnLabel = document.getElementById('btn-toggle-status-label');

  if (idInp) idInp.value = staffId;
  if (actionInp) actionInp.value = newStatus;

  const isDisabling = newStatus === 'Disabled';
  const userTag = username ? ` (@${username})` : '';

  if (isDisabling) {
    if (titleEl) titleEl.textContent = 'Disable Staff Account';
    if (headingEl) headingEl.textContent = 'Disable Staff Access?';
    if (descEl) descEl.innerHTML = `Are you sure you want to disable access for <strong>${staffName}</strong>${userTag}?`;

    if (iconWrap) {
      iconWrap.style.background = '#fee2e2';
      iconWrap.style.color = '#dc2626';
      iconWrap.innerHTML = `
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
          <circle cx="12" cy="12" r="10"/>
          <line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
        </svg>
      `;
    }

    if (warningBox) {
      warningBox.style.background = '#fef2f2';
      warningBox.style.border = '1px solid #fecaca';
      warningBox.style.color = '#991b1b';
      warningBox.innerHTML = `
        <div style="font-weight:700; margin-bottom:2px;">Operational Notice:</div>
        Disabling this account immediately revokes all authentication and access privileges. The user will be signed out and cannot access patient records or clinical modules until re-enabled by an administrator.
      `;
    }

    if (confirmBtn) {
      confirmBtn.className = 'admin-btn admin-btn-danger';
    }
    if (btnLabel) btnLabel.textContent = 'Confirm & Disable Account';
  } else {
    // Enabling
    if (titleEl) titleEl.textContent = 'Enable Staff Account';
    if (headingEl) headingEl.textContent = 'Restore Staff Access?';
    if (descEl) descEl.innerHTML = `Are you sure you want to restore full login and operational access for <strong>${staffName}</strong>${userTag}?`;

    if (iconWrap) {
      iconWrap.style.background = '#dcfce7';
      iconWrap.style.color = '#16a34a';
      iconWrap.innerHTML = `
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
          <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
          <circle cx="9" cy="7" r="4"/>
          <polyline points="16 11 18 13 22 9"/>
        </svg>
      `;
    }

    if (warningBox) {
      warningBox.style.background = '#ecfdf5';
      warningBox.style.border = '1px solid #a7f3d0';
      warningBox.style.color = '#065f46';
      warningBox.innerHTML = `
        <div style="font-weight:700; margin-bottom:2px;">Account Restoration:</div>
        This staff member will immediately be able to sign in with their existing credentials and perform clinical services according to their designated role.
      `;
    }

    if (confirmBtn) {
      confirmBtn.className = 'admin-btn admin-btn-emerald';
    }
    if (btnLabel) btnLabel.textContent = 'Confirm & Enable Account';
  }

  modal.classList.remove('hidden');
}

function initUsersManagementEvents() {
  const searchInput = document.getElementById('staff-search-input');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      staffSearchQuery = e.target.value.trim();
      renderStaffTable();
    });
  }

  const roleChips = document.querySelectorAll('#staff-role-chips .admin-filter-chip');
  roleChips.forEach(chip => {
    chip.addEventListener('click', () => {
      roleChips.forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      activeStaffRoleFilter = chip.getAttribute('data-role') || 'all';
      renderStaffTable();
    });
  });

  // Modal open: Create Staff
  const btnOpenCreate = document.getElementById('btn-open-create-staff-modal');
  const modalCreate = document.getElementById('modal-create-staff');
  if (btnOpenCreate && modalCreate) {
    btnOpenCreate.addEventListener('click', () => {
      document.getElementById('form-create-staff')?.reset();
      modalCreate.classList.remove('hidden');
    });
  }

  // Submit Create Staff
  const formCreateStaff = document.getElementById('form-create-staff');
  if (formCreateStaff) {
    formCreateStaff.addEventListener('submit', async (e) => {
      e.preventDefault();

      const firstName = document.getElementById('cs-first-name')?.value.trim();
      const lastName = document.getElementById('cs-last-name')?.value.trim();
      const username = document.getElementById('cs-username')?.value.trim();
      const email = document.getElementById('cs-email')?.value.trim();
      const role = document.getElementById('cs-role')?.value;
      const employeeId = document.getElementById('cs-employee-id')?.value.trim();
      const password = document.getElementById('cs-password')?.value;
      const confirmPwd = document.getElementById('cs-confirm-password')?.value;

      if (!firstName || !lastName || !username || !email || !role || !password) {
        showToast('Please fill in all required fields.', 'error');
        return;
      }

      if (password !== confirmPwd) {
        showToast('Passwords do not match.', 'error');
        return;
      }

      if (password.length < 8) {
        showToast('Password must be at least 8 characters long.', 'error');
        return;
      }

      const submitBtn = document.getElementById('btn-submit-create-staff');
      try {
        if (submitBtn) submitBtn.disabled = true;
        showToast('Creating staff account...', 'info');

        const { error } = await supabase.rpc('create_staff_account_admin', {
          p_first_name: firstName,
          p_middle_name: null,
          p_last_name: lastName,
          p_birthday: null,
          p_gender: null,
          p_username: username,
          p_email: email.toLowerCase(),
          p_role: role,
          p_password: password,
          p_consent_given: true,
          p_status: 'Active'
        });

        if (error) throw error;

        showToast(`Staff account for ${firstName} ${lastName} created successfully.`, 'success');
        modalCreate.classList.add('hidden');
        await loadStaffUsers();
      } catch (err) {
        console.error('[Admin] Error creating staff account:', err);
        showToast(`Failed to create staff account: ${err.message || err}`, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  // Reset Password Modal
  const formResetPwd = document.getElementById('form-reset-staff-password');
  const modalResetPwd = document.getElementById('modal-reset-staff-password');
  if (formResetPwd) {
    formResetPwd.addEventListener('submit', async (e) => {
      e.preventDefault();

      const staffId = document.getElementById('reset-target-staff-id')?.value;
      const newPassword = document.getElementById('reset-new-password')?.value;
      const confirmPassword = document.getElementById('reset-confirm-password')?.value;

      if (!newPassword || newPassword.length < 8) {
        showToast('Password must be at least 8 characters long.', 'error');
        return;
      }

      if (newPassword !== confirmPassword) {
        showToast('Passwords do not match.', 'error');
        return;
      }

      const submitBtn = document.getElementById('btn-submit-reset-password');
      try {
        if (submitBtn) submitBtn.disabled = true;
        showToast('Updating staff credentials...', 'info');

        await staffService.resetStaffPassword(staffId, newPassword);

        showToast('Staff password has been reset successfully.', 'success');
        if (modalResetPwd) modalResetPwd.classList.add('hidden');
      } catch (err) {
        console.error('[Admin] Password reset error:', err);
        showToast(`Failed to reset password: ${err.message || err}`, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  // Confirm Status Toggle (Enable/Disable) Modal Handler
  const confirmToggleBtn = document.getElementById('btn-confirm-toggle-status');
  const modalToggle = document.getElementById('modal-toggle-status');
  if (confirmToggleBtn) {
    confirmToggleBtn.addEventListener('click', async (e) => {
      e.preventDefault();
      const staffId = document.getElementById('toggle-status-staff-id')?.value;
      const targetStatus = document.getElementById('toggle-status-target-action')?.value;

      if (!staffId || !targetStatus) return;

      const origHtml = confirmToggleBtn.innerHTML;
      try {
        confirmToggleBtn.disabled = true;
        confirmToggleBtn.innerHTML = '<span>Updating...</span>';

        await staffService.toggleStaffStatus(staffId, targetStatus);

        const readableStatus = String(targetStatus).toLowerCase() === 'active' ? 'Active' : 'Disabled';
        const actionVerb = readableStatus === 'Disabled' ? 'disabled' : 'enabled';
        showToast(`Staff account has been successfully ${actionVerb}.`, 'success');
        if (modalToggle) modalToggle.classList.add('hidden');
        await loadStaffUsers();
      } catch (err) {
        console.error('[Admin] Error updating staff status:', err);
        showToast(`Failed to update status: ${err.message || err}`, 'error');
      } finally {
        confirmToggleBtn.disabled = false;
        confirmToggleBtn.innerHTML = origHtml;
      }
    });
  }
}

function openResetPasswordModal(staffId, staffName) {
  const modal = document.getElementById('modal-reset-staff-password');
  const idInp = document.getElementById('reset-target-staff-id');
  const nameEl = document.getElementById('reset-target-staff-name');
  const pwdInp = document.getElementById('reset-new-password');
  const confirmInp = document.getElementById('reset-confirm-password');

  if (idInp) idInp.value = staffId;
  if (nameEl) nameEl.textContent = staffName;
  if (pwdInp) pwdInp.value = '';
  if (confirmInp) confirmInp.value = '';

  if (modal) modal.classList.remove('hidden');
}

// ── Section 4: Doctor Schedules & Availability ───────────────────────────────
async function loadDoctorSchedulesSection() {
  const tbody = document.getElementById('schedules-tbody');
  const doctorSelectFilter = document.getElementById('schedule-doctor-filter');
  const modalDoctorSelect = document.getElementById('sched-doctor');

  if (tbody) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding:24px; color:#64748b;">Loading doctor availability rosters...</td></tr>`;
  }

  try {
    // 1. Populate doctor selectors
    if (doctorList.length === 0) {
      const { data: doctors } = await supabase.from('staff').select('id, first_name, last_name, doctor_specialization').eq('role', 'doctor');
      doctorList = doctors || [];
    }

    if (doctorSelectFilter) {
      const currentVal = doctorSelectFilter.value;
      doctorSelectFilter.innerHTML = '<option value="all">All Doctors</option>' +
        doctorList.map(d => `<option value="${d.id}">Dr. ${d.first_name} ${d.last_name}</option>`).join('');
      doctorSelectFilter.value = currentVal;
    }

    if (modalDoctorSelect) {
      modalDoctorSelect.innerHTML = '<option value="">Select Doctor...</option>' +
        doctorList.map(d => `<option value="${d.id}">Dr. ${d.first_name} ${d.last_name} (${d.doctor_specialization || 'General'})</option>`).join('');
    }

    // 2. Fetch schedules
    scheduleList = await scheduleService.listDoctorSchedules();
    renderSchedulesTable();
  } catch (err) {
    console.error('[Admin] Error loading doctor schedules:', err);
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding:24px; color:#ef4444;">Failed to load schedules: ${err.message || err}</td></tr>`;
    }
  }
}

function renderSchedulesTable() {
  const tbody = document.getElementById('schedules-tbody');
  const filterDoctorId = document.getElementById('schedule-doctor-filter')?.value || 'all';

  if (!tbody) return;

  let filtered = scheduleList;
  if (filterDoctorId !== 'all') {
    filtered = filtered.filter(s => String(s.doctor_staff_id) === String(filterDoctorId));
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:36px; color:#64748b;">
          No doctor shift schedules found. Click "+ Add Doctor Shift Slot" above to schedule a duty slot.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(sched => {
    const docName = sched.doctor ? `Dr. ${sched.doctor.first_name} ${sched.doctor.last_name}` : `Doctor #${sched.doctor_staff_id}`;
    const spec = sched.doctor?.doctor_specialization || 'General Medicine';
    const dateFormatted = sched.schedule_date ? new Date(sched.schedule_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
    const timeFormatted = `${sched.start_time || '—'} - ${sched.end_time || '—'}`;

    return `
      <tr>
        <td class="col-left"><strong>${docName}</strong></td>
        <td class="col-left"><span style="font-size:12px; color:#475569;">${spec}</span></td>
        <td class="col-center"><span style="font-weight:600; color:#334155;">${dateFormatted}</span></td>
        <td class="col-center"><span style="font-weight:700; color:#0284c7; background:#e0f2fe; padding:3px 8px; border-radius:6px; font-size:12px;">${timeFormatted}</span></td>
        <td class="col-left"><span style="font-size:12px; color:#64748b;">${sched.notes || '—'}</span></td>
        <td class="col-right" style="padding-right: 20px;">
          <button type="button" class="admin-btn admin-btn-danger admin-btn-sm btn-delete-schedule" data-id="${sched.id}">
            Remove
          </button>
        </td>
      </tr>
    `;
  }).join('');

  tbody.querySelectorAll('.btn-delete-schedule').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.preventDefault();
      const id = btn.getAttribute('data-id');
      if (!confirm('Are you sure you want to remove this doctor duty shift?')) return;

      try {
        btn.disabled = true;
        await scheduleService.deleteDoctorSchedule(id);
        showToast('Doctor shift schedule deleted.', 'info');
        await loadDoctorSchedulesSection();
      } catch (err) {
        console.error('[Admin] Error deleting schedule:', err);
        showToast(`Failed to delete schedule: ${err.message || err}`, 'error');
      }
    });
  });
}

function initScheduleEvents() {
  const doctorFilter = document.getElementById('schedule-doctor-filter');
  if (doctorFilter) {
    doctorFilter.addEventListener('change', () => renderSchedulesTable());
  }

  const btnOpenAdd = document.getElementById('btn-open-add-schedule-modal');
  const modalSched = document.getElementById('modal-schedule-editor');
  if (btnOpenAdd && modalSched) {
    btnOpenAdd.addEventListener('click', () => {
      document.getElementById('form-schedule-editor')?.reset();
      document.getElementById('sched-id').value = '';
      document.getElementById('sched-date').value = new Date().toISOString().split('T')[0];
      modalSched.classList.remove('hidden');
    });
  }

  const formSched = document.getElementById('form-schedule-editor');
  if (formSched) {
    formSched.addEventListener('submit', async (e) => {
      e.preventDefault();

      const doctorId = document.getElementById('sched-doctor')?.value;
      const date = document.getElementById('sched-date')?.value;
      const startTime = document.getElementById('sched-start-time')?.value;
      const endTime = document.getElementById('sched-end-time')?.value;
      const notes = document.getElementById('sched-notes')?.value.trim();

      if (!doctorId || !date || !startTime || !endTime) {
        showToast('Please fill in all required shift fields.', 'error');
        return;
      }

      const submitBtn = document.getElementById('btn-submit-schedule');
      try {
        if (submitBtn) submitBtn.disabled = true;

        await scheduleService.saveDoctorSchedule({
          doctor_staff_id: Number(doctorId),
          schedule_date: date,
          start_time: startTime.length === 5 ? `${startTime}:00` : startTime,
          end_time: endTime.length === 5 ? `${endTime}:00` : endTime,
          notes: notes || null,
          created_by_staff_id: currentUser?.id || null
        });

        showToast('Doctor schedule slot saved successfully.', 'success');
        modalSched.classList.add('hidden');
        await loadDoctorSchedulesSection();
      } catch (err) {
        console.error('[Admin] Save schedule error:', err);
        showToast(`Failed to save schedule: ${err.message || err}`, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }
}

// ── Section 5: Announcements & Broadcasts ────────────────────────────────────
async function loadAnnouncementsSection() {
  const tbody = document.getElementById('announcements-tbody');
  if (tbody) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding:24px; color:#64748b;">Loading broadcasts & notices...</td></tr>`;
  }

  try {
    const { data, error } = await supabase
      .from('announcements')
      .select('*, staff:created_by_staff_id(id, first_name, last_name, role)')
      .order('created_at', { ascending: false });

    if (error) throw error;

    announcementList = data || [];
    renderAnnouncementsTable();
  } catch (err) {
    console.error('[Admin] Error loading announcements:', err);
    if (tbody) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding:24px; color:#ef4444;">Failed to load announcements: ${err.message || err}</td></tr>`;
    }
  }
}

function renderAnnouncementsTable() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;

  let filtered = announcementList;
  if (activeAnnouncementAudience !== 'all') {
    filtered = filtered.filter(a => (a.visibility || '').toLowerCase() === activeAnnouncementAudience);
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:36px; color:#64748b;">
          No announcements found for selected target audience. Click "+ Create Announcement" above to publish one.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(ann => {
    const author = ann.staff ? [ann.staff.first_name, ann.staff.last_name].filter(Boolean).join(' ') : 'Admin';
    const dateFormatted = ann.created_at ? new Date(ann.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
    const imgHtml = ann.image_url
      ? `<img src="${ann.image_url}" alt="poster" style="width:40px; height:40px; object-fit:cover; border-radius:6px; border:1px solid #e2e8f0; display:block; margin:0 auto; cursor:pointer;" onclick="window.open('${ann.image_url}', '_blank')" />`
      : `<div style="width:36px; height:36px; border-radius:6px; background:#f1f5f9; display:flex; align-items:center; justify-content:center; margin:0 auto; color:#94a3b8;"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg></div>`;

    const visLabel = (ann.visibility || 'all').toLowerCase();
    const visBadgeClass = visLabel === 'all' ? 'admin' : (visLabel === 'doctor' ? 'doctor' : (visLabel === 'nurse' ? 'nurse' : 'pharmacist'));

    return `
      <tr>
        <td class="col-center">${imgHtml}</td>
        <td class="col-left">
          <div style="font-weight:700; color:#0f172a; font-size:13.5px; margin-bottom:2px;">${ann.title}</div>
          <div style="font-size:12px; color:#64748b; line-height:1.35; max-width:440px;">${ann.content || ''}</div>
        </td>
        <td class="col-center"><span class="badge-role ${visBadgeClass}">${visLabel}</span></td>
        <td class="col-left"><span style="font-size:12.5px; font-weight:600; color:#334155;">${author}</span></td>
        <td class="col-center"><span style="font-size:12px; color:#64748b;">${dateFormatted}</span></td>
        <td class="col-right" style="padding-right: 20px;">
          <button type="button" class="admin-btn admin-btn-danger admin-btn-sm btn-delete-announcement" data-id="${ann.id}">
            Delete
          </button>
        </td>
      </tr>
    `;
  }).join('');

  tbody.querySelectorAll('.btn-delete-announcement').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.preventDefault();
      const id = btn.getAttribute('data-id');
      if (!confirm('Are you sure you want to delete this announcement? It will be removed from all recipient feeds.')) return;

      try {
        btn.disabled = true;
        const { error } = await supabase.from('announcements').delete().eq('id', id);
        if (error) throw error;
        showToast('Announcement deleted successfully.', 'info');
        await loadAnnouncementsSection();
      } catch (err) {
        console.error('[Admin] Error deleting announcement:', err);
        showToast(`Failed to delete announcement: ${err.message || err}`, 'error');
      }
    });
  });
}

function initAnnouncementsEvents() {
  const audienceChips = document.querySelectorAll('#announcement-audience-chips .admin-filter-chip');
  audienceChips.forEach(chip => {
    chip.addEventListener('click', () => {
      audienceChips.forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      activeAnnouncementAudience = chip.getAttribute('data-audience') || 'all';
      renderAnnouncementsTable();
    });
  });

  const btnOpenCreate = document.getElementById('btn-open-create-announcement-modal');
  const modalAnn = document.getElementById('modal-announcement-editor');
  if (btnOpenCreate && modalAnn) {
    btnOpenCreate.addEventListener('click', () => {
      document.getElementById('form-announcement-editor')?.reset();
      modalAnn.classList.remove('hidden');
    });
  }

  const formAnn = document.getElementById('form-announcement-editor');
  if (formAnn) {
    formAnn.addEventListener('submit', async (e) => {
      e.preventDefault();

      const title = document.getElementById('ann-title')?.value.trim();
      const visibility = document.getElementById('ann-visibility')?.value;
      const content = document.getElementById('ann-content')?.value.trim();
      const imageUrl = document.getElementById('ann-image-url')?.value.trim();

      if (!title || !visibility || !content) {
        showToast('Please provide a title, target audience, and content.', 'error');
        return;
      }

      const submitBtn = document.getElementById('btn-submit-announcement');
      try {
        if (submitBtn) submitBtn.disabled = true;

        const { error } = await supabase.from('announcements').insert({
          title,
          content,
          visibility,
          image_url: imageUrl || null,
          created_by_staff_id: currentUser?.id || null
        });

        if (error) throw error;

        showToast('Announcement broadcasted successfully.', 'success');
        modalAnn.classList.add('hidden');
        await loadAnnouncementsSection();
      } catch (err) {
        console.error('[Admin] Publish announcement error:', err);
        showToast(`Failed to publish announcement: ${err.message || err}`, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }
}

// ── Section 6: Backup & Disaster Recovery ────────────────────────────────────
function initBackupRestore() {
  const btnBackup = document.getElementById('btn-generate-backup');
  const fileInput = document.getElementById('backup-file-input');
  const dropzone = document.getElementById('backup-dropzone');
  const previewBox = document.getElementById('restore-preview-box');
  const summaryText = document.getElementById('restore-summary-text');
  const btnExecute = document.getElementById('btn-execute-restore');
  const progressWrap = document.getElementById('restore-progress-wrap');
  const progressBar = document.getElementById('restore-progress-bar');
  const statusMsg = document.getElementById('restore-status-message');

  // Generate Backup Snapshot
  if (btnBackup) {
    btnBackup.addEventListener('click', async () => {
      const origHtml = btnBackup.innerHTML;
      try {
        btnBackup.disabled = true;
        btnBackup.innerHTML = '<span>Compiling System Snapshot...</span>';
        showToast('Gathering clinic datasets for full backup...', 'info');

        const [
          citizens,
          staff,
          doctorSchedules,
          announcements,
          consultations,
          vitalSigns,
          prescriptionHeaders,
          prescriptionItems,
          labOrders,
          medicines,
          queueTickets,
          feedbacks
        ] = await Promise.all([
          supabase.from('citizens').select('*').limit(10000),
          supabase.from('staff').select('*').limit(1000),
          supabase.from('doctor_schedules').select('*').limit(5000),
          supabase.from('announcements').select('*').limit(2000),
          supabase.from('consultations').select('*').limit(10000),
          supabase.from('vital_signs').select('*').limit(10000),
          supabase.from('prescription_headers').select('*').limit(10000),
          supabase.from('prescription_items').select('*').limit(20000),
          supabase.from('lab_orders').select('*').limit(5000),
          supabase.from('medicines').select('*').limit(5000),
          supabase.from('queue_tickets').select('*').limit(10000),
          supabase.from('feedbacks').select('*').limit(2000)
        ]);

        const backupData = {
          metadata: {
            system: 'U-Konek Medical Clinic Management System',
            version: '2.0-Production',
            exportDate: new Date().toISOString(),
            exportedBy: currentUser?.email || 'admin'
          },
          counts: {
            citizens: (citizens.data || []).length,
            staff: (staff.data || []).length,
            doctor_schedules: (doctorSchedules.data || []).length,
            announcements: (announcements.data || []).length,
            consultations: (consultations.data || []).length,
            vital_signs: (vitalSigns.data || []).length,
            prescription_headers: (prescriptionHeaders.data || []).length,
            prescription_items: (prescriptionItems.data || []).length,
            lab_orders: (labOrders.data || []).length,
            medicines: (medicines.data || []).length,
            queue_tickets: (queueTickets.data || []).length,
            feedbacks: (feedbacks.data || []).length
          },
          tables: {
            citizens: citizens.data || [],
            staff: staff.data || [],
            doctor_schedules: doctorSchedules.data || [],
            announcements: announcements.data || [],
            consultations: consultations.data || [],
            vital_signs: vitalSigns.data || [],
            prescription_headers: prescriptionHeaders.data || [],
            prescription_items: prescriptionItems.data || [],
            lab_orders: labOrders.data || [],
            medicines: medicines.data || [],
            queue_tickets: queueTickets.data || [],
            feedbacks: feedbacks.data || []
          }
        };

        const totalRecords = Object.values(backupData.counts).reduce((a, b) => a + b, 0);
        const jsonStr = JSON.stringify(backupData, null, 2);
        const blob = new Blob([jsonStr], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        const filename = `UKonek_System_Backup_${new Date().toISOString().split('T')[0]}_${Date.now()}.json`;

        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        showToast(`Backup snapshot downloaded (${totalRecords} records across 12 tables).`, 'success');
      } catch (err) {
        console.error('[Admin] Backup snapshot error:', err);
        showToast(`Backup failed: ${err.message || err}`, 'error');
      } finally {
        btnBackup.disabled = false;
        btnBackup.innerHTML = origHtml;
      }
    });
  }

  // File Upload Dropzone
  if (dropzone && fileInput) {
    dropzone.addEventListener('click', () => fileInput.click());
    dropzone.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropzone.style.borderColor = '#0284c7';
    });
    dropzone.addEventListener('dragleave', () => {
      dropzone.style.borderColor = '#cbd5e1';
    });
    dropzone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropzone.style.borderColor = '#cbd5e1';
      const file = e.dataTransfer.files[0];
      if (file) handleBackupFile(file);
    });
    fileInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file) handleBackupFile(file);
    });
  }

  const handleBackupFile = (file) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const json = JSON.parse(e.target.result);
        if (!json.tables || typeof json.tables !== 'object') {
          throw new Error('Invalid U-Konek backup format. Missing tables object.');
        }

        parsedBackupData = json;
        const counts = json.counts || {};
        const summaryStr = Object.entries(counts)
          .map(([k, v]) => `${v} ${k.replace('_', ' ')}`)
          .join(', ');

        if (summaryText) summaryText.textContent = `Valid Snapshot: ${summaryStr || 'Datasets parsed successfully.'}`;
        if (previewBox) previewBox.classList.remove('hidden');
        if (btnExecute) btnExecute.disabled = false;

        showToast('Backup snapshot verified and ready for restore.', 'success');
      } catch (err) {
        console.error('[Admin] Backup file parse error:', err);
        showToast(`Invalid backup file: ${err.message || err}`, 'error');
      }
    };
    reader.readAsText(file);
  };

  // Execute Restore
  if (btnExecute) {
    btnExecute.addEventListener('click', async () => {
      if (!parsedBackupData || !parsedBackupData.tables) return;

      if (!confirm('CAUTION: System restoration will synchronize current tables with the backup dataset. Proceed with data restoration?')) {
        return;
      }

      try {
        btnExecute.disabled = true;
        if (progressWrap) progressWrap.classList.remove('hidden');

        const tables = Object.keys(parsedBackupData.tables);
        const total = tables.length;
        let completed = 0;

        for (const tbl of tables) {
          const rows = parsedBackupData.tables[tbl];
          if (statusMsg) statusMsg.textContent = `Restoring ${tbl} (${rows.length} records)...`;

          if (Array.isArray(rows) && rows.length > 0) {
            // Upsert in batches of 50
            const batchSize = 50;
            for (let i = 0; i < rows.length; i += batchSize) {
              const chunk = rows.slice(i, i + batchSize);
              await supabase.from(tbl).upsert(chunk, { onConflict: 'id', ignoreDuplicates: true });
            }
          }

          completed++;
          if (progressBar) progressBar.style.width = `${Math.round((completed / total) * 100)}%`;
        }

        if (statusMsg) statusMsg.textContent = 'Data restoration completed successfully!';
        showToast('System data restoration completed. Tables synchronized.', 'success');
        await loadAnalyticsData();
      } catch (err) {
        console.error('[Admin] Restore error:', err);
        showToast(`Restore failed: ${err.message || err}`, 'error');
      } finally {
        btnExecute.disabled = false;
      }
    });
  }
}

// ── Section 7: Security & Password ───────────────────────────────────────────
function initSecuritySettings() {
  const form = document.getElementById('admin-change-password-form');
  const submitBtn = document.getElementById('btn-submit-password');

  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const newPassword = document.getElementById('admin-new-password')?.value;
      const confirmPassword = document.getElementById('admin-confirm-password')?.value;

      if (!newPassword || newPassword.length < 8) {
        showToast('Password must be at least 8 characters long.', 'error');
        return;
      }

      if (newPassword !== confirmPassword) {
        showToast('Passwords do not match. Please verify.', 'error');
        return;
      }

      try {
        if (submitBtn) submitBtn.disabled = true;
        showToast('Updating administrator credentials...', 'info');

        const { error } = await supabase.auth.updateUser({ password: newPassword });
        if (error) throw error;

        showToast('Administrator password updated securely. New credentials are now active.', 'success');
        form.reset();
      } catch (err) {
        console.error('[Admin] Password change error:', err);
        showToast(`Failed to update password: ${err.message || err}`, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }
}

// ── Generic Modal Helpers ────────────────────────────────────────────────────
function initModalCloseHandlers() {
  document.querySelectorAll('[data-close]').forEach(btn => {
    btn.addEventListener('click', () => {
      const modalId = btn.getAttribute('data-close');
      const modal = document.getElementById(modalId);
      if (modal) modal.classList.add('hidden');
    });
  });

  document.querySelectorAll('.admin-modal-overlay').forEach(modal => {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.add('hidden');
    });
  });
}

// ── Application Initialization ───────────────────────────────────────────────
async function init() {
  console.log('[Admin] Initializing Administrator Command Console...');

  const user = await ensureAdminSession();
  if (!user) return;

  initNavigation();
  initReportsExports();
  initUsersManagementEvents();
  initScheduleEvents();
  initAnnouncementsEvents();
  initBackupRestore();
  initSecuritySettings();
  initModalCloseHandlers();

  // Load Initial Analytics
  await loadAnalyticsData();
}

// Bootstrap
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
