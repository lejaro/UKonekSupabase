/**
 * Pharmacy & Medication Dispensing Controller
 * Manages medicine inventory catalog, stock levels, drug allergy checks,
 * prescription creation modal, CSV export, and PDF printable reporting.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as pharmacyService from '../services/pharmacyService.js';
import { showToast, swapContainer, renderTableSkeleton } from '../utils/uiHelpers.js';
import { attachDetailRow, sanitizeText } from '../utils/dataDetailModal.js';

export let medicines = [];
export let medicineActiveFilter = 'all';
export let showArchivedMedicines = false;

export async function refreshMedicineData() {
  const tbody = document.getElementById('medicine-tbody');
  if (tbody) renderTableSkeleton(tbody, 5, 5);

  try {
    const data = await pharmacyService.listMedicines({
      includeArchived: showArchivedMedicines,
      limit: 300
    });
    medicines = Array.isArray(data) ? data : [];
    renderMedicines();
    updateMedicineTelemetry();
  } catch (err) {
    console.warn('Error loading medicine catalog:', err);
    medicines = [];
    if (tbody) tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:24px; color:#94a3b8;">No medicines registered.</td></tr>';
  }
}

export function updateMedicineTelemetry() {
  const totalEl = document.getElementById('ph-stat-total');
  const instockEl = document.getElementById('ph-stat-instock');
  const lowstockEl = document.getElementById('ph-stat-low');
  const critEl = document.getElementById('ph-stat-out');

  const chipAll = document.getElementById('chip-count-all');
  const chipIn = document.getElementById('chip-count-instock');
  const chipLow = document.getElementById('chip-count-low');
  const chipOut = document.getElementById('chip-count-out');

  const total = medicines.length;
  const inStock = medicines.filter(m => (m.qty || 0) > 5).length;
  const lowStock = medicines.filter(m => (m.qty || 0) > 0 && (m.qty || 0) <= 5).length;
  const critical = medicines.filter(m => (m.qty || 0) === 0).length;

  if (totalEl) totalEl.textContent = String(total);
  if (instockEl) instockEl.textContent = String(inStock);
  if (lowstockEl) lowstockEl.textContent = String(lowStock);
  if (critEl) critEl.textContent = String(critical);

  if (chipAll) chipAll.textContent = String(total);
  if (chipIn) chipIn.textContent = String(inStock);
  if (chipLow) chipLow.textContent = String(lowStock);
  if (chipOut) chipOut.textContent = String(critical);
}

export function getFilteredMedicines() {
  const searchInput = document.getElementById('medicine-search-input');
  const query = String(searchInput?.value || '').trim().toLowerCase();

  return medicines.filter((m) => {
    const name = String(m.name || m.brand_name || '').toLowerCase();
    const desc = String(m.description || m.generic_name || '').toLowerCase();
    const matchesQuery = !query || name.includes(query) || desc.includes(query);

    const qty = Number(m.qty || 0);
    let matchesFilter = true;
    if (medicineActiveFilter === 'in_stock' || medicineActiveFilter === 'instock') matchesFilter = qty > 5;
    else if (medicineActiveFilter === 'low_stock' || medicineActiveFilter === 'lowstock') matchesFilter = qty > 0 && qty <= 5;
    else if (medicineActiveFilter === 'out_of_stock' || medicineActiveFilter === 'critical') matchesFilter = qty === 0;

    return matchesQuery && matchesFilter;
  });
}

export function renderMedicines() {
  const tbody = document.getElementById('medicine-tbody');
  if (!tbody) return;

  const filtered = getFilteredMedicines();

  if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; padding:28px; color:#94a3b8;">No medicines matching criteria found.</td></tr>';
    return;
  }

  tbody.innerHTML = filtered.map((m) => {
    const name = m.name || m.brand_name || 'Medicine Item';
    const generic = m.generic_name || m.description || '—';
    const qty = Number(m.qty ?? 0);
    const unit = m.unit || 'units';
    const expiry = m.expiry_date ? new Date(m.expiry_date).toLocaleDateString() : '—';

    let statusBadge = '<span class="badge badge-success" style="background:#dcfce7; color:#166534; font-weight:600; padding:2px 8px; border-radius:9999px;">In Stock</span>';
    if (qty === 0) statusBadge = '<span class="badge badge-critical" style="background:#fee2e2; color:#991b1b; font-weight:600; padding:2px 8px; border-radius:9999px;">Out of Stock</span>';
    else if (qty <= 5) statusBadge = '<span class="badge badge-warning" style="background:#fef3c7; color:#92400e; font-weight:600; padding:2px 8px; border-radius:9999px;">Low Stock</span>';

    return `
      <tr>
        <td class="table-cell">
          <strong style="color:#0f172a;">${sanitizeText(name)}</strong>
          <div style="font-size:11px; color:#64748b;">${sanitizeText(generic)}</div>
        </td>
        <td class="table-cell">${sanitizeText(generic)}</td>
        <td class="table-cell"><strong>${qty}</strong> ${sanitizeText(unit)}</td>
        <td class="table-cell">${statusBadge}</td>
        <td class="table-cell">${sanitizeText(expiry)}</td>
        <td class="table-cell" style="text-align:right;">
          <button type="button" class="btn small outline" data-action="adjust-stock" data-name="${sanitizeText(name)}" style="padding:3px 10px; font-size:11px; border-radius:9999px;">Adjust</button>
        </td>
      </tr>
    `;
  }).join('');

  tbody.querySelectorAll('tr').forEach((tr, index) => {
    const m = filtered[index];
    if (!m) return;

    attachDetailRow(tr, () => ({
      tag: 'Medicine Formulary',
      title: m.name || m.brand_name || 'Medicine Detail',
      subtitle: m.generic_name ? `Generic: ${m.generic_name}` : '',
      items: [
        { label: 'Brand Name', value: m.brand_name || m.name || '—' },
        { label: 'Generic Name', value: m.generic_name || m.description || '—' },
        { label: 'Classification', value: (m.drug_classification || 'rx').toUpperCase() },
        { label: 'Dosage Form', value: m.dosage_form || m.unit || '—' },
        { label: 'Available Stock', value: `${m.qty || 0} units` },
        { label: 'Expiration Date', value: m.expiry_date ? new Date(m.expiry_date).toLocaleDateString() : '—' }
      ]
    }));
  });
}

export function exportMedicineCSV() {
  const list = getFilteredMedicines();
  if (!list || list.length === 0) {
    showToast('No medicine records matching criteria to export.', 'warning');
    return;
  }

  const headers = [
    'Medicine Name',
    'Classification',
    'Generic / Description',
    'Stock Quantity',
    'Unit',
    'Expiration Date',
    'Stock Status'
  ];

  const rows = [];
  rows.push(headers.join(','));

  list.forEach((m) => {
    const name = m.name || m.brand_name || '';
    const classification = (m.drug_classification || 'rx').toUpperCase();
    const generic = m.generic_name || m.description || '';
    const qty = Number(m.qty ?? 0);
    const unit = m.unit || 'units';
    const expiry = m.expiry_date ? new Date(m.expiry_date).toISOString().split('T')[0] : '';
    let status = 'In Stock';
    if (qty === 0) status = 'Out of Stock';
    else if (qty <= 5) status = 'Low Stock';

    const cols = [name, classification, generic, qty, unit, expiry, status];
    const escaped = cols.map(c => `"${String(c).replace(/"/g, '""')}"`);
    rows.push(escaped.join(','));
  });

  const csvContent = '\uFEFF' + rows.join('\r\n');
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.setAttribute('href', url);
  const todayStr = new Date().toISOString().split('T')[0];
  link.setAttribute('download', `Medicine_Inventory_Report_${todayStr}.csv`);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);

  showToast(`Medicine inventory exported successfully! (${list.length} items)`, 'success');
}

export function openMedicineReportModal() {
  const modal = document.getElementById('medicine-report-modal');
  const sheet = document.getElementById('medicine-printable-sheet');
  if (!modal || !sheet) return;

  const list = getFilteredMedicines();
  const user = sessionStore.getUser();
  const preparerName = [user?.firstname || user?.first_name, user?.surname || user?.last_name].filter(Boolean).join(' ') || user?.username || 'Pharmacist on Duty';
  const roleName = (user?.role || 'Pharmacist').toUpperCase();

  const now = new Date();
  const dateStr = now.toLocaleDateString('en-US', {
    timeZone: 'Asia/Manila',
    month: 'long',
    day: 'numeric',
    year: 'numeric'
  });
  const timeStr = now.toLocaleTimeString('en-US', {
    timeZone: 'Asia/Manila',
    hour: '2-digit',
    minute: '2-digit'
  });

  const inStockCount = list.filter(m => (m.qty || 0) > 5).length;
  const lowStockCount = list.filter(m => (m.qty || 0) > 0 && (m.qty || 0) <= 5).length;
  const outCount = list.filter(m => (m.qty || 0) === 0).length;

  let filterLabel = 'All Inventory Items';
  if (medicineActiveFilter === 'in_stock' || medicineActiveFilter === 'instock') filterLabel = 'In Stock Items';
  else if (medicineActiveFilter === 'low_stock' || medicineActiveFilter === 'lowstock') filterLabel = 'Low Stock Items (<= 5)';
  else if (medicineActiveFilter === 'out_of_stock' || medicineActiveFilter === 'critical') filterLabel = 'Out of Stock Items';

  const tableRowsHtml = list.map((m, idx) => {
    const name = m.name || m.brand_name || 'Item';
    const generic = m.generic_name || m.description || '—';
    const classification = (m.drug_classification || 'rx').toUpperCase();
    const qty = Number(m.qty ?? 0);
    const unit = m.unit || 'units';
    const expiry = m.expiry_date ? new Date(m.expiry_date).toLocaleDateString() : '—';

    let statusLabel = 'In Stock';
    let statusStyle = 'background:#dcfce7; color:#166534;';
    if (qty === 0) {
      statusLabel = 'Out of Stock';
      statusStyle = 'background:#fee2e2; color:#991b1b;';
    } else if (qty <= 5) {
      statusLabel = 'Low Stock';
      statusStyle = 'background:#fef3c7; color:#92400e;';
    }

    return `
      <tr>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center;">${idx + 1}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11.5px; font-weight:700; color:#0f172a;">${sanitizeText(name)}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11px; color:#475569;">${sanitizeText(generic)}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center;">${classification}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11.5px; font-weight:700; text-align:right;">${qty}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center;">${sanitizeText(unit)}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center;">${sanitizeText(expiry)}</td>
        <td style="padding:6px 8px; border:1px solid #cbd5e1; font-size:10.5px; text-align:center;">
          <span style="display:inline-block; padding:2px 7px; border-radius:9999px; font-weight:700; ${statusStyle}">${statusLabel}</span>
        </td>
      </tr>
    `;
  }).join('');

  sheet.innerHTML = `
    <div style="padding:32px 36px; color:#0f172a; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
      <!-- Letterhead Header -->
      <div style="text-align:center; border-bottom:2.5px solid #0284c7; padding-bottom:14px; margin-bottom:18px;">
        <div style="font-size:11px; font-weight:700; letter-spacing:1px; text-transform:uppercase; color:#0284c7; margin-bottom:2px;">Republic of the Philippines &bull; Department of Health Accredited</div>
        <h2 style="margin:0; font-size:22px; font-weight:800; color:#0f172a; text-transform:uppercase; letter-spacing:0.5px;">AFM Roquero Medical Clinic</h2>
        <div style="font-size:12px; color:#475569; margin:3px 0;">Poblacion Ward, City of San Jose del Monte, Bulacan &bull; Clinic License No. DOH-03-0491</div>
        <div style="margin-top:10px; font-size:16px; font-weight:800; color:#0284c7; text-transform:uppercase; letter-spacing:0.5px;">
          Pharmacy Formulary &amp; Stock Inventory Valuation Report
        </div>
      </div>

      <!-- Report Metadata Strip -->
      <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(140px, 1fr)); gap:10px; background:#f8fafc; border:1px solid #e2e8f0; border-radius:8px; padding:12px 16px; margin-bottom:18px; font-size:11.5px;">
        <div>
          <span style="color:#64748b; display:block; font-size:10px; text-transform:uppercase; font-weight:700;">Report Date &amp; Time</span>
          <strong style="color:#0f172a;">${dateStr}, ${timeStr}</strong>
        </div>
        <div>
          <span style="color:#64748b; display:block; font-size:10px; text-transform:uppercase; font-weight:700;">Prepared By</span>
          <strong style="color:#0f172a;">${sanitizeText(preparerName)} (${roleName})</strong>
        </div>
        <div>
          <span style="color:#64748b; display:block; font-size:10px; text-transform:uppercase; font-weight:700;">Scope / Active Filter</span>
          <strong style="color:#0f172a;">${filterLabel}</strong>
        </div>
        <div>
          <span style="color:#64748b; display:block; font-size:10px; text-transform:uppercase; font-weight:700;">Inventory Counts</span>
          <strong style="color:#0f172a;">${list.length} Items (${inStockCount} In Stock, ${lowStockCount} Low, ${outCount} Out)</strong>
        </div>
      </div>

      <!-- Inventory Table -->
      <table style="width:100%; border-collapse:collapse; margin-bottom:28px;">
        <thead>
          <tr style="background:#f1f5f9; color:#334155;">
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center; width:36px;">#</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:left;">Medicine Item</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:left;">Generic / Formulation</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center; width:55px;">Class</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:right; width:65px;">Qty</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center; width:55px;">Unit</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center; width:85px;">Expiry</th>
            <th style="padding:7px 8px; border:1px solid #cbd5e1; font-size:11px; text-align:center; width:95px;">Status</th>
          </tr>
        </thead>
        <tbody>
          ${tableRowsHtml || '<tr><td colspan="8" style="text-align:center; padding:20px; color:#94a3b8;">No items matching report criteria.</td></tr>'}
        </tbody>
      </table>

      <!-- Official Signatures -->
      <div style="display:flex; justify-content:space-between; align-items:flex-end; margin-top:36px; padding-top:16px; page-break-inside:avoid;">
        <div style="text-align:center; width:220px;">
          <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
          <div style="font-size:12px; font-weight:700;">Pharmacist-on-Duty</div>
          <div style="font-size:10.5px; color:#64748b;">Dispensary Custodian</div>
        </div>
        <div style="text-align:center; width:220px;">
          <div style="border-bottom:1px solid #0f172a; margin-bottom:4px;">&nbsp;</div>
          <div style="font-size:12px; font-weight:700;">Medical Director / Administrator</div>
          <div style="font-size:10.5px; color:#64748b;">Verified &amp; Approved</div>
        </div>
      </div>
    </div>
  `;

  modal.classList.remove('hidden');
}

export { openPrescriptionModalForPatient } from './prescriptionController.js';

export function openPrescriptionModal() {
  const modal = document.getElementById('prescription-modal');
  if (modal) modal.classList.remove('hidden');
}

export function closePrescriptionModal() {
  const modal = document.getElementById('prescription-modal');
  if (modal) modal.classList.add('hidden');
}

export async function checkPatientDrugAllergies(patientId, medicineName) {
  if (!patientId || !medicineName) return false;

  try {
    const { data: citizen, error } = await supabase
      .from('citizens')
      .select('allergies')
      .eq('id', patientId)
      .maybeSingle();

    if (error || !citizen || !citizen.allergies) return false;

    const patientAllergies = String(citizen.allergies).toLowerCase();
    const medLower = String(medicineName).toLowerCase();
    return patientAllergies.includes(medLower);
  } catch (_) {
    return false;
  }
}

export function initPharmacySection() {
  const rxCloseBtn = document.getElementById('prescription-modal-close');

  refreshMedicineData();

  if (rxCloseBtn && !rxCloseBtn.dataset.bound) {
    rxCloseBtn.dataset.bound = 'true';
    rxCloseBtn.addEventListener('click', closePrescriptionModal);
  }

  // Filter chips
  document.querySelectorAll('.ph-filter-chip').forEach((chip) => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        document.querySelectorAll('.ph-filter-chip').forEach(c => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        medicineActiveFilter = chip.getAttribute('data-filter') || 'all';
        renderMedicines();
      });
    }
  });

  // Search input
  const searchInput = document.getElementById('medicine-search-input');
  if (searchInput && !searchInput.dataset.bound) {
    searchInput.dataset.bound = 'true';
    searchInput.addEventListener('input', renderMedicines);
  }

  // CSV Export Button
  const csvBtn = document.getElementById('medicine-csv-export-btn');
  if (csvBtn && !csvBtn.dataset.bound) {
    csvBtn.dataset.bound = 'true';
    csvBtn.addEventListener('click', (e) => {
      e.preventDefault();
      exportMedicineCSV();
    });
  }

  // PDF Report Button
  const reportBtn = document.getElementById('medicine-report-btn');
  if (reportBtn && !reportBtn.dataset.bound) {
    reportBtn.dataset.bound = 'true';
    reportBtn.addEventListener('click', (e) => {
      e.preventDefault();
      openMedicineReportModal();
    });
  }

  // Show / Hide Archived Button
  const archivedBtn = document.getElementById('medicine-archived-toggle-btn');
  if (archivedBtn && !archivedBtn.dataset.bound) {
    archivedBtn.dataset.bound = 'true';
    archivedBtn.addEventListener('click', (e) => {
      e.preventDefault();
      showArchivedMedicines = !showArchivedMedicines;
      archivedBtn.classList.toggle('is-active', showArchivedMedicines);
      archivedBtn.innerHTML = `
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="21 8 21 21 3 21 3 8" />
          <rect x="1" y="3" width="22" height="5" />
          <line x1="10" y1="12" x2="14" y2="12" />
        </svg>
        ${showArchivedMedicines ? 'Hide Archived' : 'Show Archived'}
      `;
      refreshMedicineData();
    });
  }

  // Medicine Report Modal Buttons
  const modalClose = document.getElementById('medicine-modal-close-btn');
  const modalCancel = document.getElementById('medicine-modal-cancel-btn');
  const modalPrint = document.getElementById('medicine-modal-print-btn');
  const reportModal = document.getElementById('medicine-report-modal');

  const closeReportModal = () => {
    if (reportModal) reportModal.classList.add('hidden');
  };

  if (modalClose && !modalClose.dataset.bound) {
    modalClose.dataset.bound = 'true';
    modalClose.addEventListener('click', closeReportModal);
  }
  if (modalCancel && !modalCancel.dataset.bound) {
    modalCancel.dataset.bound = 'true';
    modalCancel.addEventListener('click', closeReportModal);
  }
  if (modalPrint && !modalPrint.dataset.bound) {
    modalPrint.dataset.bound = 'true';
    modalPrint.addEventListener('click', () => {
      window.print();
    });
  }
  if (reportModal && !reportModal.dataset.bound) {
    reportModal.dataset.bound = 'true';
    reportModal.addEventListener('click', (e) => {
      if (e.target === reportModal) closeReportModal();
    });
  }
}

export const initPharmacyModule = initPharmacySection;
export const loadMedicinesCatalog = refreshMedicineData;
