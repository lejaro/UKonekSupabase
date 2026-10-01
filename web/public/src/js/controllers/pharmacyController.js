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
    if (tbody) tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:24px; color:#94a3b8;">No medicines registered.</td></tr>';
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

  const filtered = medicines.filter((m) => {
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

  const sortSelect = document.getElementById('medicine-sort-select');
  const sortVal = sortSelect?.value || 'name-asc';

  filtered.sort((a, b) => {
    const nameA = String(a.name || a.brand_name || '').toLowerCase();
    const nameB = String(b.name || b.brand_name || '').toLowerCase();
    const qtyA = Number(a.qty ?? 0);
    const qtyB = Number(b.qty ?? 0);
    const expA = a.expiry_date ? new Date(a.expiry_date).getTime() : Infinity;
    const expB = b.expiry_date ? new Date(b.expiry_date).getTime() : Infinity;

    switch (sortVal) {
      case 'name-asc':
        return nameA.localeCompare(nameB);
      case 'name-desc':
        return nameB.localeCompare(nameA);
      case 'stock-desc':
        return qtyB - qtyA;
      case 'stock-asc':
        return qtyA - qtyB;
      case 'expiry-asc':
        return expA - expB;
      case 'expiry-desc':
        return (expB === Infinity ? -Infinity : expB) - (expA === Infinity ? -Infinity : expA);
      default:
        return nameA.localeCompare(nameB);
    }
  });

  return filtered;
}

export function renderMedicines() {
  const tbody = document.getElementById('medicine-tbody');
  if (!tbody) return;

  const filtered = getFilteredMedicines();

  if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:28px; color:#94a3b8;">No medicines matching criteria found.</td></tr>';
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
      <tr style="cursor: pointer;">
        <td class="table-cell">
          <strong style="color:#0f172a;">${sanitizeText(name)}</strong>
        </td>
        <td class="table-cell" style="color:#475569;">${sanitizeText(generic)}</td>
        <td class="table-cell"><strong>${qty}</strong> <span style="font-size:12px; color:#64748b;">${sanitizeText(unit)}</span></td>
        <td class="table-cell">${statusBadge}</td>
        <td class="table-cell" style="color:#64748b; font-size:12.5px;">${sanitizeText(expiry)}</td>
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

  // Sort dropdown
  const sortSelect = document.getElementById('medicine-sort-select');
  if (sortSelect && !sortSelect.dataset.bound) {
    sortSelect.dataset.bound = 'true';
    sortSelect.addEventListener('change', renderMedicines);
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
}

export const initPharmacyModule = initPharmacySection;
export const loadMedicinesCatalog = refreshMedicineData;
