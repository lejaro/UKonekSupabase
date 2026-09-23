/**
 * Telemetry & Operational Metrics Controller
 * Manages executive KPI cards, Chart.js telemetry, and operational data refreshes.
 */

import { supabase } from '../lib/supabaseClient.js';
import { navigateToSection } from './navigationController.js';
import { toggleStatsSkeleton, toggleChartSkeleton } from '../utils/uiHelpers.js';

export const ADMIN_DASHBOARD_REFRESH_MS = 15000;
let adminDashboardRefreshTimer = null;
let adminDashboardRefreshInFlight = false;

export function getManilaTodayStr() {
  return new Intl.DateTimeFormat('fr-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(new Date());
}

export let clinicalMetricsCache = {
  waiting: 0,
  serving: 0,
  consultsToday: 0,
  vitalsToday: 0,
  dispensesToday: 0
};

export async function loadClinicalOperationsMetrics() {
  try {
    const manilaTodayStr = getManilaTodayStr();
    const manilaStartIso = `${manilaTodayStr}T00:00:00+08:00`;
    const manilaEndIso = `${manilaTodayStr}T23:59:59.999+08:00`;

    // Query active queue tickets specifically for today's queue date
    const [metricsRpc, queueWaitingRes, queueServingRes] = await Promise.all([
      supabase.rpc('get_clinical_operations_metrics'),
      supabase.from('queue_tickets').select('id', { count: 'exact', head: true }).in('status', ['waiting', 'on_call']).eq('queue_date', manilaTodayStr),
      supabase.from('queue_tickets').select('id', { count: 'exact', head: true }).eq('status', 'serving').eq('queue_date', manilaTodayStr)
    ]);

    const { data, error } = metricsRpc;

    const waitingToday = (queueWaitingRes && typeof queueWaitingRes.count === 'number')
      ? queueWaitingRes.count
      : (data?.waiting || 0);

    const servingToday = (queueServingRes && typeof queueServingRes.count === 'number')
      ? queueServingRes.count
      : (data?.serving || 0);

    if (error) {
      console.warn('RPC get_clinical_operations_metrics failed, falling back to individual queries:', error);
      const [consultsRes, vitalsRes, rxRes, otcRes] = await Promise.all([
        supabase.from('consultations').select('id', { count: 'exact', head: true }).gte('created_at', manilaStartIso).lte('created_at', manilaEndIso),
        supabase.from('vital_signs').select('id', { count: 'exact', head: true }).gte('created_at', manilaStartIso).lte('created_at', manilaEndIso),
        supabase.from('prescription_item_dispenses').select('id', { count: 'exact', head: true }).gte('dispensed_at', manilaStartIso).lte('dispensed_at', manilaEndIso),
        supabase.from('otc_dispenses').select('id', { count: 'exact', head: true }).gte('dispensed_at', manilaStartIso).lte('dispensed_at', manilaEndIso)
      ]);

      const rxCount = (rxRes && typeof rxRes.count === 'number') ? rxRes.count : 0;
      const otcCount = (otcRes && typeof otcRes.count === 'number') ? otcRes.count : 0;

      clinicalMetricsCache = {
        waiting: waitingToday,
        serving: servingToday,
        consultsToday: (consultsRes && typeof consultsRes.count === 'number') ? consultsRes.count : 0,
        vitalsToday: (vitalsRes && typeof vitalsRes.count === 'number') ? vitalsRes.count : 0,
        dispensesToday: rxCount + otcCount
      };
    } else {
      clinicalMetricsCache = {
        waiting: waitingToday,
        serving: servingToday,
        consultsToday: data?.consults_today || 0,
        vitalsToday: data?.vitals_today || 0,
        dispensesToday: data?.dispenses_today || 0
      };
    }

    try {
      await loadDashboardAnalyticsData();
    } catch (_) {}

    renderClinicalMetrics();
  } catch (err) {
    console.warn('Failed to load clinical operations metrics:', err);
  } finally {
    renderClinicalMetrics();
  }
}

export function updateRegisteredCitizensMetric(count) {
  clinicalMetricsCache.citizensCount = count;
  const statCitizens = document.getElementById('stat-citizens');
  if (statCitizens) {
    statCitizens.textContent = String(count);
    statCitizens.classList.remove('data-loaded');
    void statCitizens.offsetWidth;
    statCitizens.classList.add('data-loaded');
  }
}

export function renderClinicalMetrics() {
  const statQueueWaiting = document.getElementById('stat-queue-waiting');
  const statConsultsToday = document.getElementById('stat-consults-today');
  const statVitalsToday = document.getElementById('stat-vitals-today');
  const statDispensesToday = document.getElementById('stat-dispenses-today');
  const statCitizens = document.getElementById('stat-citizens');
  const statQueueFoot = document.getElementById('stat-queue-foot');

  const updateMetric = (el, val) => {
    if (!el) return;
    el.textContent = String(val);
    el.classList.remove('data-loaded');
    void el.offsetWidth;
    el.classList.add('data-loaded');
  };

  updateMetric(statQueueWaiting, clinicalMetricsCache.waiting);
  updateMetric(statConsultsToday, clinicalMetricsCache.consultsToday);
  updateMetric(statVitalsToday, clinicalMetricsCache.vitalsToday);
  updateMetric(statDispensesToday, clinicalMetricsCache.dispensesToday);
  updateMetric(statCitizens, clinicalMetricsCache.citizensCount);

  if (statQueueFoot) {
    if (clinicalMetricsCache.serving > 0) {
      statQueueFoot.textContent = `${clinicalMetricsCache.serving} patient${clinicalMetricsCache.serving > 1 ? 's' : ''} being served`;
      statQueueFoot.className = 'stat-foot stat-success';
    } else if (clinicalMetricsCache.waiting > 0) {
      statQueueFoot.textContent = `${clinicalMetricsCache.waiting} waiting in triage/consult`;
      statQueueFoot.className = 'stat-foot stat-warning';
    } else {
      statQueueFoot.textContent = 'Queue is clear';
      statQueueFoot.className = 'stat-foot stat-neutral';
    }
  }

  const syncElem = document.getElementById('dashboard-last-sync');
  if (syncElem) {
    syncElem.textContent = `Updated ${new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}`;
  }
}

// -------------------------------------------------------------
// Multi-Chart Analytics Engine (Line, Bar, Pie)
// -------------------------------------------------------------

export let analyticsDataCache = {
  lineTrend: { labels: [], queueCounts: [], consultCounts: [] },
  topDiagnoses: { labels: [], counts: [] },
  priorityDist: { labels: [], counts: [] }
};

export async function loadDashboardAnalyticsData() {
  try {
    const dates = [];
    const dayLabels = [];
    const dailyQueueMap = {};
    const dailyConsultMap = {};

    const now = new Date();
    for (let i = 6; i >= 0; i--) {
      const d = new Date(now.getTime() - i * 86400000);
      const isoDate = new Intl.DateTimeFormat('fr-CA', {
        timeZone: 'Asia/Manila',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
      }).format(d);
      dates.push(isoDate);
      const parts = isoDate.split('-');
      dayLabels.push(`${Number(parts[1])}/${Number(parts[2])}`);
      dailyQueueMap[isoDate] = 0;
      dailyConsultMap[isoDate] = 0;
    }

    const sevenDaysAgoStart = `${dates[0]}T00:00:00+08:00`;

    const [queueRes, consultsRes] = await Promise.all([
      supabase
        .from('queue_tickets')
        .select('queue_date, created_at, citizen_type, service_label')
        .gte('created_at', sevenDaysAgoStart),
      supabase
        .from('consultations')
        .select('consulted_at, created_at, diagnosis')
        .gte('created_at', sevenDaysAgoStart)
    ]);

    const queueTickets = queueRes.data || [];
    const consults = consultsRes.data || [];

    // 1. Line Chart Data: Daily Volume & Consults
    queueTickets.forEach(t => {
      const qDate = t.queue_date || (t.created_at ? t.created_at.slice(0, 10) : '');
      if (dailyQueueMap.hasOwnProperty(qDate)) {
        dailyQueueMap[qDate]++;
      }
    });

    consults.forEach(c => {
      const cDate = (c.consulted_at || c.created_at || '').slice(0, 10);
      if (dailyConsultMap.hasOwnProperty(cDate)) {
        dailyConsultMap[cDate]++;
      }
    });

    const queueCounts = dates.map(d => dailyQueueMap[d] || 0);
    const consultCounts = dates.map(d => dailyConsultMap[d] || 0);

    // 2. Bar Chart Data: Top 5 Diagnoses
    const diagCounts = {};
    consults.forEach(c => {
      const diag = String(c.diagnosis || '').trim();
      if (diag && diag !== '—' && diag.toLowerCase() !== 'none' && diag.toLowerCase() !== 'n/a' && diag.toLowerCase() !== 'null') {
        diagCounts[diag] = (diagCounts[diag] || 0) + 1;
      }
    });

    const sortedDiags = Object.entries(diagCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);

    // 3. Pie Chart Data: Patient Priority
    const priorityCounts = {
      'Regular': 0,
      'Senior Citizen': 0,
      'PWD': 0,
      'Pregnant': 0
    };

    queueTickets.forEach(t => {
      const type = String(t.citizen_type || '').toLowerCase();
      const sLabel = String(t.service_label || '').toLowerCase();
      if (type === 'senior' || sLabel.includes('senior')) {
        priorityCounts['Senior Citizen']++;
      } else if (type === 'pwd' || sLabel.includes('pwd')) {
        priorityCounts['PWD']++;
      } else if (type === 'pregnant' || sLabel.includes('pregnant')) {
        priorityCounts['Pregnant']++;
      } else {
        priorityCounts['Regular']++;
      }
    });

    analyticsDataCache = {
      lineTrend: {
        labels: dayLabels,
        queueCounts,
        consultCounts
      },
      topDiagnoses: {
        labels: sortedDiags.map(d => d[0]),
        counts: sortedDiags.map(d => d[1])
      },
      priorityDist: {
        labels: Object.keys(priorityCounts),
        counts: Object.values(priorityCounts)
      }
    };
  } catch (err) {
    console.warn('[Telemetry] Analytics load notice:', err);
  }
}

let activeVolumeLineChart = null;
let activeDiagnosesBarChart = null;
let activePriorityPieChart = null;

export function renderDashboardInsights() {
  if (typeof Chart === 'undefined') return;

  renderVolumeLineChart();
  renderDiagnosesBarChart();
  renderPriorityPieChart();
}

function renderVolumeLineChart() {
  const canvas = document.getElementById('chart-volume-trend');
  if (!canvas) return;

  if (activeVolumeLineChart) {
    activeVolumeLineChart.destroy();
    activeVolumeLineChart = null;
  }

  const { labels, queueCounts, consultCounts } = analyticsDataCache.lineTrend;
  const hasData = (queueCounts && queueCounts.some(c => c > 0)) || (consultCounts && consultCounts.some(c => c > 0));
  const emptyNote = document.getElementById('chart-volume-empty');
  if (emptyNote) emptyNote.classList.toggle('hidden', hasData);

  const displayLabels = labels.length ? labels : ['Day 1', 'Day 2', 'Day 3', 'Day 4', 'Day 5', 'Day 6', 'Day 7'];
  const displayQueue = queueCounts.length ? queueCounts : [0, 0, 0, 0, 0, 0, 0];
  const displayConsults = consultCounts.length ? consultCounts : [0, 0, 0, 0, 0, 0, 0];

  const ctx = canvas.getContext('2d');
  activeVolumeLineChart = new Chart(ctx, {
    type: 'line',
    data: {
      labels: displayLabels,
      datasets: [
        {
          label: 'Queue Intake',
          data: displayQueue,
          borderColor: '#3b82f6',
          backgroundColor: 'rgba(59, 130, 246, 0.08)',
          borderWidth: 2.5,
          tension: 0.35,
          fill: true,
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: '#3b82f6'
        },
        {
          label: 'Consultations',
          data: displayConsults,
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.08)',
          borderWidth: 2.5,
          tension: 0.35,
          fill: true,
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: '#10b981'
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: 'index',
        intersect: false
      },
      plugins: {
        legend: {
          display: false
        },
        tooltip: {
          backgroundColor: '#0f172a',
          titleFont: { family: "'Inter', sans-serif", size: 12 },
          bodyFont: { family: "'Inter', sans-serif", size: 11.5 },
          padding: 10,
          cornerRadius: 8
        }
      },
      scales: {
        x: {
          grid: {
            display: false
          },
          ticks: {
            font: { family: "'Inter', sans-serif", size: 11 },
            color: '#64748b'
          }
        },
        y: {
          beginAtZero: true,
          ticks: {
            stepSize: 1,
            precision: 0,
            font: { family: "'Inter', sans-serif", size: 11 },
            color: '#64748b'
          },
          grid: {
            color: '#f1f5f9'
          }
        }
      }
    }
  });
}

function renderDiagnosesBarChart() {
  const canvas = document.getElementById('chart-diagnoses-bar');
  if (!canvas) return;

  if (activeDiagnosesBarChart) {
    activeDiagnosesBarChart.destroy();
    activeDiagnosesBarChart = null;
  }

  const { labels, counts } = analyticsDataCache.topDiagnoses;
  const hasData = labels && labels.length > 0 && counts.some(c => c > 0);
  const emptyNote = document.getElementById('chart-diagnoses-empty');
  if (emptyNote) emptyNote.classList.toggle('hidden', hasData);

  const displayLabels = hasData ? labels : ['No diagnoses logged yet'];
  const displayCounts = hasData ? counts : [0];

  const ctx = canvas.getContext('2d');
  activeDiagnosesBarChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: displayLabels,
      datasets: [{
        label: 'Cases',
        data: displayCounts,
        backgroundColor: [
          '#10b981',
          '#059669',
          '#34d399',
          '#6ee7b7',
          '#a7f3d0'
        ],
        borderRadius: 6,
        borderSkipped: false,
        maxBarThickness: 32
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: '#0f172a',
          titleFont: { family: "'Inter', sans-serif", size: 12 },
          bodyFont: { family: "'Inter', sans-serif", size: 11.5 },
          padding: 10,
          cornerRadius: 8
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            font: { family: "'Inter', sans-serif", size: 10.5 },
            color: '#64748b',
            callback: function(val, index) {
              const label = this.getLabelForValue(index);
              return (label && label.length > 15) ? label.slice(0, 13) + '…' : label;
            }
          }
        },
        y: {
          beginAtZero: true,
          ticks: {
            stepSize: 1,
            precision: 0,
            font: { family: "'Inter', sans-serif", size: 11 },
            color: '#64748b'
          },
          grid: { color: '#f1f5f9' }
        }
      }
    }
  });
}

function renderPriorityPieChart() {
  const canvas = document.getElementById('chart-priority-pie');
  if (!canvas) return;

  if (activePriorityPieChart) {
    activePriorityPieChart.destroy();
    activePriorityPieChart = null;
  }

  const { labels, counts } = analyticsDataCache.priorityDist;
  const total = counts ? counts.reduce((a, b) => a + b, 0) : 0;
  const hasData = total > 0;
  const emptyNote = document.getElementById('chart-priority-empty');
  if (emptyNote) emptyNote.classList.toggle('hidden', hasData);

  const displayLabels = hasData ? labels : ['No queue activity'];
  const displayCounts = hasData ? counts : [1];
  const bgColors = hasData
    ? ['#3b82f6', '#f59e0b', '#8b5cf6', '#ec4899']
    : ['#e2e8f0'];

  const ctx = canvas.getContext('2d');
  activePriorityPieChart = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: displayLabels,
      datasets: [{
        data: displayCounts,
        backgroundColor: bgColors,
        borderWidth: 2,
        borderColor: '#ffffff',
        hoverOffset: 4
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: '62%',
      plugins: {
        legend: {
          position: 'bottom',
          labels: {
            boxWidth: 11,
            font: { family: "'Inter', sans-serif", size: 11 },
            padding: 10,
            color: '#475569'
          }
        },
        tooltip: {
          enabled: hasData,
          backgroundColor: '#0f172a',
          titleFont: { family: "'Inter', sans-serif", size: 12 },
          bodyFont: { family: "'Inter', sans-serif", size: 11.5 },
          padding: 10,
          cornerRadius: 8
        }
      }
    }
  });
}

export function startAdminDashboardAutoRefresh() {
  stopAdminDashboardAutoRefresh();
  adminDashboardRefreshTimer = setInterval(async () => {
    if (adminDashboardRefreshInFlight || document.visibilityState === 'hidden') return;
    adminDashboardRefreshInFlight = true;
    try {
      await loadClinicalOperationsMetrics();
      renderDashboardInsights();
    } catch (_) {}
    finally {
      adminDashboardRefreshInFlight = false;
    }
  }, ADMIN_DASHBOARD_REFRESH_MS);
}

export function stopAdminDashboardAutoRefresh() {
  if (adminDashboardRefreshTimer) {
    clearInterval(adminDashboardRefreshTimer);
    adminDashboardRefreshTimer = null;
  }
}

export function initTelemetry() {
  // Wire clickable stat cards to jump to corresponding clinical workflows
  const cardQueue = document.getElementById('stat-queue-waiting')?.closest('.stat-card');
  const cardConsults = document.getElementById('stat-consults-today')?.closest('.stat-card');
  const cardVitals = document.getElementById('stat-vitals-today')?.closest('.stat-card');
  const cardDispenses = document.getElementById('stat-dispenses-today')?.closest('.stat-card');
  const cardCitizens = document.getElementById('stat-citizens')?.closest('.stat-card');

  if (cardQueue) cardQueue.addEventListener('click', () => navigateToSection('queue-section'));
  if (cardConsults) cardConsults.addEventListener('click', () => navigateToSection('consultation-section'));
  if (cardVitals) cardVitals.addEventListener('click', () => navigateToSection('vitals-section'));
  if (cardDispenses) cardDispenses.addEventListener('click', () => navigateToSection('medicine-section'));
  if (cardCitizens) cardCitizens.addEventListener('click', () => navigateToSection('users-section', { pane: 'citizens-pane' }));

  const dashRefreshBtn = document.getElementById('dash-refresh-btn');
  if (dashRefreshBtn) {
    dashRefreshBtn.addEventListener('click', async () => {
      dashRefreshBtn.disabled = true;
      toggleStatsSkeleton(true);
      toggleChartSkeleton('chart-volume-trend', true);
      toggleChartSkeleton('chart-diagnoses-bar', true);
      toggleChartSkeleton('chart-priority-pie', true);
      try {
        await loadClinicalOperationsMetrics();
        renderDashboardInsights();
      } finally {
        toggleChartSkeleton('chart-volume-trend', false);
        toggleChartSkeleton('chart-diagnoses-bar', false);
        toggleChartSkeleton('chart-priority-pie', false);
        toggleStatsSkeleton(false);
        dashRefreshBtn.disabled = false;
      }
    });
  }

  startAdminDashboardAutoRefresh();
}

export const initTelemetryController = initTelemetry;

export async function refreshAdminDashboard() {
  const isFirstLoad = !analyticsDataCache.lineTrend.labels.length;
  if (isFirstLoad) {
    toggleStatsSkeleton(true);
    toggleChartSkeleton('chart-volume-trend', true);
    toggleChartSkeleton('chart-diagnoses-bar', true);
    toggleChartSkeleton('chart-priority-pie', true);
  }
  try {
    renderClinicalMetrics();
    await loadClinicalOperationsMetrics();
    renderDashboardInsights();
  } finally {
    if (isFirstLoad) {
      toggleChartSkeleton('chart-volume-trend', false);
      toggleChartSkeleton('chart-diagnoses-bar', false);
      toggleChartSkeleton('chart-priority-pie', false);
      toggleStatsSkeleton(false);
    }
  }
}


