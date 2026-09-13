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


let activeChartInstance = null;

export function renderDashboardInsights() {
  const canvas = document.getElementById('dashboard-chart');
  if (!canvas || typeof Chart === 'undefined') return;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  if (activeChartInstance) {
    activeChartInstance.destroy();
    activeChartInstance = null;
  }

  const { waiting, consultsToday, vitalsToday, dispensesToday } = clinicalMetricsCache;

  activeChartInstance = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['In Queue', 'Consultations', 'Vitals Triage', 'Dispenses'],
      datasets: [{
        data: [waiting, consultsToday, vitalsToday, dispensesToday],
        backgroundColor: [
          '#3b82f6',
          '#10b981',
          '#f59e0b',
          '#8b5cf6'
        ],
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
          labels: {
            font: { size: 11, family: "'Inter', sans-serif" },
            boxWidth: 12,
            padding: 14
          }
        }
      },
      cutout: '68%'
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
      try {
        await loadClinicalOperationsMetrics();
        renderDashboardInsights();
      } finally {
        toggleStatsSkeleton(false);
        dashRefreshBtn.disabled = false;
      }
    });
  }

  startAdminDashboardAutoRefresh();
}

export const initTelemetryController = initTelemetry;

export async function refreshAdminDashboard() {
  // Instantly render cache/default metrics so skeletons are dismissed without waiting
  renderClinicalMetrics();
  await loadClinicalOperationsMetrics();
  renderDashboardInsights();
}

