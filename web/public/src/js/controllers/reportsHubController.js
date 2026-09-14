/**
 * Reports, Analytics & Communications Hub Controller
 * Manages segmented in-page tab switching:
 * 1. Promo Posters & Announcements (announcements-pane)
 * 2. Citizen Feedback (feedback-pane)
 * 3. Clinical Analytics (stats-pane)
 * 4. Data Export Center (exports-pane)
 */

import { supabase } from '../lib/supabaseClient.js';
import { showToast, toggleChartSkeleton, renderTableSkeleton } from '../utils/uiHelpers.js';
import { loadPromoPosters } from './promoPosterController.js';
import { loadSystemReportData, initSystemReportController } from './systemReportController.js';

let _feedbacks = [];
let _feedbackSearch = '';
let _feedbackRatingFilter = 'all';
let _activePaneId = 'announcements-pane';
let _diagnosesChart = null;
let _consultsChart = null;

function escHtml(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/**
 * Switch between the 4 hub panes:
 * 'announcements-pane', 'feedback-pane', 'stats-pane', 'exports-pane'
 */
export function switchReportsHubPane(targetPaneId) {
  if (!targetPaneId) return;
  _activePaneId = targetPaneId;

  // 1. Update tab button active states
  const hubTabsWrap = document.getElementById('reports-hub-tabs');
  if (hubTabsWrap) {
    hubTabsWrap.querySelectorAll('.personnel-tab-btn').forEach((btn) => {
      const pane = btn.getAttribute('data-pane');
      btn.classList.toggle('is-active', pane === targetPaneId);
    });
  }

  // 2. Toggle pane visibility
  const panes = document.querySelectorAll('.hub-content-pane');
  panes.forEach((pane) => {
    if (pane.id === targetPaneId) {
      pane.classList.remove('hidden');
    } else {
      pane.classList.add('hidden');
    }
  });

  // 3. Trigger data loaders for selected pane
  if (targetPaneId === 'announcements-pane') {
    loadPromoPosters();
  } else if (targetPaneId === 'feedback-pane') {
    loadFeedback();
  } else if (targetPaneId === 'stats-pane') {
    renderClinicalStats();
  } else if (targetPaneId === 'exports-pane') {
    loadSystemReportData();
    if (typeof window.loadStaffLogsVisual === 'function') {
      window.loadStaffLogsVisual();
    }
  }
}

/**
 * Refresh whichever sub-pane is currently active.
 */
export function refreshActiveReportsHubPane() {
  switchReportsHubPane(_activePaneId);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. CITIZEN FEEDBACK
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch feedbacks from Supabase public.feedbacks table.
 */
export async function loadFeedback() {
  const tbody = document.getElementById('feedback-tbody');
  if (tbody) renderTableSkeleton(tbody, 4, 3);

  try {
    const { data, error } = await supabase
      .from('feedbacks')
      .select(`
        id,
        citizen_id,
        from_email,
        subject,
        message,
        rating,
        created_at,
        citizen:citizens(id, first_name, last_name, email)
      `)
      .order('created_at', { ascending: false })
      .limit(100);

    if (error) {
      // Fallback if citizens relation join fails
      console.warn('[Feedback] Detailed join error, falling back to flat select:', error.message);
      const flatRes = await supabase
        .from('feedbacks')
        .select('id, citizen_id, from_email, subject, message, rating, created_at')
        .order('created_at', { ascending: false })
        .limit(100);

      if (flatRes.error) throw flatRes.error;
      _feedbacks = flatRes.data || [];
    } else {
      _feedbacks = data || [];
    }

    // Update hub count badge
    const badge = document.getElementById('hub-count-feedback');
    if (badge) {
      badge.textContent = String(_feedbacks.length);
    }

    renderFeedbackTable();
  } catch (err) {
    console.error('[Feedback] Load error:', err);
    showToast('Failed to load citizen feedback records.', 'error');
    if (tbody) {
      tbody.innerHTML = `
        <tr class="empty-row">
          <td colspan="4" style="text-align:center; padding:32px; color:#ef4444;">
            Error loading feedback data. Please check your connection and retry.
          </td>
        </tr>
      `;
    }
  }
}

/**
 * Render filtered feedback items in #feedback-tbody.
 */
export function renderFeedbackTable() {
  const tbody = document.getElementById('feedback-tbody');
  if (!tbody) return;

  const query = String(_feedbackSearch || '').trim().toLowerCase();

  const filtered = _feedbacks.filter((item) => {
    // Rating filter
    if (_feedbackRatingFilter !== 'all') {
      const r = Number(item.rating) || 0;
      if (_feedbackRatingFilter === '5' && r !== 5) return false;
      if (_feedbackRatingFilter === '4' && r !== 4) return false;
      if (_feedbackRatingFilter === '3' && r > 3) return false;
    }

    // Search query filter
    if (query) {
      const citizenName = item.citizen
        ? `${item.citizen.first_name || ''} ${item.citizen.last_name || ''}`.toLowerCase()
        : '';
      const email = String(item.from_email || '').toLowerCase();
      const subject = String(item.subject || '').toLowerCase();
      const message = String(item.message || '').toLowerCase();

      const match = citizenName.includes(query) ||
        email.includes(query) ||
        subject.includes(query) ||
        message.includes(query);
      if (!match) return false;
    }

    return true;
  });

  if (filtered.length === 0) {
    const isFiltered = query || _feedbackRatingFilter !== 'all';
    tbody.innerHTML = `
      <tr class="empty-row">
        <td colspan="4" style="text-align:center; padding:40px; color:#64748b;">
          <div style="font-weight:700; font-size:14px; margin-bottom:4px; color:#334155;">
            ${isFiltered ? 'No matching feedback found' : 'No citizen feedback received yet'}
          </div>
          <div style="font-size:12px; color:#94a3b8;">
            ${isFiltered ? 'Try clearing your search query or rating filter.' : 'Citizen responses submitted through the mobile app will automatically appear here.'}
          </div>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map((item) => {
    let citizenName = 'Anonymous Citizen';
    if (item.citizen && (item.citizen.first_name || item.citizen.last_name)) {
      citizenName = [item.citizen.first_name, item.citizen.last_name].filter(Boolean).join(' ');
    } else if (item.from_email) {
      citizenName = item.from_email.split('@')[0];
    }

    const email = item.from_email || (item.citizen?.email) || '';
    const ratingNum = Number(item.rating);
    const ratingStars = ratingNum ? '⭐'.repeat(Math.min(5, Math.max(1, ratingNum))) : '<span style="color:#94a3b8;">Not rated</span>';
    const dateFormatted = item.created_at
      ? new Date(item.created_at).toLocaleString('en-US', {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        })
      : '—';

    return `
      <tr class="clickable-row feedback-row" data-id="${item.id}" style="cursor:pointer; transition:background 0.15s ease;">
        <td class="table-cell" style="vertical-align:middle;">
          <div style="font-weight:700; color:#0f172a; font-size:13.5px;">${escHtml(citizenName)}</div>
          <div style="font-size:12px; color:#64748b; margin-top:2px;">
            ${email ? `<span style="color:#0284c7;">${escHtml(email)}</span> &bull; ` : ''}
            <span style="font-weight:600; color:#334155;">${escHtml(item.subject || 'General Feedback')}</span>
          </div>
        </td>
        <td class="table-cell" style="text-align:center; vertical-align:middle; font-size:13px;">
          <div>${ratingStars}</div>
          ${ratingNum ? `<span style="font-size:11px; color:#64748b; font-weight:700;">${ratingNum}/5</span>` : ''}
        </td>
        <td class="table-cell" style="text-align:center; vertical-align:middle; font-size:12px; color:#64748b;">
          ${dateFormatted}
        </td>
        <td class="table-cell" style="text-align:right; vertical-align:middle; white-space:nowrap;">
          <button type="button" class="chip-btn chip-btn-outline btn-view-feedback" data-id="${item.id}" style="padding:4px 10px; font-size:11px; margin-right:4px;">
            View
          </button>
          <button type="button" class="chip-btn chip-btn-danger btn-delete-feedback" data-id="${item.id}" style="padding:4px 10px; font-size:11px;">
            Delete
          </button>
        </td>
      </tr>
    `;
  }).join('');
}

/**
 * Open detail modal for a specific feedback entry.
 */
export function openFeedbackDetail(id) {
  const item = _feedbacks.find((f) => String(f.id) === String(id));
  if (!item) return;

  const modal = document.getElementById('feedback-detail-modal');
  const fromEl = document.getElementById('feedback-detail-from');
  const dateEl = document.getElementById('feedback-detail-date');
  const ratingEl = document.getElementById('feedback-detail-rating');
  const subjectEl = document.getElementById('feedback-detail-subject');
  const bodyEl = document.getElementById('feedback-detail-body');
  const deleteBtn = document.getElementById('feedback-detail-delete-btn');

  let citizenName = 'Anonymous Citizen';
  if (item.citizen && (item.citizen.first_name || item.citizen.last_name)) {
    citizenName = [item.citizen.first_name, item.citizen.last_name].filter(Boolean).join(' ');
  } else if (item.from_email) {
    citizenName = item.from_email;
  }

  const dateFormatted = item.created_at
    ? new Date(item.created_at).toLocaleString('en-US', {
        dateStyle: 'medium',
        timeStyle: 'short'
      })
    : '—';

  const ratingNum = Number(item.rating);

  if (fromEl) fromEl.textContent = citizenName;
  if (dateEl) dateEl.textContent = dateFormatted;
  if (ratingEl) {
    ratingEl.innerHTML = ratingNum
      ? `<span style="font-size:14px; font-weight:700; color:#d97706;">${'⭐'.repeat(ratingNum)} (${ratingNum}/5)</span>`
      : '<span style="font-size:12px; color:#94a3b8;">No rating given</span>';
  }
  if (subjectEl) subjectEl.textContent = item.subject || 'No Subject';
  if (bodyEl) bodyEl.textContent = item.message || '(No message content provided)';

  if (deleteBtn) {
    deleteBtn.onclick = () => deleteFeedback(item.id);
  }

  if (modal) modal.classList.remove('hidden');
}

/**
 * Delete feedback by ID.
 */
export async function deleteFeedback(id) {
  if (!confirm('Are you sure you want to permanently delete this citizen feedback?')) return;

  try {
    const { error } = await supabase.from('feedbacks').delete().eq('id', id);
    if (error) throw error;

    showToast('Feedback deleted successfully.', 'success');
    document.getElementById('feedback-detail-modal')?.classList.add('hidden');
    await loadFeedback();
  } catch (err) {
    console.error('[Feedback] Delete error:', err);
    showToast('Failed to delete feedback record: ' + (err.message || 'Unknown error'), 'error');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. CLINICAL ANALYTICS
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Render clinical analytics charts and key vitals telemetry.
 */
export async function renderClinicalStats() {
  toggleChartSkeleton('diagnoses-chart', true);
  toggleChartSkeleton('consults-chart', true);

  try {
    // 1. Fetch consultations and vital signs
    const [consultsRes, vitalsRes] = await Promise.all([
      supabase.from('consultations').select('diagnosis, consulted_at, created_at').order('consulted_at', { ascending: false }).limit(200),
      supabase.from('vital_signs').select('temperature, blood_pressure').order('created_at', { ascending: false }).limit(200)
    ]);

    if (consultsRes.error) console.warn('[ReportsHub] Clinical stats consults fetch notice:', consultsRes.error.message);
    if (vitalsRes.error) console.warn('[ReportsHub] Clinical stats vitals fetch notice:', vitalsRes.error.message);

    const consults = consultsRes.data || [];
    const vitals = vitalsRes.data || [];

    // 2. Aggregate Top Diagnoses
    const diagMap = {};
    consults.forEach((c) => {
      const diag = String(c.diagnosis || '').trim();
      if (diag && diag !== '—' && diag.toLowerCase() !== 'none') {
        diagMap[diag] = (diagMap[diag] || 0) + 1;
      }
    });

    const sortedDiags = Object.entries(diagMap).sort((a, b) => b[1] - a[1]).slice(0, 5);

    // 3. Aggregate Daily Consultations (Last 7 days)
    const dailyMap = {};
    const last7Days = [...Array(7)].map((_, i) => {
      const d = new Date();
      d.setDate(d.getDate() - (6 - i));
      return d.toISOString().split('T')[0];
    });

    last7Days.forEach((day) => { dailyMap[day] = 0; });
    consults.forEach((c) => {
      const ts = c.consulted_at || c.created_at;
      if (ts) {
        const day = ts.split('T')[0];
        if (dailyMap.hasOwnProperty(day)) dailyMap[day]++;
      }
    });

    // 4. Vitals Metrics (Average Body Temp & Hypertension)
    const temps = vitals
      .map((v) => Number(v.temperature))
      .filter((t) => !isNaN(t) && t >= 30 && t <= 45);

    const avgTemp = temps.length
      ? (temps.reduce((sum, t) => sum + t, 0) / temps.length).toFixed(1)
      : '—';

    let hypertensionCount = 0;
    vitals.forEach((v) => {
      if (v.blood_pressure) {
        const parts = String(v.blood_pressure).split('/');
        if (parts.length === 2) {
          const sys = parseInt(parts[0], 10);
          const dia = parseInt(parts[1], 10);
          if (!isNaN(sys) && !isNaN(dia) && (sys >= 140 || dia >= 90)) {
            hypertensionCount++;
          }
        }
      }
    });

    const avgTempEl = document.getElementById('avg-temp');
    if (avgTempEl) {
      avgTempEl.textContent = avgTemp !== '—' ? `${avgTemp}°C` : '—';
    }

    const hypEl = document.getElementById('hypertension-count');
    if (hypEl) {
      hypEl.textContent = String(hypertensionCount);
    }

    // 5. Render Charts via Chart.js
    if (typeof window.Chart !== 'undefined') {
      // Diagnoses Doughnut Chart
      const ctxDiag = document.getElementById('diagnoses-chart');
      if (ctxDiag) {
        if (_diagnosesChart) {
          _diagnosesChart.destroy();
          _diagnosesChart = null;
        }

        const labels = sortedDiags.length ? sortedDiags.map((d) => d[0]) : ['No diagnoses logged yet'];
        const dataVals = sortedDiags.length ? sortedDiags.map((d) => d[1]) : [1];
        const bgColors = sortedDiags.length
          ? ['#2563eb', '#16a34a', '#f59e0b', '#dc2626', '#8b5cf6']
          : ['#e2e8f0'];

        _diagnosesChart = new window.Chart(ctxDiag, {
          type: 'doughnut',
          data: {
            labels,
            datasets: [{
              data: dataVals,
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

      // Consultations Line Chart
      const ctxCons = document.getElementById('consults-chart');
      if (ctxCons) {
        if (_consultsChart) {
          _consultsChart.destroy();
          _consultsChart = null;
        }

        const dateLabels = last7Days.map((d) => {
          const parts = d.split('-');
          return `${Number(parts[1])}/${Number(parts[2])}`;
        });
        const counts = last7Days.map((d) => dailyMap[d] || 0);

        _consultsChart = new window.Chart(ctxCons, {
          type: 'line',
          data: {
            labels: dateLabels,
            datasets: [{
              label: 'Daily Consultations',
              data: counts,
              borderColor: '#16a34a',
              backgroundColor: 'rgba(22, 163, 74, 0.1)',
              tension: 0.35,
              fill: true,
              pointRadius: 4,
              pointBackgroundColor: '#16a34a'
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            resizeDelay: 200,
            animation: { duration: 300 },
            scales: {
              y: {
                beginAtZero: true,
                ticks: { stepSize: 1, precision: 0 }
              }
            },
            plugins: {
              legend: { display: false }
            }
          }
        });
      }
    }
  } catch (err) {
    console.error('[Analytics] Chart rendering error:', err);
  } finally {
    toggleChartSkeleton('diagnoses-chart', false);
    toggleChartSkeleton('consults-chart', false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. DATA EXPORT CENTER & PRESETS
// ─────────────────────────────────────────────────────────────────────────────

function setupExportDatePresets() {
  const presetChips = document.querySelectorAll('#export-presets .ph-filter-chip');
  if (!presetChips.length) return;

  presetChips.forEach((chip) => {
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      presetChips.forEach((c) => c.classList.remove('is-active'));
      chip.classList.add('is-active');

      const preset = chip.getAttribute('data-preset');
      const startInput = document.getElementById('export-start-date');
      const endInput = document.getElementById('export-end-date');
      const now = new Date();
      const todayStr = now.toISOString().split('T')[0];

      if (preset === 'today') {
        if (startInput) startInput.value = todayStr;
        if (endInput) endInput.value = todayStr;
      } else if (preset === 'month') {
        const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
        if (startInput) startInput.value = firstOfMonth;
        if (endInput) endInput.value = todayStr;
      } else if (preset === 'year') {
        const firstOfYear = new Date(now.getFullYear(), 0, 1).toISOString().split('T')[0];
        if (startInput) startInput.value = firstOfYear;
        if (endInput) endInput.value = todayStr;
      } else {
        // 'all'
        if (startInput) startInput.value = '';
        if (endInput) endInput.value = '';
      }

      if (typeof window.loadStaffLogsVisual === 'function') {
        window.loadStaffLogsVisual();
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. EVENT BINDINGS & INITIALIZATION
// ─────────────────────────────────────────────────────────────────────────────

export function initReportsHubController() {
  console.log('[ReportsHub] Initializing Reports, Analytics & Communications Hub...');

  // 1. In-Page Segmented Tab Switcher
  const hubTabsWrap = document.getElementById('reports-hub-tabs');
  if (hubTabsWrap) {
    hubTabsWrap.querySelectorAll('.personnel-tab-btn').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const paneId = btn.getAttribute('data-pane');
        if (paneId) switchReportsHubPane(paneId);
      });
    });
  }

  // 2. Hub-wide Refresh button
  const refreshBtn = document.getElementById('reports-hub-refresh-btn');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', (e) => {
      e.preventDefault();
      refreshActiveReportsHubPane();
    });
  }

  // 3. Citizen Feedback events
  const feedbackSearch = document.getElementById('feedback-search-input');
  if (feedbackSearch) {
    feedbackSearch.addEventListener('input', (e) => {
      _feedbackSearch = e.target.value;
      renderFeedbackTable();
    });
  }

  const feedbackRatingChips = document.querySelectorAll('#feedback-filter-chips .ph-filter-chip');
  feedbackRatingChips.forEach((chip) => {
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      feedbackRatingChips.forEach((c) => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      _feedbackRatingFilter = chip.getAttribute('data-rating') || 'all';
      renderFeedbackTable();
    });
  });

  const feedbackTbody = document.getElementById('feedback-tbody');
  if (feedbackTbody) {
    feedbackTbody.addEventListener('click', (e) => {
      const delBtn = e.target.closest('.btn-delete-feedback');
      if (delBtn) {
        e.stopPropagation();
        const id = delBtn.getAttribute('data-id');
        if (id) deleteFeedback(id);
        return;
      }

      const viewBtn = e.target.closest('.btn-view-feedback');
      const row = e.target.closest('.feedback-row');
      const target = viewBtn || row;
      if (target) {
        const id = target.getAttribute('data-id');
        if (id) openFeedbackDetail(id);
      }
    });
  }

  // Feedback detail modal close
  const detailModal = document.getElementById('feedback-detail-modal');
  const closeBtn = document.getElementById('feedback-detail-close');
  if (closeBtn && detailModal) {
    closeBtn.addEventListener('click', () => detailModal.classList.add('hidden'));
  }
  if (detailModal) {
    detailModal.addEventListener('click', (e) => {
      if (e.target === detailModal) detailModal.classList.add('hidden');
    });
  }

  // 4. Setup export date presets
  setupExportDatePresets();

  // 5. Initialize System Report & Executive Intelligence
  initSystemReportController();

  // 6. Initial background load of feedback count to populate badge
  loadFeedback().catch((e) => console.warn('[ReportsHub] Feedback count preload warning:', e));
}
