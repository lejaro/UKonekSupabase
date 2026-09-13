/**
 * Pharmacy & Medication Dispensing Controller
 * Manages medicine inventory catalog, stock levels, drug allergy checks,
 * prescription creation modal, and dispensing workflows.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as pharmacyService from '../services/pharmacyService.js';
import { showToast, swapContainer, renderTableSkeleton } from '../utils/uiHelpers.js';
import { attachDetailRow, sanitizeText } from '../utils/dataDetailModal.js';

export let medicines = [];
let medicineActiveFilter = 'all';

export async function refreshMedicineData() {
  const tbody = document.getElementById('medicine-tbody');
  if (tbody) renderTableSkeleton(tbody, 5, 5);

  try {
    const data = await pharmacyService.listMedicines({ limit: 200 });
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
  const lowstockEl = document.getElementById('ph-stat-lowstock');
  const critEl = document.getElementById('ph-stat-critical');

  const total = medicines.length;
  const inStock = medicines.filter(m => (m.qty || 0) > 20).length;
  const lowStock = medicines.filter(m => (m.qty || 0) > 0 && (m.qty || 0) <= 20).length;
  const critical = medicines.filter(m => (m.qty || 0) === 0).length;

  if (totalEl) totalEl.textContent = String(total);
  if (instockEl) instockEl.textContent = String(inStock);
  if (lowstockEl) lowstockEl.textContent = String(lowStock);
  if (critEl) critEl.textContent = String(critical);
}

export function renderMedicines() {
  const tbody = document.getElementById('medicine-tbody');
  if (!tbody) return;

  const searchInput = document.getElementById('medicine-search-input');
  const query = String(searchInput?.value || '').trim().toLowerCase();

  const filtered = medicines.filter((m) => {
    const name = String(m.name || m.brand_name || '').toLowerCase();
    const desc = String(m.description || m.generic_name || '').toLowerCase();
    const matchesQuery = !query || name.includes(query) || desc.includes(query);

    const qty = Number(m.qty || 0);
    let matchesFilter = true;
    if (medicineActiveFilter === 'instock') matchesFilter = qty > 20;
    else if (medicineActiveFilter === 'lowstock') matchesFilter = qty > 0 && qty <= 20;
    else if (medicineActiveFilter === 'critical') matchesFilter = qty === 0;

    return matchesQuery && matchesFilter;
  });

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

    let statusBadge = '<span class="badge badge-success">In Stock</span>';
    if (qty === 0) statusBadge = '<span class="badge badge-critical">Out of Stock</span>';
    else if (qty <= 20) statusBadge = '<span class="badge badge-warning">Low Stock</span>';

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

  if (rxCloseBtn) rxCloseBtn.addEventListener('click', closePrescriptionModal);

  document.querySelectorAll('.ph-filter-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.ph-filter-chip').forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      medicineActiveFilter = chip.getAttribute('data-filter') || 'all';
      renderMedicines();
    });
  });

  document.getElementById('medicine-search-input')?.addEventListener('input', renderMedicines);
}

export const initPharmacyModule = initPharmacySection;
export const loadMedicinesCatalog = refreshMedicineData;

