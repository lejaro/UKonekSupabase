/**
 * clinic-enhancements.js
 * Phase 1: Enhanced Consultation, Prescription Safety, Inventory Management, and Analytics
 * This module adds new functionality on top of the existing dashboard.js
 */

(function () {
  'use strict';

  /* ------------------------------------------------------------------ */
  /*  UTILITY HELPERS                                                    */
  /* ------------------------------------------------------------------ */

  function $(id) { return document.getElementById(id); }
  function $$(sel, root) { return (root || document).querySelectorAll(sel); }

  async function getSupabase() {
    const mod = await import('./supabase-config.js');
    return mod.supabase;
  }

  function formatDate(d) {
    if (!d) return '—';
    const dt = new Date(d);
    return isNaN(dt) ? '—' : dt.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
  }
  function formatDateTime(d) {
    if (!d) return '—';
    const dt = new Date(d);
    return isNaN(dt) ? '—' : dt.toLocaleString('en-US', { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  }
  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function toast(msg, type) {
    if (typeof window.showToast === 'function') window.showToast(msg, type);
    else console.log(`[${type}] ${msg}`);
  }

  /* ------------------------------------------------------------------ */
  /*  ENHANCED CONSULTATION MODAL                                       */
  /* ------------------------------------------------------------------ */

  const enhancedConsultModal = $('enhanced-consult-modal');
  const enhancedConsultForm = $('enhanced-consult-form');
  const openEnhancedConsultBtn = $('open-consult-modal-btn');

  // Vitals template
  const VITAL_FIELDS = [
    { key: 'bp_systolic', label: 'BP Systolic', unit: 'mmHg', type: 'number' },
    { key: 'bp_diastolic', label: 'BP Diastolic', unit: 'mmHg', type: 'number' },
    { key: 'heart_rate', label: 'Heart Rate', unit: 'bpm', type: 'number' },
    { key: 'respiratory_rate', label: 'Resp. Rate', unit: '/min', type: 'number' },
    { key: 'temperature', label: 'Temperature', unit: '°C', type: 'number', step: '0.1' },
    { key: 'weight', label: 'Weight', unit: 'kg', type: 'number', step: '0.1' },
    { key: 'height', label: 'Height', unit: 'cm', type: 'number', step: '0.1' },
    { key: 'oxygen_sat', label: 'O₂ Sat', unit: '%', type: 'number' }
  ];

  const PE_SECTIONS = [
    { key: 'general', label: 'General Appearance' },
    { key: 'heent', label: 'HEENT (Head, Eyes, Ears, Nose, Throat)' },
    { key: 'chest', label: 'Chest / Lungs' },
    { key: 'cardiovascular', label: 'Cardiovascular' },
    { key: 'abdomen', label: 'Abdomen' },
    { key: 'extremities', label: 'Extremities' },
    { key: 'neurological', label: 'Neurological' },
    { key: 'skin', label: 'Skin / Integumentary' }
  ];

  function collectVitals() {
    const vitals = {};
    VITAL_FIELDS.forEach(f => {
      const el = $(`vital-${f.key}`);
      if (el && el.value.trim()) vitals[f.key] = parseFloat(el.value) || el.value.trim();
    });
    return Object.keys(vitals).length ? vitals : null;
  }

  function collectPE() {
    const pe = {};
    PE_SECTIONS.forEach(s => {
      const el = $(`pe-${s.key}`);
      if (el && el.value.trim()) pe[s.key] = el.value.trim();
    });
    return Object.keys(pe).length ? pe : null;
  }

  function collectLabRequests() {
    const rows = $$('.lab-request-row');
    const labs = [];
    rows.forEach(row => {
      const name = row.querySelector('.lab-test-name');
      if (name && name.value.trim()) {
        labs.push({ test_name: name.value.trim(), status: 'requested', result: null });
      }
    });
    return labs.length ? labs : null;
  }

  // Open enhanced consultation
  if (openEnhancedConsultBtn && enhancedConsultModal) {
    openEnhancedConsultBtn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      // Pre-fill from queue if a serving patient exists
      enhancedConsultModal.classList.remove('hidden');
      enhancedConsultForm?.reset();
      // Clear lab request rows except the first
      const labContainer = $('lab-requests-container');
      if (labContainer) {
        const rows = labContainer.querySelectorAll('.lab-request-row');
        rows.forEach((r, i) => { if (i > 0) r.remove(); });
      }
    });
  }

  // Close enhanced consultation modal
  const closeEnhancedConsultBtn = $('enhanced-consult-cancel-btn');
  if (closeEnhancedConsultBtn) {
    closeEnhancedConsultBtn.addEventListener('click', () => {
      if (enhancedConsultModal) enhancedConsultModal.classList.add('hidden');
    });
  }
  if (enhancedConsultModal) {
    enhancedConsultModal.addEventListener('click', (e) => {
      if (e.target === enhancedConsultModal) enhancedConsultModal.classList.add('hidden');
    });
  }

  // Add lab request row
  const addLabBtn = $('add-lab-request-btn');
  if (addLabBtn) {
    addLabBtn.addEventListener('click', () => {
      const container = $('lab-requests-container');
      if (!container) return;
      const row = document.createElement('div');
      row.className = 'lab-request-row field-row';
      row.innerHTML = `
        <input class="lab-test-name" type="text" placeholder="e.g., CBC, Urinalysis, X-Ray" />
        <button type="button" class="btn-icon remove-lab-btn" title="Remove">×</button>
      `;
      row.querySelector('.remove-lab-btn').addEventListener('click', () => row.remove());
      container.appendChild(row);
    });
  }

  // PE accordion
  $$('.pe-accordion-header').forEach(header => {
    header.addEventListener('click', () => {
      const body = header.nextElementSibling;
      const isOpen = header.classList.toggle('open');
      if (body) body.classList.toggle('hidden', !isOpen);
    });
  });

  // Submit enhanced consultation
  if (enhancedConsultForm) {
    enhancedConsultForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const submitBtn = enhancedConsultForm.querySelector('button[type="submit"]');
      if (submitBtn) submitBtn.disabled = true;

      try {
        const patientId = $('enh-consult-patient-id')?.value?.trim();
        const chiefComplaint = $('enh-consult-chief-complaint')?.value?.trim();
        const diagnosis = $('enh-consult-diagnosis')?.value?.trim();

        if (!patientId) { toast('Patient ID is required.', 'error'); return; }
        if (!chiefComplaint) { toast('Chief complaint is required.', 'error'); return; }

        // Resolve citizen ID
        let citizenId = null;
        const cidMatch = /^CIT-(\d+)$/i.exec(patientId);
        if (cidMatch) citizenId = parseInt(cidMatch[1]);
        else if (/^\d+$/.test(patientId)) citizenId = parseInt(patientId);

        const payload = {
          p_patient_citizen_id: citizenId,
          p_patient_identifier: patientId,
          p_chief_complaint: chiefComplaint,
          p_symptoms: $('enh-consult-symptoms')?.value?.trim() || null,
          p_history_of_present_illness: $('enh-consult-hpi')?.value?.trim() || null,
          p_vital_signs: collectVitals(),
          p_physical_examination: collectPE(),
          p_diagnosis: diagnosis || 'Pending',
          p_notes: $('enh-consult-notes')?.value?.trim() || null,
          p_lab_requests: collectLabRequests(),
          p_follow_up_date: $('enh-consult-followup-date')?.value || null,
          p_follow_up_notes: $('enh-consult-followup-notes')?.value?.trim() || null,
          p_consultation_status: 'completed'
        };

        const supabase = await getSupabase();
        const { data, error } = await supabase.rpc('save_consultation_with_vitals', payload);

        if (error) throw new Error(error.message);
        if (data && data.error) throw new Error(data.error);

        toast('Consultation saved successfully.', 'success');
        enhancedConsultModal.classList.add('hidden');

        // Check if Save & Prescribe was clicked
        const nextAction = e.submitter?.dataset?.next;
        if (nextAction === 'prescribe' && data?.consultation_id) {
          openPrescriptionFromConsultation(data.consultation_id, patientId);
        }

        // Refresh consultation list
        if (typeof window.refreshConsultationData === 'function') {
          window.refreshConsultationData();
        }
      } catch (err) {
        toast(err.message || 'Failed to save consultation.', 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /*  PATIENT HISTORY TIMELINE                                          */
  /* ------------------------------------------------------------------ */

  async function loadPatientHistory(citizenId) {
    const container = $('patient-history-timeline');
    if (!container) return;

    container.innerHTML = '<p class="timeline-loading">Loading patient history...</p>';

    try {
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('get_patient_consultation_history', {
        p_citizen_id: citizenId
      });

      if (error) throw error;
      if (!data || !data.length) {
        container.innerHTML = '<p class="timeline-empty">No previous consultations found.</p>';
        return;
      }

      container.innerHTML = '';
      data.forEach(c => {
        const card = document.createElement('div');
        card.className = 'timeline-card';
        const vitalsHtml = c.vital_signs ? renderVitalsCompact(c.vital_signs) : '';
        card.innerHTML = `
          <div class="timeline-date">${formatDate(c.consulted_at)}</div>
          <div class="timeline-content">
            <div class="timeline-doctor">Dr. ${escapeHtml(c.doctor_name)} ${c.doctor_specialization ? `(${escapeHtml(c.doctor_specialization)})` : ''}</div>
            ${c.chief_complaint ? `<div class="timeline-complaint"><strong>Chief Complaint:</strong> ${escapeHtml(c.chief_complaint)}</div>` : ''}
            ${c.diagnosis ? `<div class="timeline-diagnosis"><strong>Diagnosis:</strong> ${escapeHtml(c.diagnosis)}</div>` : ''}
            ${vitalsHtml}
            ${c.prescription_count > 0 ? `<div class="timeline-rx"><span class="rx-badge">${c.prescription_count} Rx</span></div>` : ''}
            ${c.follow_up_date ? `<div class="timeline-followup"><strong>Follow-up:</strong> ${formatDate(c.follow_up_date)}</div>` : ''}
          </div>
        `;
        container.appendChild(card);
      });
    } catch (err) {
      container.innerHTML = '<p class="timeline-error">Failed to load patient history.</p>';
    }
  }

  function renderVitalsCompact(vitals) {
    if (!vitals) return '';
    const items = [];
    if (vitals.bp_systolic && vitals.bp_diastolic) items.push(`BP: ${vitals.bp_systolic}/${vitals.bp_diastolic}`);
    if (vitals.heart_rate) items.push(`HR: ${vitals.heart_rate}`);
    if (vitals.temperature) items.push(`Temp: ${vitals.temperature}°C`);
    if (vitals.respiratory_rate) items.push(`RR: ${vitals.respiratory_rate}`);
    if (vitals.oxygen_sat) items.push(`O₂: ${vitals.oxygen_sat}%`);
    if (!items.length) return '';
    return `<div class="timeline-vitals">${items.map(i => `<span class="vital-chip">${i}</span>`).join('')}</div>`;
  }

  // When patient ID changes in enhanced consultation, load history
  const enhPatientIdInput = $('enh-consult-patient-id');
  if (enhPatientIdInput) {
    let historyDebounce = null;
    enhPatientIdInput.addEventListener('input', () => {
      clearTimeout(historyDebounce);
      historyDebounce = setTimeout(() => {
        const val = enhPatientIdInput.value.trim();
        let cid = null;
        const m = /^CIT-(\d+)$/i.exec(val);
        if (m) cid = parseInt(m[1]);
        else if (/^\d+$/.test(val)) cid = parseInt(val);
        if (cid) loadPatientHistory(cid);
      }, 600);
    });
  }

  /* ------------------------------------------------------------------ */
  /*  PRESCRIPTION SAFETY CHECKS                                        */
  /* ------------------------------------------------------------------ */

  async function checkPrescriptionSafety(citizenId, medicineNames) {
    try {
      const supabase = await getSupabase();
      const { data, error } = await supabase.rpc('check_prescription_safety', {
        p_citizen_id: citizenId,
        p_medicine_names: medicineNames
      });
      if (error) throw error;
      return data;
    } catch (err) {
      console.warn('Prescription safety check failed:', err);
      return { ok: false, warnings: [], has_critical: false };
    }
  }

  function displaySafetyWarnings(warnings) {
    const container = $('prescription-safety-warnings');
    if (!container) return;

    if (!warnings || !warnings.length) {
      container.innerHTML = '';
      container.classList.add('hidden');
      return;
    }

    container.classList.remove('hidden');
    container.innerHTML = warnings.map(w => {
      const icon = w.severity === 'high' ? '⚠️' : 'ℹ️';
      const cls = w.severity === 'high' ? 'safety-warning-critical' : 'safety-warning-info';
      return `<div class="safety-warning ${cls}">${icon} ${escapeHtml(w.message)}</div>`;
    }).join('');
  }

  function openPrescriptionFromConsultation(consultationId, patientId) {
    const prescriptionModal = $('prescription-modal');
    const prescriptionPatientInput = $('prescription-patient');
    if (prescriptionModal && prescriptionPatientInput) {
      prescriptionPatientInput.value = patientId || '';
      prescriptionPatientInput.dataset.consultationId = consultationId || '';
      prescriptionModal.classList.remove('hidden');
    }
  }

  /* ------------------------------------------------------------------ */
  /*  ENHANCED INVENTORY                                                */
  /* ------------------------------------------------------------------ */

  // Restock modal
  const restockModal = $('restock-modal');
  const restockForm = $('restock-form');

  function openRestockModal(medicineId, medicineName) {
    if (!restockModal) return;
    $('restock-medicine-id').value = medicineId;
    $('restock-medicine-name').textContent = medicineName;
    restockForm?.reset();
    $('restock-medicine-id').value = medicineId; // re-set after reset
    restockModal.classList.remove('hidden');
  }

  if (restockForm) {
    restockForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const submitBtn = restockForm.querySelector('button[type="submit"]');
      if (submitBtn) submitBtn.disabled = true;

      try {
        const medId = parseInt($('restock-medicine-id')?.value);
        const qty = parseInt($('restock-qty')?.value);
        if (!medId || !qty || qty <= 0) { toast('Valid quantity required.', 'error'); return; }

        const supabase = await getSupabase();
        const { data, error } = await supabase.rpc('restock_medicine', {
          p_medicine_id: medId,
          p_qty_added: qty,
          p_supplier_name: $('restock-supplier')?.value?.trim() || null,
          p_supplier_contact: $('restock-supplier-contact')?.value?.trim() || null,
          p_batch_number: $('restock-batch')?.value?.trim() || null,
          p_expiration_date: $('restock-expiry')?.value || null,
          p_unit_cost: parseFloat($('restock-unit-cost')?.value) || null,
          p_notes: $('restock-notes')?.value?.trim() || null
        });

        if (error) throw new Error(error.message);
        if (data?.error) throw new Error(data.error);

        toast(`Restocked successfully. New quantity: ${data?.new_qty}`, 'success');
        restockModal.classList.add('hidden');
        if (typeof window.refreshMedicineData === 'function') window.refreshMedicineData();
        loadInventoryAlerts();
      } catch (err) {
        toast(err.message || 'Restock failed.', 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }

  const restockCancelBtn = $('restock-cancel-btn');
  if (restockCancelBtn) {
    restockCancelBtn.addEventListener('click', () => restockModal?.classList.add('hidden'));
  }

  // Inventory alerts
  async function loadInventoryAlerts() {
    try {
      const supabase = await getSupabase();
      const [lowStockRes, expiringRes] = await Promise.all([
        supabase.rpc('get_low_stock_medicines'),
        supabase.rpc('get_expiring_medicines', { p_days_ahead: 90 })
      ]);

      const lowStockData = lowStockRes?.data || [];
      const expiringData = expiringRes?.data || [];

      renderInventoryAlerts(lowStockData, expiringData);
    } catch (err) {
      console.warn('Failed to load inventory alerts:', err);
    }
  }

  function renderInventoryAlerts(lowStock, expiring) {
    const container = $('inventory-alerts-container');
    if (!container) return;

    if (!lowStock.length && !expiring.length) {
      container.innerHTML = '<p class="alert-empty">✅ All inventory levels are normal.</p>';
      return;
    }

    let html = '';

    if (lowStock.length) {
      html += `<div class="alert-section alert-low-stock">
        <h4>⚠️ Low Stock (${lowStock.length} items)</h4>
        <div class="alert-items">${lowStock.map(m => `
          <div class="alert-item">
            <span class="alert-item-name">${escapeHtml(m.name)}</span>
            <span class="alert-item-qty qty-critical">${m.qty} / ${m.reorder_level}</span>
            <button type="button" class="btn-restock-alert chip-btn" data-id="${m.id}" data-name="${escapeHtml(m.name)}">Restock</button>
          </div>
        `).join('')}</div>
      </div>`;
    }

    if (expiring.length) {
      html += `<div class="alert-section alert-expiring">
        <h4>🕐 Expiring Soon (${expiring.length} items)</h4>
        <div class="alert-items">${expiring.map(m => {
          const daysLeft = m.days_until_expiry;
          const urgency = daysLeft <= 0 ? 'expired' : daysLeft <= 30 ? 'urgent' : 'warning';
          return `
            <div class="alert-item alert-${urgency}">
              <span class="alert-item-name">${escapeHtml(m.name)}</span>
              <span class="alert-item-expiry">${daysLeft <= 0 ? 'EXPIRED' : `${daysLeft} days left`}</span>
              <span class="alert-item-date">${formatDate(m.expiration_date)}</span>
            </div>
          `;
        }).join('')}</div>
      </div>`;
    }

    container.innerHTML = html;

    // Attach restock buttons
    container.querySelectorAll('.btn-restock-alert').forEach(btn => {
      btn.addEventListener('click', () => {
        openRestockModal(parseInt(btn.dataset.id), btn.dataset.name);
      });
    });
  }

  // Restock button delegation on medicine table
  document.addEventListener('click', (e) => {
    const restockBtn = e.target.closest('[data-action="restock"]');
    if (restockBtn) {
      e.preventDefault();
      openRestockModal(parseInt(restockBtn.dataset.id), restockBtn.dataset.name);
    }
  });

  /* ------------------------------------------------------------------ */
  /*  ANALYTICS DASHBOARD                                               */
  /* ------------------------------------------------------------------ */

  let chartJsLoaded = false;

  async function ensureChartJs() {
    if (chartJsLoaded) return;
    return new Promise((resolve, reject) => {
      if (window.Chart) { chartJsLoaded = true; resolve(); return; }
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js';
      script.onload = () => { chartJsLoaded = true; resolve(); };
      script.onerror = () => reject(new Error('Failed to load Chart.js'));
      document.head.appendChild(script);
    });
  }

  const analyticsDateFrom = $('analytics-date-from');
  const analyticsDateTo = $('analytics-date-to');
  const analyticsRefreshBtn = $('analytics-refresh-btn');
  const analyticsExportBtn = $('analytics-export-btn');

  // Set default date range (last 30 days)
  if (analyticsDateFrom) {
    const from = new Date();
    from.setDate(from.getDate() - 30);
    analyticsDateFrom.value = from.toISOString().slice(0, 10);
  }
  if (analyticsDateTo) {
    analyticsDateTo.value = new Date().toISOString().slice(0, 10);
  }

  if (analyticsRefreshBtn) {
    analyticsRefreshBtn.addEventListener('click', () => refreshAnalytics());
  }

  if (analyticsExportBtn) {
    analyticsExportBtn.addEventListener('click', () => exportAnalyticsCSV());
  }

  let cachedPatientStats = null;
  let cachedInventoryReport = null;
  let cachedFinancialSummary = null;
  let analyticsCharts = {};

  async function refreshAnalytics() {
    const dateFrom = analyticsDateFrom?.value || null;
    const dateTo = analyticsDateTo?.value || null;

    toast('Loading analytics...', 'info');

    try {
      await ensureChartJs();
      const supabase = await getSupabase();

      const [patientRes, inventoryRes, financialRes, consultAnalyticsRes] = await Promise.all([
        supabase.rpc('get_patient_statistics', { p_date_from: dateFrom, p_date_to: dateTo }),
        supabase.rpc('get_inventory_report'),
        supabase.rpc('get_financial_summary', { p_date_from: dateFrom, p_date_to: dateTo }),
        supabase.rpc('get_consultation_analytics', { p_date_from: dateFrom, p_date_to: dateTo })
      ]);

      cachedPatientStats = patientRes?.data || {};
      cachedInventoryReport = inventoryRes?.data || {};
      cachedFinancialSummary = financialRes?.data || {};
      const consultAnalytics = consultAnalyticsRes?.data || {};

      renderPatientStats(cachedPatientStats);
      renderInventoryStats(cachedInventoryReport);
      renderFinancialStats(cachedFinancialSummary);
      renderConsultationAnalytics(consultAnalytics);
      renderFollowUpsDue(consultAnalytics.follow_ups_due || []);

      toast('Analytics updated.', 'success');
    } catch (err) {
      toast('Failed to load analytics: ' + (err.message || ''), 'error');
    }
  }

  function destroyChart(key) {
    if (analyticsCharts[key]) { analyticsCharts[key].destroy(); delete analyticsCharts[key]; }
  }

  function renderPatientStats(stats) {
    // Summary cards
    const totalEl = $('analytics-total-consultations');
    const uniqueEl = $('analytics-unique-patients');
    const todayEl = $('analytics-today-consultations');
    if (totalEl) totalEl.textContent = stats.total_consultations || 0;
    if (uniqueEl) uniqueEl.textContent = stats.unique_patients || 0;
    if (todayEl) todayEl.textContent = stats.today_consultations || 0;

    // Gender pie chart
    const genderCanvas = $('chart-gender');
    if (genderCanvas && window.Chart) {
      destroyChart('gender');
      const genders = stats.gender_distribution || [];
      analyticsCharts.gender = new Chart(genderCanvas, {
        type: 'doughnut',
        data: {
          labels: genders.map(g => g.gender),
          datasets: [{
            data: genders.map(g => g.count),
            backgroundColor: ['#6366f1', '#ec4899', '#8b5cf6', '#94a3b8'],
            borderWidth: 0
          }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
      });
    }

    // Age group bar chart
    const ageCanvas = $('chart-age-groups');
    if (ageCanvas && window.Chart) {
      destroyChart('ageGroups');
      const ages = stats.age_groups || [];
      analyticsCharts.ageGroups = new Chart(ageCanvas, {
        type: 'bar',
        data: {
          labels: ages.map(a => a.age_group),
          datasets: [{
            label: 'Patients',
            data: ages.map(a => a.count),
            backgroundColor: '#6366f1',
            borderRadius: 6
          }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
      });
    }

    // Top diagnoses
    const diagCanvas = $('chart-diagnoses');
    if (diagCanvas && window.Chart) {
      destroyChart('diagnoses');
      const diags = (stats.top_diagnoses || []).slice(0, 8);
      analyticsCharts.diagnoses = new Chart(diagCanvas, {
        type: 'bar',
        data: {
          labels: diags.map(d => d.diagnosis.length > 25 ? d.diagnosis.slice(0, 25) + '...' : d.diagnosis),
          datasets: [{
            label: 'Cases',
            data: diags.map(d => d.count),
            backgroundColor: '#0ea5e9',
            borderRadius: 6
          }]
        },
        options: {
          indexAxis: 'y',
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: { x: { beginAtZero: true } }
        }
      });
    }

    // Daily consultation trend
    const dailyCanvas = $('chart-daily-consultations');
    if (dailyCanvas && window.Chart) {
      destroyChart('dailyConsultations');
      const daily = stats.daily_counts || [];
      analyticsCharts.dailyConsultations = new Chart(dailyCanvas, {
        type: 'line',
        data: {
          labels: daily.map(d => formatDate(d.date)),
          datasets: [{
            label: 'Consultations',
            data: daily.map(d => d.count),
            borderColor: '#6366f1',
            backgroundColor: 'rgba(99, 102, 241, 0.1)',
            fill: true,
            tension: 0.3,
            pointRadius: 3
          }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
      });
    }
  }

  function renderInventoryStats(report) {
    const totalMedEl = $('analytics-total-medicines');
    const totalStockEl = $('analytics-total-stock');
    const lowStockEl = $('analytics-low-stock');
    const expiringEl = $('analytics-expiring');
    const expiredEl = $('analytics-expired');

    if (totalMedEl) totalMedEl.textContent = report.total_medicines || 0;
    if (totalStockEl) totalStockEl.textContent = report.total_stock || 0;
    if (lowStockEl) lowStockEl.textContent = report.low_stock_count || 0;
    if (expiringEl) expiringEl.textContent = report.expiring_count || 0;
    if (expiredEl) expiredEl.textContent = report.expired_count || 0;

    // Category breakdown chart
    const catCanvas = $('chart-inventory-categories');
    if (catCanvas && window.Chart) {
      destroyChart('inventoryCategories');
      const cats = report.category_breakdown || [];
      analyticsCharts.inventoryCategories = new Chart(catCanvas, {
        type: 'doughnut',
        data: {
          labels: cats.map(c => c.category),
          datasets: [{
            data: cats.map(c => c.total_qty),
            backgroundColor: ['#6366f1', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6'],
            borderWidth: 0
          }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom' } } }
      });
    }
  }

  function renderFinancialStats(summary) {
    const incomeEl = $('analytics-total-income');
    const expenseEl = $('analytics-total-expense');
    const netEl = $('analytics-net-income');

    if (incomeEl) incomeEl.textContent = '₱' + Number(summary.total_income || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
    if (expenseEl) expenseEl.textContent = '₱' + Number(summary.total_expense || 0).toLocaleString('en-PH', { minimumFractionDigits: 2 });
    if (netEl) {
      const net = Number(summary.net_income || 0);
      netEl.textContent = '₱' + Math.abs(net).toLocaleString('en-PH', { minimumFractionDigits: 2 });
      netEl.classList.toggle('positive', net >= 0);
      netEl.classList.toggle('negative', net < 0);
    }

    // Income vs Expense chart
    const finCanvas = $('chart-financials');
    if (finCanvas && window.Chart) {
      destroyChart('financials');
      const daily = summary.daily_breakdown || [];
      analyticsCharts.financials = new Chart(finCanvas, {
        type: 'bar',
        data: {
          labels: daily.map(d => formatDate(d.date)),
          datasets: [
            { label: 'Income', data: daily.map(d => d.income), backgroundColor: '#10b981', borderRadius: 4 },
            { label: 'Expense', data: daily.map(d => d.expense), backgroundColor: '#ef4444', borderRadius: 4 }
          ]
        },
        options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true } } }
      });
    }
  }

  function renderConsultationAnalytics(analytics) {
    const byDoctorEl = $('analytics-by-doctor');
    if (byDoctorEl) {
      const doctors = analytics.by_doctor || [];
      if (doctors.length === 0) {
        byDoctorEl.innerHTML = '<p class="note">No consultation data for this period.</p>';
        return;
      }
      byDoctorEl.innerHTML = `<table class="accounts-table compact-table">
        <thead><tr><th>Doctor</th><th>Specialization</th><th>Consultations</th></tr></thead>
        <tbody>${doctors.map(d => `<tr>
          <td>${escapeHtml(d.doctor_name)}</td>
          <td>${escapeHtml(d.specialization || '—')}</td>
          <td><strong>${d.consultation_count}</strong></td>
        </tr>`).join('')}</tbody>
      </table>`;
    }
  }

  function renderFollowUpsDue(followUps) {
    const container = $('analytics-follow-ups');
    if (!container) return;

    if (!followUps.length) {
      container.innerHTML = '<p class="note">No follow-ups due in the next 14 days.</p>';
      return;
    }

    container.innerHTML = `<table class="accounts-table compact-table">
      <thead><tr><th>Patient</th><th>Reason</th><th>Follow-up Date</th><th>Doctor</th></tr></thead>
      <tbody>${followUps.map(f => `<tr>
        <td>${escapeHtml(f.patient_name)}</td>
        <td>${escapeHtml(f.reason || '—')}</td>
        <td><strong>${formatDate(f.follow_up_date)}</strong></td>
        <td>${escapeHtml(f.doctor_name)}</td>
      </tr>`).join('')}</tbody>
    </table>`;
  }

  /* ------------------------------------------------------------------ */
  /*  CSV EXPORT                                                        */
  /* ------------------------------------------------------------------ */

  function exportAnalyticsCSV() {
    if (!cachedPatientStats) { toast('Load analytics data first.', 'warning'); return; }

    const rows = [['Analytics Export', new Date().toISOString()], []];

    // Patient stats
    rows.push(['--- Patient Statistics ---']);
    rows.push(['Total Consultations', cachedPatientStats.total_consultations || 0]);
    rows.push(['Unique Patients', cachedPatientStats.unique_patients || 0]);
    rows.push(['Today', cachedPatientStats.today_consultations || 0]);
    rows.push([]);

    rows.push(['Gender Distribution']);
    (cachedPatientStats.gender_distribution || []).forEach(g => rows.push([g.gender, g.count]));
    rows.push([]);

    rows.push(['Age Groups']);
    (cachedPatientStats.age_groups || []).forEach(a => rows.push([a.age_group, a.count]));
    rows.push([]);

    rows.push(['Top Diagnoses']);
    (cachedPatientStats.top_diagnoses || []).forEach(d => rows.push([d.diagnosis, d.count]));
    rows.push([]);

    // Inventory
    if (cachedInventoryReport) {
      rows.push(['--- Inventory Report ---']);
      rows.push(['Total Medicines', cachedInventoryReport.total_medicines || 0]);
      rows.push(['Total Stock', cachedInventoryReport.total_stock || 0]);
      rows.push(['Low Stock', cachedInventoryReport.low_stock_count || 0]);
      rows.push(['Expiring Soon', cachedInventoryReport.expiring_count || 0]);
      rows.push([]);
    }

    // Financial
    if (cachedFinancialSummary) {
      rows.push(['--- Financial Summary ---']);
      rows.push(['Total Income', cachedFinancialSummary.total_income || 0]);
      rows.push(['Total Expense', cachedFinancialSummary.total_expense || 0]);
      rows.push(['Net Income', cachedFinancialSummary.net_income || 0]);
      rows.push([]);
    }

    const csv = rows.map(r => r.map(c => `"${String(c || '').replace(/"/g, '""')}"`).join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ukonek-analytics-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    toast('Analytics exported to CSV.', 'success');
  }

  /* ------------------------------------------------------------------ */
  /*  FINANCIAL TRANSACTION ENTRY                                       */
  /* ------------------------------------------------------------------ */

  const transactionModal = $('transaction-modal');
  const transactionForm = $('transaction-form');
  const addTransactionBtn = $('add-transaction-btn');
  const transactionCancelBtn = $('transaction-cancel-btn');

  if (addTransactionBtn && transactionModal) {
    addTransactionBtn.addEventListener('click', () => {
      transactionForm?.reset();
      transactionModal.classList.remove('hidden');
    });
  }
  if (transactionCancelBtn) {
    transactionCancelBtn.addEventListener('click', () => transactionModal?.classList.add('hidden'));
  }

  if (transactionForm) {
    transactionForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = transactionForm.querySelector('button[type="submit"]');
      if (btn) btn.disabled = true;

      try {
        const supabase = await getSupabase();
        const { error } = await supabase.from('clinic_transactions').insert({
          transaction_type: $('txn-type')?.value,
          category: $('txn-category')?.value?.trim(),
          amount: parseFloat($('txn-amount')?.value) || 0,
          description: $('txn-description')?.value?.trim() || null,
          transaction_date: $('txn-date')?.value || new Date().toISOString().slice(0, 10)
        });

        if (error) throw new Error(error.message);
        toast('Transaction recorded.', 'success');
        transactionModal.classList.add('hidden');
        refreshAnalytics();
      } catch (err) {
        toast(err.message || 'Failed to record transaction.', 'error');
      } finally {
        if (btn) btn.disabled = false;
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /*  SECTION INITIALIZATION HOOKS                                      */
  /* ------------------------------------------------------------------ */

  // Hook into section navigation to trigger analytics load
  const origShowSection = window.showSection;
  if (typeof origShowSection === 'function') {
    // The showSection is async in dashboard.js, we augment it
    const sectionObserver = new MutationObserver((mutations) => {
      mutations.forEach(m => {
        if (m.target.id === 'analytics-section' && !m.target.classList.contains('hidden')) {
          refreshAnalytics();
        }
        if (m.target.id === 'medicine-section' && !m.target.classList.contains('hidden')) {
          loadInventoryAlerts();
        }
      });
    });

    const sections = ['analytics-section', 'medicine-section'];
    sections.forEach(sId => {
      const el = $(sId);
      if (el) sectionObserver.observe(el, { attributes: true, attributeFilter: ['class'] });
    });
  }

  // Expose functions globally
  window.openRestockModal = openRestockModal;
  window.checkPrescriptionSafety = checkPrescriptionSafety;
  window.displaySafetyWarnings = displaySafetyWarnings;
  window.loadInventoryAlerts = loadInventoryAlerts;
  window.refreshAnalytics = refreshAnalytics;
  window.loadPatientHistory = loadPatientHistory;

})();
