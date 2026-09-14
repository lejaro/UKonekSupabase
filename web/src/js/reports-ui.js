// Reports UI Controller Module
// Handles CSV export button actions, date range filtering, loading states, and visual log viewing.

import * as Reports from './reports.js';

// Helper to set button loading state
function setButtonLoading(btn, isLoading) {
  if (!btn) return;
  const spinner = btn.querySelector('.btn-spinner');
  const label = btn.querySelector('.btn-label');
  if (isLoading) {
    btn.disabled = true;
    if (spinner) spinner.style.display = 'inline-block';
  } else {
    btn.disabled = false;
    if (spinner) spinner.style.display = 'none';
  }
}

// Helper to show export status
function showExportStatus(message, isError = false) {
  const status = document.getElementById('export-status');
  const statusMessage = document.getElementById('export-status-message');
  if (status && statusMessage) {
    statusMessage.textContent = message;
    status.className = isError
      ? 'export-status-error'
      : 'export-status-success';
    status.style.display = 'block';
    status.style.padding = '16px';
    status.style.marginTop = '24px';
    status.style.borderRadius = '8px';
    status.style.background = isError ? '#fef2f2' : '#f0fdf4';
    status.style.border = isError ? '1px solid #fecaca' : '1px solid #bbf7d0';
    statusMessage.style.color = isError ? '#991b1b' : '#166534';
    statusMessage.style.fontSize = '13px';
    statusMessage.style.fontWeight = '500';
    statusMessage.style.margin = '0';

    setTimeout(() => {
      status.style.display = 'none';
    }, 5000);
  }
}

// Get date range
function getDateRange() {
  const startDate = document.getElementById('export-start-date')?.value || null;
  const endDate = document.getElementById('export-end-date')?.value || null;
  return { startDate, endDate };
}

// Clear date range
document.getElementById('clear-date-range-btn')?.addEventListener('click', () => {
  const startInput = document.getElementById('export-start-date');
  const endInput = document.getElementById('export-end-date');
  if (startInput) startInput.value = '';
  if (endInput) endInput.value = '';
  document.querySelectorAll('#export-presets .ph-filter-chip').forEach(c => {
    c.classList.toggle('is-active', c.getAttribute('data-preset') === 'all');
  });
  loadStaffLogsVisual();
});

// Patient Report
document.getElementById('export-patient-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-patient-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportPatientReport(startDate, endDate);
    showExportStatus(`Patient Report exported successfully! (${result.count} records)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// Consultation Report
document.getElementById('export-consultation-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-consultation-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportConsultationReport(startDate, endDate);
    showExportStatus(`Consultation Report exported successfully! (${result.count} records)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// Doctor Activity Report
document.getElementById('export-doctor-activity-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-doctor-activity-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportDoctorActivityReport(startDate, endDate);
    showExportStatus(`Doctor Activity Report exported successfully! (${result.count} doctors)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// Queue Report
document.getElementById('export-queue-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-queue-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportQueueReport(startDate, endDate);
    showExportStatus(`Queue Report exported successfully! (${result.count} tickets)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// System Usage Report
document.getElementById('export-system-usage-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-system-usage-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportSystemUsageReport(startDate, endDate);
    showExportStatus(`System Usage Report exported successfully! (${result.count} metrics)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// Staff Session Logs Report Export
document.getElementById('export-staff-logs-report-btn')?.addEventListener('click', async () => {
  const btn = document.getElementById('export-staff-logs-report-btn');
  setButtonLoading(btn, true);
  try {
    const { startDate, endDate } = getDateRange();
    const result = await Reports.exportStaffLoginLogsReport(startDate, endDate);
    showExportStatus(`Staff Session Logs exported successfully! (${result.count} logs)`);
  } catch (error) {
    console.error('Export error:', error);
    showExportStatus(`Failed to export: ${error.message}`, true);
  } finally {
    setButtonLoading(btn, false);
  }
});

// Visual Log Viewer Logic
async function loadStaffLogsVisual() {
  const tbody = document.getElementById('staff-logs-tbody');
  if (!tbody) return;

  tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:24px;color:#475569;font-size:13px;">Loading authentication logs...</td></tr>`;

  try {
    const { startDate, endDate } = getDateRange();
    const searchTerm = document.getElementById('staff-logs-search')?.value || '';
    const logs = await Reports.fetchStaffLoginLogs(startDate, endDate, searchTerm);

    if (logs.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:24px;color:#64748b;font-size:13px;">No authentication log data matched the criteria.</td></tr>`;
      return;
    }

    tbody.innerHTML = logs.map(log => {
      const formattedDate = log.logged_at ? new Date(log.logged_at).toLocaleString('en-US', { timeZone: 'Asia/Manila' }) : '—';
      const actionStyle = log.action === 'login'
        ? 'background:#dcfce7;color:#15803d;padding:2px 8px;border-radius:9999px;font-size:11px;font-weight:700;display:inline-block;'
        : 'background:#fee2e2;color:#b91c1c;padding:2px 8px;border-radius:9999px;font-size:11px;font-weight:700;display:inline-block;';

      return `
        <tr style="border-bottom:1px solid #f1f5f9;">
          <td style="padding:12px;font-size:13px;color:#0f172a;text-align:left;">${log.staff_id || '—'}</td>
          <td style="padding:12px;font-size:13px;color:#334155;font-weight:600;text-align:left;">${log.username || '—'}</td>
          <td style="padding:12px;font-size:13px;color:#475569;text-align:left;">${log.email || '—'}</td>
          <td style="padding:12px;font-size:13px;color:#475569;text-align:left;text-transform:capitalize;">${log.role || '—'}</td>
          <td style="padding:12px;font-size:13px;text-align:center;"><span style="${actionStyle}">${log.action}</span></td>
          <td style="padding:12px;font-size:13px;color:#64748b;text-align:right;">${formattedDate}</td>
        </tr>
      `;
    }).join('');
  } catch (error) {
    console.error('Visual log load error:', error);
    tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:24px;color:#b91c1c;font-size:13px;font-weight:600;">Error: ${error.message || 'Failed to load logs.'}</td></tr>`;
  }
}

// Debouncer helper
function debounceLogViewer(func, wait) {
  let timeout;
  return function (...args) {
    clearTimeout(timeout);
    timeout = setTimeout(() => func.apply(this, args), wait);
  };
}

// Bind log viewer events
document.getElementById('staff-logs-refresh-btn')?.addEventListener('click', loadStaffLogsVisual);
document.getElementById('staff-logs-search')?.addEventListener('input', debounceLogViewer(loadStaffLogsVisual, 350));

// Auto-load logs on click of exports tab (supporting both legacy and hub IDs)
const exportsTab = document.getElementById('hub-tab-exports') || document.getElementById('tab-exports');
exportsTab?.addEventListener('click', () => {
  setTimeout(loadStaffLogsVisual, 100);
});

// Expose globally for reportsHubController
window.loadStaffLogsVisual = loadStaffLogsVisual;
export { loadStaffLogsVisual };

console.log('[Reports] CSV Export UI module loaded and wired');
