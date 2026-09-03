// dashboard-pharmacist.js — Pharmacist-only medicine management dashboard

'use strict';

// ── Config ──────────────────────────────────────────────────────────────────
const getApiBase = () => String(window.UKONEK_CONFIG?.API_BASE || '').trim();
const API_BASE   = getApiBase();
const isDemoMode = Boolean(window.UKONEK_CONFIG?.FORCE_DEMO);

const LOW_STOCK_THRESHOLD  = 10;
const EXPIRY_SOON_DAYS     = 30;

// ── State ────────────────────────────────────────────────────────────────────
let medicines       = [];
let filteredMedicines = [];
let activeFilter    = 'all';
let searchQuery     = '';
let cachedUser      = null;
let supabaseClient  = null;

// ── Presence Heartbeat State & Helpers ────────────────────────────────────────
const STAFF_PRESENCE_HEARTBEAT_MS = 60 * 1000;
let presenceHeartbeatTimer = null;

async function pushPresenceHeartbeat() {
  if (isDemoMode) return;

  try {
    const authService = await loadAuthServiceModule();
    await authService.setStaffPresence(true);
  } catch (error) {
    console.warn('Presence heartbeat warning:', error);
  }
}

function startPresenceHeartbeat() {
  if (isDemoMode || presenceHeartbeatTimer) return;

  pushPresenceHeartbeat();
  presenceHeartbeatTimer = setInterval(pushPresenceHeartbeat, STAFF_PRESENCE_HEARTBEAT_MS);
}

function stopPresenceHeartbeat() {
  if (!presenceHeartbeatTimer) return;
  clearInterval(presenceHeartbeatTimer);
  presenceHeartbeatTimer = null;
}

async function markStaffOfflineBestEffort() {
  if (isDemoMode) return;

  try {
    const authService = await loadAuthServiceModule();
    await authService.setStaffPresence(false);
  } catch (_) {
    // best effort on page close/navigation
  }
}

function sendOfflinePresenceOnUnload() {
  if (isDemoMode) return;

  try {
    const config = window.UKONEK_CONFIG || {};
    const supabaseUrl = String(config.SUPABASE_URL || '').trim();
    const supabaseAnonKey = String(config.SUPABASE_ANON_KEY || '').trim();
    if (!supabaseUrl || !supabaseAnonKey) return;

    const keys = Object.keys(window.sessionStorage || {});
    const authKey = keys.find((key) => key.startsWith('sb-') && key.includes('-auth-tab-'));
    if (!authKey) return;

    const raw = sessionStorage.getItem(authKey);
    if (!raw) return;

    const parsed = JSON.parse(raw);
    const accessToken = String(parsed?.access_token || '').trim();
    if (!accessToken) return;

    const url = `${supabaseUrl}/rest/v1/rpc/set_staff_presence`;
    const body = JSON.stringify({ p_is_online: false });

    // Prefer keepalive fetch; unload-safe on modern browsers.
    fetch(url, {
      method: 'POST',
      keepalive: true,
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body
    }).catch(() => {
      // Ignore unload path failures.
    });
  } catch (_) {
    // Ignore unload path failures.
  }
}

function handleAutoLogoutOnClose() {
  stopPresenceHeartbeat();
  sendOfflinePresenceOnUnload();
  markStaffOfflineBestEffort();
}

/**
 * Render standard table row skeletons during data load.
 * Prevents layout shift and provides clean shimmer animations.
 */
function renderTableSkeleton(tbody, columnCount, rowCount = 5) {
  if (!tbody) return;
  let rowsHtml = '';
  for (let i = 0; i < rowCount; i++) {
    rowsHtml += '<tr class="skeleton-row">';
    for (let j = 0; j < columnCount; j++) {
      const width = j === 0 ? 'width: 65%;' : (j === columnCount - 1 ? 'width: 40%;' : 'width: 85%;');
      rowsHtml += `
        <td class="table-cell" style="padding: 12px 14px; vertical-align: middle;">
          <div class="skeleton-shimmer skeleton-text" style="${width} height: 12px; margin: 4px 0; border-radius: 4px; display: block;"></div>
        </td>
      `;
    }
    rowsHtml += '</tr>';
  }
  tbody.innerHTML = rowsHtml;
}

/**
 * Render shimmery statistics placeholder inside text nodes.
 */
function togglePharmacistStatsSkeleton(isLoading) {
  const statIds = ['stat-total', 'stat-in-stock', 'stat-low', 'stat-expiry'];
  statIds.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    if (isLoading) {
      if (!el.dataset.originalText) {
        el.dataset.originalText = el.textContent || '0';
      }
      el.innerHTML = `<span class="skeleton-shimmer" style="width: 50px; height: 28px; border-radius: 6px; display: inline-block;"></span>`;
    } else {
      if (el.dataset.originalText && el.querySelector('.skeleton-shimmer')) {
        el.textContent = el.dataset.originalText;
        delete el.dataset.originalText;
      }
    }
  });
}

// ── DOM refs ─────────────────────────────────────────────────────────────────
const tbody        = document.getElementById('ph-medicines-tbody');
const searchInput  = document.getElementById('ph-search');
const filterBtns   = document.querySelectorAll('.ph-filter-btn');
const refreshBtn   = document.getElementById('ph-refresh-btn');
const addForm      = document.getElementById('ph-add-form');
const addSubmitBtn = document.getElementById('add-submit-btn');
const addBtnLabel  = document.getElementById('add-btn-label');
const editModal    = document.getElementById('ph-edit-modal');
const editIdInput  = document.getElementById('edit-id');
const editNameDisp = document.getElementById('edit-name-display');
const editDescInp  = document.getElementById('edit-desc');
const editQtyInp   = document.getElementById('edit-qty');
const editExpiryInp= document.getElementById('edit-expiry');
const editSaveBtn  = document.getElementById('edit-save-btn');
const editCancelBtn= document.getElementById('edit-cancel-btn');
const logoutBtn    = document.getElementById('ph-logout-btn');
const userNameEl   = document.getElementById('ph-user-name');
const listSubtitle = document.getElementById('ph-list-subtitle');

// Delete modal DOM refs
const deleteModal    = document.getElementById('ph-delete-modal');
const deleteMedName  = document.getElementById('delete-med-name');
const deleteConfirmBtn = document.getElementById('delete-confirm-btn');
const deleteCancelBtn = document.getElementById('delete-cancel-btn');

let pendingDeleteId = null;

// Dispense prescription DOM refs
const rxCodeInput       = document.getElementById('rx-code-input');
const rxLookupBtn       = document.getElementById('rx-lookup-btn');
const rxClearBtn        = document.getElementById('rx-clear-btn');
const rxDetailCard      = document.getElementById('rx-detail-card');
const rxCodeDisplay     = document.getElementById('rx-code-display');
const rxStatusBadge     = document.getElementById('rx-status-badge');
const rxPatient         = document.getElementById('rx-patient');
const rxDoctor          = document.getElementById('rx-doctor');
const rxIssued          = document.getElementById('rx-issued');
const rxItemsTbody      = document.getElementById('rx-items-tbody');
const rxDispenseAction  = document.getElementById('rx-dispense-action');
const rxConfirmBtn      = document.getElementById('rx-confirm-dispense-btn');
const rxDispensedNotice = document.getElementById('rx-dispensed-notice');
const rxDispensedBy     = document.getElementById('rx-dispensed-by');
const rxCancelledNotice = document.getElementById('rx-cancelled-notice');

// Dispense confirmation modal refs
const dispenseModal    = document.getElementById('ph-dispense-modal');
const dispenseModalCode = document.getElementById('dispense-modal-rx-code');
const dispenseCancelBtn = document.getElementById('dispense-modal-cancel-btn');
const dispenseConfirmBtn = document.getElementById('dispense-modal-confirm-btn');

// Confirmation modal DOM refs
const confirmAddModal    = document.getElementById('ph-confirm-add-modal');
const confirmAddName     = document.getElementById('confirm-add-name');
const confirmAddQty      = document.getElementById('confirm-add-qty');
const confirmAddExpiry   = document.getElementById('confirm-add-expiry');
const confirmAddCancel   = document.getElementById('confirm-add-cancel-btn');
const confirmAddSubmit   = document.getElementById('confirm-add-submit-btn');

// Return modal DOM refs
const returnModal       = document.getElementById('ph-return-modal');
const returnMedName     = document.getElementById('return-modal-med-name');
const returnMaxQty      = document.getElementById('return-modal-max-qty');
const returnQtyInp      = document.getElementById('return-modal-qty');
const returnReasonSel   = document.getElementById('return-modal-reason');
const returnNotesInp    = document.getElementById('return-modal-notes');
const returnCancelBtn   = document.getElementById('return-modal-cancel-btn');
const returnConfirmBtn  = document.getElementById('return-modal-confirm-btn');

let pendingReturnData = null;

// OTC Dispensing DOM refs
const openOtcDispenseBtn = document.getElementById('open-otc-dispense-btn');
const otcModal           = document.getElementById('ph-otc-modal');
const otcModalCloseIcon  = document.getElementById('otc-modal-close-icon');
const otcPatientNameInp  = document.getElementById('otc-patient-name');
const otcNotesInp        = document.getElementById('otc-notes');
const otcItemsContainer  = document.getElementById('otc-items-container');
const otcAddLineBtn      = document.getElementById('otc-add-line-btn');
const otcSummaryCounter  = document.getElementById('otc-summary-counter');
const otcCancelBtn       = document.getElementById('otc-cancel-btn');
const otcSubmitBtn       = document.getElementById('otc-submit-btn');

// OTC Receipt Modal refs
const otcReceiptModal    = document.getElementById('ph-otc-receipt-modal');
const otcReceiptRef      = document.getElementById('otc-receipt-ref');
const otcReceiptPatient  = document.getElementById('otc-receipt-patient');
const otcReceiptItems    = document.getElementById('otc-receipt-items');
const otcReceiptCloseBtn = document.getElementById('otc-receipt-close-btn');

let otcLineItems = [];
let pendingAddData = null;

// ── Toast ─────────────────────────────────────────────────────────────────────
function showToast(message, type = 'info') {
  const container = document.getElementById('ph-toast');
  if (!container) return;
  const el = document.createElement('div');
  el.className = `ph-toast-item ${type}`;
  el.textContent = message;
  container.appendChild(el);
  requestAnimationFrame(() => {
    requestAnimationFrame(() => el.classList.add('show'));
  });
  setTimeout(() => {
    el.classList.remove('show');
    setTimeout(() => el.remove(), 320);
  }, 3500);
}

// ── Loading state ─────────────────────────────────────────────────────────────
function setLoading(btn, state) {
  if (!btn) return;
  btn.disabled = state;
  if (state) {
    btn._originalHTML = btn.innerHTML;
    btn.innerHTML = '<span class="ph-spinner"></span>';
  } else {
    if (btn._originalHTML) btn.innerHTML = btn._originalHTML;
  }
}

// ── Supabase module ───────────────────────────────────────────────────────────
async function getSupabase() {
  if (supabaseClient) return supabaseClient;
  const mod = await import('./lib/supabaseClient.js');
  supabaseClient = mod.supabase || mod.default;
  return supabaseClient;
}

// ── Auth ──────────────────────────────────────────────────────────────────────
async function loadAuthServiceModule() {
  return await import('./services/authService.js');
}

async function ensurePharmacistSession() {
  if (cachedUser) return cachedUser;
  let profile = null;
  try {
    const authService = await loadAuthServiceModule();
    profile = await authService.getAuthenticatedStaffProfile();
  } catch (err) {
    console.error('Failed to load staff profile:', err);
    showToast('Unable to verify your session. Please sign in again.', 'error');
    setTimeout(() => { window.location.href = './index.html'; }, 1800);
    throw err;
  }

  if (!profile) {
    showToast('Session expired. Please sign in again.', 'warning');
    setTimeout(() => { window.location.href = './index.html'; }, 1500);
    throw new Error('Not authenticated');
  }

  const role = String(profile.role || '').trim().toLowerCase();
  if (role !== 'pharmacist') {
    showToast('Access denied. Pharmacist account required.', 'error');
    setTimeout(() => { window.location.href = './index.html'; }, 1500);
    throw new Error('Forbidden role: ' + role);
  }

  cachedUser = profile;
  return profile;
}

// ── Data helpers ──────────────────────────────────────────────────────────────
function computeStockStatus(qty) {
  if (qty === 0) {
    return { label: 'Out of Stock', cls: 'badge-red', fillCls: 'ph-stock-fill-empty', percent: 0 };
  }
  if (qty <= 10) {
    return { label: 'Critical Low', cls: 'badge-red', fillCls: 'ph-stock-fill-critical', percent: Math.max(10, Math.min(100, (qty / 50) * 100)) };
  }
  if (qty <= LOW_STOCK_THRESHOLD) {
    return { label: 'Low Stock', cls: 'badge-amber', fillCls: 'ph-stock-fill-low', percent: Math.min(100, (qty / 50) * 100) };
  }
  return { label: 'In Stock', cls: 'badge-green', fillCls: 'ph-stock-fill-healthy', percent: Math.min(100, (qty / 50) * 100) };
}

function computeExpiryStatus(expiryDate) {
  if (!expiryDate) {
    return {
      label: 'No Expiry Set',
      cls: 'badge-gray',
      pillHtml: '<span class="badge badge-gray">No Expiry Set</span>'
    };
  }
  const today = new Date(); today.setHours(0,0,0,0);
  const exp   = new Date(expiryDate); exp.setHours(0,0,0,0);
  const diffDays = Math.floor((exp - today) / 86400000);

  if (diffDays < 0) {
    return {
      label: 'Expired',
      cls: 'badge-red',
      pillHtml: `<span class="ph-expiry-badge ph-expiry-expired">Expired (${Math.abs(diffDays)}d ago)</span>`
    };
  }
  if (diffDays <= EXPIRY_SOON_DAYS) {
    return {
      label: 'Expiring Soon',
      cls: 'badge-amber',
      pillHtml: `<span class="ph-expiry-badge ph-expiry-critical">Expires in ${diffDays}d</span>`
    };
  }
  if (diffDays <= 90) {
    const mos = Math.ceil(diffDays / 30);
    return {
      label: 'Valid',
      cls: 'badge-amber',
      pillHtml: `<span class="ph-expiry-badge ph-expiry-warning">In ${mos} mos (${diffDays}d)</span>`
    };
  }
  return {
    label: 'Valid',
    cls: 'badge-green',
    pillHtml: `<span class="ph-expiry-badge ph-expiry-good">Good (${diffDays}d)</span>`
  };
}

function formatDate(val) {
  if (!val) return '—';
  const d = new Date(val);
  if (isNaN(d)) return val;
  return d.toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: '2-digit' });
}

// ── Load medicines ─────────────────────────────────────────────────────────────
async function loadMedicines() {
  const medicinesTbody = document.getElementById('ph-medicines-tbody');
  if (medicinesTbody) renderTableSkeleton(medicinesTbody, 8, 6);
  togglePharmacistStatsSkeleton(true);

  if (isDemoMode) {
    const raw = localStorage.getItem('ukonek_medicines');
    try { medicines = raw ? JSON.parse(raw) : []; } catch { medicines = []; }
    togglePharmacistStatsSkeleton(false);
    return;
  }
  try {
    const sb = await getSupabase();
    const { data, error } = await sb
      .from('medicines')
      .select('id, name, description, qty, unit, expiry_date, drug_classification, created_at, updated_at')
      .is('archived_at', null)
      .order('name', { ascending: true });
    if (error) throw new Error(error.message);
    medicines = (data || []).map(row => ({
      id:                  row.id,
      name:                row.name,
      description:         row.description || '',
      qty:                 Number(row.qty ?? 0),
      unit:                row.unit || '',
      expiry_date:         row.expiry_date || null,
      drug_classification: (row.drug_classification || 'rx').toLowerCase(),
      created_at:          row.created_at,
      updated_at:          row.updated_at
    }));
  } catch (err) {
    console.error('Failed to load medicines:', err);
    showToast('Failed to load medicines. ' + (err.message || ''), 'error');
    medicines = [];
  } finally {
    togglePharmacistStatsSkeleton(false);
  }
}

// ── Filter / search ────────────────────────────────────────────────────────────
function getFilteredMedicines() {
  let rows = medicines.slice();

  if (searchQuery) {
    const q = searchQuery.toLowerCase();
    rows = rows.filter(m => m.name.toLowerCase().includes(q) || (m.description || '').toLowerCase().includes(q));
  }

  switch (activeFilter) {
    case 'otc':
      rows = rows.filter(m => (m.drug_classification || '').toLowerCase() === 'otc');
      break;
    case 'low':
      rows = rows.filter(m => m.qty <= LOW_STOCK_THRESHOLD);
      break;
    case 'expired':
      rows = rows.filter(m => {
        if (!m.expiry_date) return false;
        return new Date(m.expiry_date) < new Date(new Date().toDateString());
      });
      break;
    case 'expiring':
      rows = rows.filter(m => {
        if (!m.expiry_date) return false;
        const today = new Date(); today.setHours(0,0,0,0);
        const exp = new Date(m.expiry_date); exp.setHours(0,0,0,0);
        const diff = Math.floor((exp - today) / 86400000);
        return diff >= 0 && diff <= EXPIRY_SOON_DAYS;
      });
      break;
  }

  // Apply Sorting
  const sortSelect = document.getElementById('ph-sort-select');
  const sortBy = sortSelect ? sortSelect.value : 'name-asc';

  if (sortBy === 'name-asc') {
    rows.sort((a, b) => a.name.localeCompare(b.name));
  } else if (sortBy === 'name-desc') {
    rows.sort((a, b) => b.name.localeCompare(a.name));
  } else if (sortBy === 'stock-desc') {
    rows.sort((a, b) => (b.qty || 0) - (a.qty || 0));
  } else if (sortBy === 'stock-asc') {
    rows.sort((a, b) => (a.qty || 0) - (b.qty || 0));
  } else if (sortBy === 'expiry-asc') {
    rows.sort((a, b) => {
      const dateA = a.expiry_date ? new Date(a.expiry_date).getTime() : Infinity;
      const dateB = b.expiry_date ? new Date(b.expiry_date).getTime() : Infinity;
      return dateA - dateB;
    });
  } else if (sortBy === 'expiry-desc') {
    rows.sort((a, b) => {
      const dateA = a.expiry_date ? new Date(a.expiry_date).getTime() : -1;
      const dateB = b.expiry_date ? new Date(b.expiry_date).getTime() : -1;
      return dateB - dateA;
    });
  }

  return rows;
}

// ── Render list ───────────────────────────────────────────────────────────────
function renderMedicines() {
  if (!tbody) return;
  const rows = getFilteredMedicines();
  filteredMedicines = rows; // Store for export
  updateStats();
  updateSubtitle(rows.length);

  if (!rows.length) {
    tbody.innerHTML = '<tr class="empty-row"><td colspan="8">No medicines found.</td></tr>';
    return;
  }

  tbody.innerHTML = '';
  rows.forEach(m => {
    const stock  = computeStockStatus(m.qty);
    const expiry = computeExpiryStatus(m.expiry_date);
    const tr = document.createElement('tr');

    // Highlight rows with issues
    if (expiry.label === 'Expired')        tr.style.background = '#fff5f5';
    else if (expiry.label === 'Expiring Soon') tr.style.background = '#fffbeb';
    else if (stock.label === 'Out of Stock')   tr.style.background = '#fff5f5';
    else if (stock.label === 'Low Stock' || stock.label === 'Critical Low') tr.style.background = '#fffbeb';

    tr.dataset.id = m.id;
    const isOtc = (m.drug_classification || '').toLowerCase() === 'otc';
    const classBadge = isOtc
      ? '<span class="badge badge-otc" style="margin-left:6px;font-size:10px;font-weight:700;">OTC</span>'
      : '<span class="badge badge-rx" style="margin-left:6px;font-size:10px;font-weight:700;">Rx</span>';

    tr.innerHTML = `
      <td><strong>${escHtml(m.name)}</strong>${classBadge}</td>
      <td style="color:#64748b;font-size:13px;">${escHtml(m.description) || '<em style="color:#cbd5e1">—</em>'}</td>
      <td>
        <div class="ph-stock-bar-wrap">
          <div class="ph-stock-qty-text">
            <strong>${m.qty}</strong>
            <span class="ph-stock-unit">${escHtml(m.unit) || ''}</span>
          </div>
          <div class="ph-stock-bar-track">
            <div class="ph-stock-bar-fill ${stock.fillCls}" style="width:${stock.percent}%;"></div>
          </div>
        </div>
      </td>
      <td style="color:#64748b;">${escHtml(m.unit) || '—'}</td>
      <td>${formatDate(m.expiry_date)}</td>
      <td><span class="badge ${stock.cls}">${stock.label}</span></td>
      <td>${expiry.pillHtml}</td>
      <td>
        <div style="display:flex; gap:6px;">
          <button class="ph-btn ph-btn-edit ph-btn-sm" data-action="edit" data-id="${m.id}">Edit</button>
          <button class="ph-btn ph-btn-delete ph-btn-sm" data-action="delete" data-id="${m.id}">Delete</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  });
}

function escHtml(str) {
  return String(str || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function updateSubtitle(count) {
  if (!listSubtitle) return;
  const filterLabel = { all: 'All medicines', otc: 'Over-The-Counter (OTC)', low: 'Low / Out of Stock', expired: 'Expired', expiring: 'Expiring within 30 days' };
  listSubtitle.textContent = `${filterLabel[activeFilter] || 'All medicines'} — ${count} result${count !== 1 ? 's' : ''}`;
}

// ── Stats cards & Filter Badges ────────────────────────────────────────────────
function updateStats() {
  const total    = medicines.length;
  const inStock  = medicines.filter(m => m.qty > LOW_STOCK_THRESHOLD).length;
  const lowStock = medicines.filter(m => m.qty <= LOW_STOCK_THRESHOLD).length;
  const today    = new Date(); today.setHours(0,0,0,0);
  
  const expiredCount = medicines.filter(m => {
    if (!m.expiry_date) return false;
    return new Date(m.expiry_date) < today;
  }).length;

  const expAlert = medicines.filter(m => {
    if (!m.expiry_date) return false;
    const exp = new Date(m.expiry_date); exp.setHours(0,0,0,0);
    const diff = Math.floor((exp - today) / 86400000);
    return diff >= 0 && diff <= EXPIRY_SOON_DAYS;
  }).length;

  const statTotal = document.getElementById('stat-total');
  const statInStock = document.getElementById('stat-in-stock');
  const statLow = document.getElementById('stat-low');
  const statExpiry = document.getElementById('stat-expiry');

  if (statTotal) statTotal.textContent = total;
  if (statInStock) statInStock.textContent = inStock;
  if (statLow) statLow.textContent = lowStock;
  if (statExpiry) statExpiry.textContent = expAlert + expiredCount;

  // Update filter pill counts
  const cAll = document.getElementById('ph-count-all');
  const cOtc = document.getElementById('ph-count-otc');
  const cLow = document.getElementById('ph-count-low');
  const cExp = document.getElementById('ph-count-expired');
  const cSoon = document.getElementById('ph-count-expiring');

  const otcCount = medicines.filter(m => (m.drug_classification || '').toLowerCase() === 'otc').length;

  if (cAll) cAll.textContent = total;
  if (cOtc) cOtc.textContent = otcCount;
  if (cLow) cLow.textContent = lowStock;
  if (cExp) cExp.textContent = expiredCount;
  if (cSoon) cSoon.textContent = expAlert;
}

// ── Save medicine (add or update) ─────────────────────────────────────────────
async function saveMedicine({ id = null, name, description, qty, unit, expiry_date, drug_classification = 'rx' }) {
  qty = Number(qty);
  if (qty < 0) throw new Error('Stock quantity cannot be negative.');

  if (isDemoMode) {
    if (id === null) {
      const entry = {
        id: Date.now(),
        name: name.trim(),
        description: (description || '').trim(),
        qty,
        unit: (unit || '').trim(),
        expiry_date: expiry_date || null,
        drug_classification: drug_classification || 'rx',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      medicines.push(entry);
      localStorage.setItem('ukonek_medicines', JSON.stringify(medicines));
      return entry;
    } else {
      const idx = medicines.findIndex(m => m.id === id);
      if (idx === -1) throw new Error('Medicine not found.');
      medicines[idx] = { ...medicines[idx], description: (description || '').trim(), qty, expiry_date: expiry_date || null, drug_classification: drug_classification || medicines[idx].drug_classification, updated_at: new Date().toISOString() };
      localStorage.setItem('ukonek_medicines', JSON.stringify(medicines));
      return medicines[idx];
    }
  }

  const sb = await getSupabase();

  if (id === null) {
    // Step 1: INSERT with base columns
    const { data, error } = await sb
      .from('medicines')
      .insert({
        name: name.trim(),
        qty,
        unit: unit ? unit.trim() : null,
        drug_classification: drug_classification || 'rx'
      })
      .select('id')
      .single();
    if (error) throw new Error(error.message);

    // Step 2: UPDATE with extended columns (expiry_date, description)
    const extUpdates = {};
    if (expiry_date) extUpdates.expiry_date = expiry_date;
    if (description && description.trim()) extUpdates.description = description.trim();
    if (Object.keys(extUpdates).length > 0) {
      await sb.from('medicines').update(extUpdates).eq('id', data.id);
    }
    return data;
  } else {
    // UPDATE existing medicine (stock + expiry + description + classification)
    const updates = { qty };
    if (drug_classification) updates.drug_classification = drug_classification;
    if (expiry_date !== undefined) updates.expiry_date = expiry_date || null;
    if (description !== undefined) updates.description = description ? description.trim() : null;
    const { error } = await sb
      .from('medicines')
      .update(updates)
      .eq('id', id)
      .is('archived_at', null);
    if (error) throw new Error(error.message);
    return { id };
  }
}

// ── Add form ──────────────────────────────────────────────────────────────────
if (addForm) {
  addForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const name      = document.getElementById('add-name').value.trim();
    const drugClass = document.getElementById('add-classification')?.value || 'rx';
    const qty       = Number(document.getElementById('add-qty').value);
    const unit      = document.getElementById('add-unit').value.trim();
    const expiry    = document.getElementById('add-expiry').value || null;
    const desc      = document.getElementById('add-desc').value.trim();

    if (!name) { showToast('Medicine name is required.', 'warning'); return; }
    if (qty < 0) { showToast('Stock quantity cannot be negative.', 'warning'); return; }

    pendingAddData = { id: null, name, description: desc, qty, unit, expiry_date: expiry, drug_classification: drugClass };
    
    // Show confirmation modal
    if (confirmAddName) confirmAddName.textContent = name;
    if (confirmAddQty) confirmAddQty.textContent = `${qty} ${unit || ''}`.trim();
    if (confirmAddExpiry) confirmAddExpiry.textContent = expiry ? formatDate(expiry) : 'No expiration set';

    const confirmAddBadge = document.getElementById('confirm-add-classification-badge');
    if (confirmAddBadge) {
      confirmAddBadge.innerHTML = drugClass === 'otc'
        ? '<span class="badge badge-otc">OTC</span>'
        : '<span class="badge badge-rx">Rx</span>';
    }
    
    if (confirmAddModal) {
      confirmAddModal.classList.remove('hidden');
      confirmAddModal.style.display = 'flex';
    }
  });
}

if (confirmAddCancel) {
  confirmAddCancel.addEventListener('click', () => {
    confirmAddModal.classList.add('hidden');
    confirmAddModal.style.display = 'none';
    pendingAddData = null;
  });
}

if (confirmAddSubmit) {
  confirmAddSubmit.addEventListener('click', async () => {
    if (!pendingAddData) return;
    
    setLoading(confirmAddSubmit, true);
    try {
      await saveMedicine(pendingAddData);
      await loadMedicines();
      renderMedicines();
      addForm.reset();
      showToast(`"${pendingAddData.name}" added to inventory.`, 'success');
      
      confirmAddModal.classList.add('hidden');
      confirmAddModal.style.display = 'none';
      pendingAddData = null;
    } catch (err) {
      showToast(err.message || 'Failed to add medicine.', 'error');
    } finally {
      setLoading(confirmAddSubmit, false);
    }
  });
}

// ── Table click handler (edit) ────────────────────────────────────────────────
if (tbody) {
  tbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    const id     = Number(btn.dataset.id);
    const med    = medicines.find(m => m.id === id);
    if (!med) return;

    if (action === 'edit') {
      openEditModal(med);
    } else if (action === 'delete') {
      openDeleteModal(med);
    }
  });
}

// ── Delete modal ──────────────────────────────────────────────────────────────
function openDeleteModal(med) {
  pendingDeleteId = med.id;
  if (deleteMedName) deleteMedName.textContent = med.name;
  if (deleteModal) {
    deleteModal.classList.remove('hidden');
    deleteModal.style.display = 'flex';
  }
}

if (deleteCancelBtn) {
  deleteCancelBtn.addEventListener('click', () => {
    deleteModal.classList.add('hidden');
    deleteModal.style.display = 'none';
    pendingDeleteId = null;
  });
}

if (deleteConfirmBtn) {
  deleteConfirmBtn.addEventListener('click', async () => {
    if (pendingDeleteId === null) return;
    
    setLoading(deleteConfirmBtn, true);
    try {
      await deleteMedicine(pendingDeleteId);
      await loadMedicines();
      renderMedicines();
      showToast('Medicine successfully deleted.', 'success');
      
      deleteModal.classList.add('hidden');
      deleteModal.style.display = 'none';
      pendingDeleteId = null;
    } catch (err) {
      showToast(err.message || 'Failed to delete medicine.', 'error');
    } finally {
      setLoading(deleteConfirmBtn, false);
    }
  });
}

async function deleteMedicine(id) {
  if (isDemoMode) {
    const idx = medicines.findIndex(m => m.id === id);
    if (idx !== -1) {
      medicines.splice(idx, 1);
      localStorage.setItem('ukonek_medicines', JSON.stringify(medicines));
    }
    return;
  }

  const sb = await getSupabase();
  const { error } = await sb
    .from('medicines')
    .update({ archived_at: new Date().toISOString() })
    .eq('id', id);

  if (error) throw new Error(error.message);
}

// ── Edit modal ────────────────────────────────────────────────────────────────
function openEditModal(med) {
  editIdInput.value    = med.id;
  editNameDisp.value   = med.name;
  const editClassInp   = document.getElementById('edit-classification');
  if (editClassInp) editClassInp.value = (med.drug_classification || 'rx').toLowerCase();
  editDescInp.value    = med.description || '';
  editQtyInp.value     = med.qty;
  editExpiryInp.value  = med.expiry_date || '';
  editModal.classList.remove('hidden');
  editQtyInp.focus();
}

function closeEditModal() {
  editModal.classList.add('hidden');
}

if (editCancelBtn) editCancelBtn.addEventListener('click', closeEditModal);
if (editModal) {
  editModal.addEventListener('click', (e) => {
    if (e.target === editModal) closeEditModal();
  });
}

if (editSaveBtn) {
  editSaveBtn.addEventListener('click', async () => {
    const id        = Number(editIdInput.value);
    const drugClass = document.getElementById('edit-classification')?.value || 'rx';
    const qty       = Number(editQtyInp.value);
    const expiry    = editExpiryInp.value || null;
    const desc      = editDescInp.value.trim();
    const med       = medicines.find(m => m.id === id);

    if (!med) { showToast('Medicine not found.', 'error'); return; }
    if (qty < 0) { showToast('Stock quantity cannot be negative.', 'warning'); return; }

    setLoading(editSaveBtn, true);
    try {
      await saveMedicine({ id, description: desc, qty, expiry_date: expiry, drug_classification: drugClass });
      await loadMedicines();
      renderMedicines();
      closeEditModal();
      showToast(`"${med.name}" updated.`, 'success');
    } catch (err) {
      showToast(err.message || 'Failed to update medicine.', 'error');
    } finally {
      setLoading(editSaveBtn, false);
    }
  });
}

// ── Filter buttons ────────────────────────────────────────────────────────────
filterBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    filterBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    activeFilter = btn.dataset.filter || 'all';
    renderMedicines();
  });
});

// ── Search ────────────────────────────────────────────────────────────────────
if (searchInput) {
  searchInput.addEventListener('input', () => {
    searchQuery = searchInput.value.trim();
    renderMedicines();
  });
}

// ── Refresh ───────────────────────────────────────────────────────────────────
if (refreshBtn) {
  refreshBtn.addEventListener('click', async () => {
    setLoading(refreshBtn, true);
    try {
      await loadMedicines();
      renderMedicines();
      showToast('Inventory refreshed.', 'info');
    } finally {
      setLoading(refreshBtn, false);
    }
  });
}

// ── Logout ────────────────────────────────────────────────────────────────────
const logoutModal = document.getElementById('ph-logout-modal');
const logoutCancelBtn = document.getElementById('ph-logout-cancel-btn');
const logoutConfirmBtn = document.getElementById('ph-logout-confirm-btn');

if (logoutBtn) {
  logoutBtn.addEventListener('click', () => {
    if (logoutModal) {
      logoutModal.classList.remove('hidden');
      logoutModal.style.display = 'flex';
    }
  });
}

if (logoutCancelBtn) {
  logoutCancelBtn.addEventListener('click', () => {
    if (logoutModal) {
      logoutModal.classList.add('hidden');
      logoutModal.style.display = 'none';
    }
  });
}

if (logoutConfirmBtn) {
  logoutConfirmBtn.addEventListener('click', async () => {
    setLoading(logoutConfirmBtn, true);
    try {
      const authService = await loadAuthServiceModule();
      const fn = authService.signOutStaff || authService.signOut || authService.default?.signOutStaff;
      if (fn) await fn();
    } catch (_) {}
    sessionStorage.clear();
    window.location.href = './index.html';
  });
}

// ── Guard: prevent non-pharmacist access ──────────────────────────────────────
async function guardAccess() {
  // Check the session-storage role key written by script.js at login time
  const role = (sessionStorage.getItem('ukonek_role') || '').toLowerCase();
  // Only block if we have a definitive non-pharmacist role (empty means not yet loaded)
  if (role !== '' && role !== 'pharmacist') {
    showToast('Access restricted to pharmacists only.', 'error');
    setTimeout(() => { window.location.href = './index.html'; }, 1200);
    return false;
  }
  return true;
}

// ── Dispense Prescription ─────────────────────────────────────────────────────

let currentRxData = null;

function rxShow(el) { if (el) el.style.display = ''; }
function rxHide(el) { if (el) el.style.display = 'none'; }

function renderRxStatusBadge(status) {
  if (!rxStatusBadge) return;
  const map = {
    pending:   { cls: 'badge-blue',   label: 'Pending' },
    partial:   { cls: 'badge-yellow', label: 'Partially Dispensed' },
    dispensed: { cls: 'badge-green',  label: 'Dispensed' },
    cancelled: { cls: 'badge-red',    label: 'Cancelled' }
  };
  const s = map[status] || { cls: 'badge-gray', label: status };
  rxStatusBadge.innerHTML = `<span class="badge ${s.cls}" style="font-size:13px;padding:5px 14px;">${s.label}</span>`;
}

function renderRxItems(items) {
  if (!rxItemsTbody) return;
  if (!Array.isArray(items) || !items.length) {
    rxItemsTbody.innerHTML = '<tr class="empty-row"><td colspan="8">No items.</td></tr>';
    return;
  }
  rxItemsTbody.innerHTML = items.map(it => {
    const remaining = it.remaining_quantity ?? (it.quantity - (it.dispensed_quantity ?? 0));
    const isFullyDispensed = remaining <= 0;
    const dispensedQty = it.dispensed_quantity ?? 0;
    const statusHtml = isFullyDispensed
      ? '<span style="color:#16a34a;font-weight:600;">&#10003; Done</span>'
      : (dispensedQty > 0
          ? '<span style="color:#d97706;font-weight:600;">Partial</span>'
          : '<span style="color:#64748b;">Pending</span>');
    const returnBtnHtml = dispensedQty > 0
      ? `<button type="button" class="rx-return-btn ph-btn ph-btn-sm" data-item-id="${it.id}" data-item-name="${escHtml(it.medicine_name)}" data-dispensed="${dispensedQty}" style="background:#fef2f2;color:#dc2626;border:1px solid #fecaca;margin-top:4px;padding:2px 8px;font-size:11px;cursor:pointer;" title="Return dispensed units to inventory">&#x21a9; Return</button>`
      : '';
    return `
      <tr>
        <td><strong>${escHtml(it.medicine_name)}</strong></td>
        <td style="text-align:center;">${it.quantity} ${escHtml(it.unit || '')}</td>
        <td style="text-align:center;">${dispensedQty}</td>
        <td style="text-align:center;">${remaining}</td>
        <td>${escHtml(it.dosage) || '—'}</td>
        <td>${escHtml(it.frequency) || '—'}</td>
        <td style="font-size:13px;color:#64748b;">${escHtml(it.instructions) || '—'}</td>
        <td style="text-align:center;">
          <div style="display:flex;flex-direction:column;align-items:center;gap:3px;">
            ${isFullyDispensed
              ? statusHtml
              : `<input
                  type="number"
                  class="rx-dispense-qty-input"
                  data-item-id="${it.id}"
                  data-remaining="${remaining}"
                  min="0"
                  max="${remaining}"
                  value="${remaining}"
                  style="width:64px;padding:3px 6px;border:1px solid #cbd5e1;border-radius:6px;text-align:center;"
                >`}
            ${returnBtnHtml}
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

function clearRxLookup() {
  currentRxData = null;
  if (rxCodeInput) rxCodeInput.value = 'RX-';
  rxHide(rxDetailCard);
  rxHide(rxClearBtn);
  rxHide(rxDispenseAction);
  rxHide(rxDispensedNotice);
  rxHide(rxCancelledNotice);
}

async function lookupPrescription() {
  const code = (rxCodeInput?.value || '').trim().toUpperCase();
  if (!code) { showToast('Enter a Prescription ID.', 'warning'); return; }

  setLoading(rxLookupBtn, true);
  try {
    const sb = await getSupabase();
    const { data, error } = await sb.rpc('lookup_prescription_by_code', { p_code: code });
    if (error) throw new Error(error.message);
    if (data?.error) throw new Error(data.error);

    currentRxData = data;

    // Populate header fields
    if (rxCodeDisplay) rxCodeDisplay.textContent = data.prescription_code || code;
    if (rxPatient)     rxPatient.textContent     = data.patient_identifier || '—';
    if (rxDoctor)      rxDoctor.textContent      = data.doctor_name || '—';
    if (rxIssued)      rxIssued.textContent      = data.issued_at ? new Date(data.issued_at).toLocaleString('en-PH') : '—';

    renderRxStatusBadge(data.dispensing_status);
    renderRxItems(data.items || []);

    // Show correct action panel
    rxHide(rxDispenseAction);
    rxHide(rxDispensedNotice);
    rxHide(rxCancelledNotice);

    if (data.dispensing_status === 'pending' || data.dispensing_status === 'partial') {
      rxShow(rxDispenseAction);
    } else if (data.dispensing_status === 'dispensed') {
      const when = data.last_dispensed_at
        ? new Date(data.last_dispensed_at).toLocaleString('en-PH')
        : (data.dispensed_at ? new Date(data.dispensed_at).toLocaleString('en-PH') : 'earlier');
      if (rxDispensedBy) rxDispensedBy.textContent = `Fully dispensed on ${when}.`;
      rxShow(rxDispensedNotice);
    } else if (data.dispensing_status === 'cancelled') {
      rxShow(rxCancelledNotice);
    }

    rxShow(rxDetailCard);
    rxShow(rxClearBtn);
  } catch (err) {
    showToast(err.message || 'Lookup failed.', 'error');
    rxHide(rxDetailCard);
    rxHide(rxClearBtn);
  } finally {
    setLoading(rxLookupBtn, false);
  }
}

async function confirmDispense() {
  if (!currentRxData) return;
  const code = currentRxData.prescription_code;

  // Collect and validate per-item quantities from the rendered inputs
  const inputs = document.querySelectorAll('.rx-dispense-qty-input');
  const pendingItems = [];
  let hasError = false;
  let totalDispenseQty = 0;

  inputs.forEach(input => {
    const itemId = parseInt(input.dataset.itemId, 10);
    const remaining = parseInt(input.dataset.remaining, 10);
    const qty = parseInt(input.value, 10);

    if (isNaN(qty) || qty < 0) {
      showToast(`Enter a valid quantity (0 or more) for each item.`, 'warning');
      hasError = true;
      return;
    }
    if (qty > remaining) {
      showToast(`Quantity exceeds remaining (${remaining}) for one or more items.`, 'warning');
      hasError = true;
      return;
    }
    totalDispenseQty += qty;
    pendingItems.push({ prescription_item_id: itemId, quantity: qty });
  });

  if (hasError || pendingItems.length === 0) return;

  if (totalDispenseQty === 0) {
    showToast('Please enter a quantity greater than 0 for at least one item to dispense.', 'warning');
    return;
  }

  // Stash on state for the confirm handler
  currentRxData._pendingDispenseItems = pendingItems;

  if (dispenseModalCode) dispenseModalCode.textContent = code;
  if (dispenseModal) {
    dispenseModal.classList.remove('hidden');
    dispenseModal.style.display = 'flex';
  }
}

async function handleActualDispense() {
  if (!currentRxData) return;
  const code = currentRxData.prescription_code;
  const allItems = currentRxData._pendingDispenseItems || [];
  // Only items with quantity > 0 are dispatched for deduction & event recording
  const items = allItems.filter(it => it.quantity > 0);

  if (!items || items.length === 0) {
    showToast('No items with quantity greater than 0 to dispense.', 'warning');
    return;
  }

  setLoading(dispenseConfirmBtn, true);
  try {
    const sb = await getSupabase();
    const { data, error } = await sb.rpc('dispense_prescription_items', {
      p_prescription_code: code,
      p_items: items
    });
    if (error) throw new Error(error.message);
    if (data?.error) throw new Error(data.error);

    const newStatus = data.dispensing_status || 'dispensed';
    const label = newStatus === 'partial' ? 'partially dispensed' : 'dispensed';
    showToast(`Prescription ${code} ${label}. Stock updated.`, 'success');

    // Refresh inventory list
    await loadMedicines();
    renderMedicines();

    // Re-lookup to update the card status and quantities
    await lookupPrescription();

    // Close modal
    if (dispenseModal) {
      dispenseModal.classList.add('hidden');
      dispenseModal.style.display = 'none';
    }
  } catch (err) {
    showToast(err.message || 'Dispense failed.', 'error');
  } finally {
    setLoading(dispenseConfirmBtn, false);
  }
}

// Event listeners
if (rxLookupBtn) {
  rxLookupBtn.addEventListener('click', lookupPrescription);
}
if (rxCodeInput) {
  rxCodeInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); lookupPrescription(); }
  });
  rxCodeInput.addEventListener('input', () => {
    let val = rxCodeInput.value.toUpperCase();
    if (!val.startsWith('RX-')) {
      if (val.length < 3) {
        val = 'RX-';
      } else {
        // If they pasted something like "000012", turn it into "RX-000012"
        val = 'RX-' + val.replace(/^RX-?/i, '');
      }
    }
    rxCodeInput.value = val;
  });
}
if (rxClearBtn) {
  rxClearBtn.addEventListener('click', clearRxLookup);
}
if (rxConfirmBtn) {
  rxConfirmBtn.addEventListener('click', confirmDispense);
}
if (dispenseCancelBtn) {
  dispenseCancelBtn.addEventListener('click', () => {
    dispenseModal.classList.add('hidden');
    dispenseModal.style.display = 'none';
  });
}
if (dispenseConfirmBtn) {
  dispenseConfirmBtn.addEventListener('click', handleActualDispense);
}

// ── Return & Restock Handlers ──────────────────────────────────────────────────
function openReturnModal({ itemId, medicineName, dispensedQty }) {
  if (!returnModal) return;
  pendingReturnData = { itemId, medicineName, dispensedQty };
  if (returnMedName) returnMedName.textContent = medicineName;
  if (returnMaxQty) returnMaxQty.textContent = dispensedQty;
  if (returnQtyInp) {
    returnQtyInp.value = 1;
    returnQtyInp.max = dispensedQty;
  }
  if (returnNotesInp) returnNotesInp.value = '';
  returnModal.classList.remove('hidden');
  returnModal.style.display = 'flex';
}

function closeReturnModal() {
  if (!returnModal) return;
  returnModal.classList.add('hidden');
  returnModal.style.display = 'none';
  pendingReturnData = null;
}

if (returnCancelBtn) returnCancelBtn.addEventListener('click', closeReturnModal);
if (returnModal) {
  returnModal.addEventListener('click', (e) => {
    if (e.target === returnModal) closeReturnModal();
  });
}

if (returnConfirmBtn) {
  returnConfirmBtn.addEventListener('click', async () => {
    if (!pendingReturnData) return;
    const qty = parseInt(returnQtyInp?.value, 10);
    const reasonCategory = returnReasonSel?.value || 'Other';
    const notes = (returnNotesInp?.value || '').trim();
    const fullReason = notes ? `${reasonCategory}: ${notes}` : reasonCategory;

    if (isNaN(qty) || qty <= 0) {
      showToast('Please enter a return quantity greater than 0.', 'warning');
      return;
    }

    if (qty > pendingReturnData.dispensedQty) {
      showToast(`Cannot return more than ${pendingReturnData.dispensedQty} units.`, 'warning');
      return;
    }

    setLoading(returnConfirmBtn, true);
    try {
      const sb = await getSupabase();
      const { data, error } = await sb.rpc('return_dispensed_prescription_item', {
        p_prescription_item_id: pendingReturnData.itemId,
        p_quantity: qty,
        p_reason: fullReason
      });

      if (error) throw new Error(error.message);
      if (data?.error) throw new Error(data.error);

      showToast(data.message || 'Item restocked successfully.', 'success');
      closeReturnModal();

      await lookupPrescription();
      await loadMedicines();
      renderMedicines();
    } catch (err) {
      showToast(err.message || 'Failed to restock item.', 'error');
    } finally {
      setLoading(returnConfirmBtn, false);
    }
  });
}

if (rxItemsTbody) {
  rxItemsTbody.addEventListener('click', (e) => {
    const returnBtn = e.target.closest('.rx-return-btn');
    if (!returnBtn) return;
    const itemId = Number(returnBtn.dataset.itemId);
    const medicineName = returnBtn.dataset.itemName;
    const dispensedQty = parseInt(returnBtn.dataset.dispensed, 10);
    openReturnModal({ itemId, medicineName, dispensedQty });
  });
}

// ── QR Scanner Implementation ────────────────────────────────────────────────
let html5QrCode = null;

async function startQrScanner() {
  const modal = document.getElementById('ph-scanner-modal');
  if (!modal) return;
  
  modal.classList.remove('hidden');
  modal.style.display = 'flex';

  if (!html5QrCode) {
    html5QrCode = new Html5Qrcode("qr-reader");
  }

  const config = { fps: 10, qrbox: { width: 250, height: 250 } };

  try {
    await html5QrCode.start(
      { facingMode: "environment" }, 
      config,
      (decodedText) => {
        // Success: handle the scanned code
        stopQrScanner();
        if (rxCodeInput) {
          rxCodeInput.value = decodedText.trim().toUpperCase();
          lookupPrescription();
        }
      }
    ).catch(err => {
      console.error("Scanner start error:", err);
      showToast("Camera access denied or unavailable.", "error");
      stopQrScanner();
    });
  } catch (err) {
    console.error("Unable to start scanner:", err);
    stopQrScanner();
  }
}

function stopQrScanner() {
  const modal = document.getElementById('ph-scanner-modal');
  if (modal) {
    modal.classList.add('hidden');
    modal.style.display = 'none';
  }
  if (html5QrCode && html5QrCode.isScanning) {
    html5QrCode.stop().catch(err => console.warn("Scanner stop failed:", err));
  }
}

// Attach scanner listeners
const scanBtn = document.getElementById('rx-scan-btn');
if (scanBtn) scanBtn.addEventListener('click', startQrScanner);

const closeScannerBtn = document.getElementById('scanner-close-x');
if (closeScannerBtn) closeScannerBtn.addEventListener('click', stopQrScanner);

// ── Reports & Exports ────────────────────────────────────────────────────────
function generateReport(title, headers, rows) {
  const win = window.open('', '_blank');
  if (!win) { showToast('Popup blocked. Allow popups for report generation.', 'error'); return; }
  const html = [];
  html.push('<html><head><title>' + title + '</title>');
  html.push('<style>body{font-family:Arial,Helvetica,sans-serif;padding:20px}table{width:100%;border-collapse:collapse}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#f4f4f4}</style>');
  html.push('</head><body>');
  html.push('<h1>' + title + '</h1>');
  html.push('<table><thead><tr>' + headers.map(h => `<th>${h}</th>`).join('') + '</tr></thead>');
  html.push('<tbody>');
  rows.forEach(r => {
    html.push('<tr>' + r.map(c => `<td>${String(c)}</td>`).join('') + '</tr>');
  });
  html.push('</tbody></table>');
  html.push('</body></html>');
  win.document.write(html.join(''));
  win.document.close();
  setTimeout(() => { win.print(); }, 500);
}

const sortSelect = document.getElementById('ph-sort-select');
if (sortSelect) {
  sortSelect.addEventListener('change', () => {
    renderMedicines();
  });
}

const pdfExportBtn = document.getElementById('ph-pdf-export-btn');
if (pdfExportBtn) {
  pdfExportBtn.addEventListener('click', () => {
    const listToExport = filteredMedicines.length > 0 ? filteredMedicines : medicines;
    const headers = ['Medicine', 'Classification', 'Description', 'Quantity', 'Unit', 'Expiry Date', 'Status'];
    const rows = listToExport.map(m => {
      const stock = computeStockStatus(m.qty);
      const expiry = computeExpiryStatus(m.expiry_date);
      return [
        m.name,
        (m.drug_classification || 'rx').toUpperCase(),
        m.description || '—',
        m.qty,
        m.unit || '—',
        formatDate(m.expiry_date),
        `${stock.label} / ${expiry.label}`
      ];
    });
    generateReport('Pharmacy Inventory Report', headers, rows);
  });
}

const csvExportBtn = document.getElementById('ph-csv-export-btn');
if (csvExportBtn) {
  csvExportBtn.addEventListener('click', () => {
    const listToExport = filteredMedicines.length > 0 ? filteredMedicines : medicines;
    const headers = ['Medicine', 'Classification', 'Description', 'Quantity', 'Unit', 'Expiry Date', 'Stock Status', 'Expiry Status'];
    let csvContent = headers.join(',') + '\n';
    
    listToExport.forEach(m => {
      const stock = computeStockStatus(m.qty);
      const expiry = computeExpiryStatus(m.expiry_date);
      const row = [
        `"${m.name}"`,
        `"${(m.drug_classification || 'rx').toUpperCase()}"`,
        `"${m.description || ''}"`,
        m.qty,
        `"${m.unit || ''}"`,
        `"${m.expiry_date || ''}"`,
        `"${stock.label}"`,
        `"${expiry.label}"`
      ];
      csvContent += row.join(',') + '\n';
    });

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `pharmacy_inventory_${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  });
}

const csvImportBtn = document.getElementById('ph-csv-import-btn');
if (csvImportBtn && window.openCsvImport) {
  csvImportBtn.addEventListener('click', () => {
    openCsvImport({
      title: 'Import Medicine Inventory',
      templateHeaders: ['name', 'description', 'qty', 'unit', 'expiry_date'],
      requiredFields: ['name', 'qty'],
      fieldLabels: { 
        name: 'Medicine Name', 
        description: 'Description', 
        qty: 'Quantity', 
        unit: 'Unit', 
        expiry_date: 'Expiry Date' 
      },
      fieldTypes: { 
        qty: 'number', 
        expiry_date: 'date' 
      },
      onImport: async (rows) => {
        for (const row of rows) {
          await saveMedicine({
            id: null,
            name: row.name,
            description: row.description,
            qty: row.qty,
            unit: row.unit,
            expiry_date: row.expiry_date
          });
        }
      },
      onSuccess: async () => {
        await loadMedicines();
        renderMedicines();
      }
    });
  });
}

// ── OTC Dispensing Logic ──────────────────────────────────────────────────────

async function openOtcModal() {
  if (!otcModal) return;
  if (otcPatientNameInp) otcPatientNameInp.value = 'Walk-in Patient';
  if (otcNotesInp) otcNotesInp.value = '';

  if (!Array.isArray(medicines) || medicines.length === 0) {
    await loadMedicines();
  }

  const otcMeds = medicines.filter(m => (m.drug_classification || '').toLowerCase() === 'otc' && Number(m.qty) > 0);
  if (otcMeds.length === 0) {
    showToast('No Over-The-Counter (OTC) medicines with available stock found.', 'warning');
    return;
  }

  otcLineItems = [
    { medicineId: otcMeds[0].id, quantity: 1, instructions: '' }
  ];

  renderOtcLineItems();
  otcModal.classList.remove('hidden');
  otcModal.style.display = 'flex';
}

function closeOtcModal() {
  if (!otcModal) return;
  otcModal.classList.add('hidden');
  otcModal.style.display = 'none';
  otcLineItems = [];
}

function renderOtcLineItems() {
  if (!otcItemsContainer) return;
  const otcMeds = medicines.filter(m => (m.drug_classification || '').toLowerCase() === 'otc' && m.qty > 0);

  if (otcLineItems.length === 0) {
    otcItemsContainer.innerHTML = '<div style="color:#94a3b8; font-size:13px; text-align:center; padding:12px;">No medicines added yet. Click "+ Add Another Medicine" above.</div>';
    if (otcSummaryCounter) otcSummaryCounter.textContent = '0 items selected';
    return;
  }

  otcItemsContainer.innerHTML = otcLineItems.map((item, idx) => {
    const selectedMed = medicines.find(m => m.id === item.medicineId) || otcMeds[0];
    const maxQty = selectedMed ? selectedMed.qty : 1;

    const optionsHtml = otcMeds.map(m => `
      <option value="${m.id}" ${m.id === item.medicineId ? 'selected' : ''}>
        ${escHtml(m.name)} (Stock: ${m.qty}${m.unit ? ' ' + escHtml(m.unit) : ''})
      </option>
    `).join('');

    return `
      <div class="otc-line-row" data-index="${idx}" style="background:#fff; border:1px solid #e2e8f0; border-radius:10px; padding:10px; display:grid; grid-template-columns: 2fr 1fr 2fr auto; gap:8px; align-items:center;">
        <div>
          <label style="font-size:10px; color:#64748b; font-weight:700; text-transform:uppercase; display:block; margin-bottom:2px;">OTC Medicine</label>
          <select class="otc-med-select" data-index="${idx}" style="width:100%; padding:6px 8px; border:1px solid #cbd5e1; border-radius:6px; font-size:13px;">
            ${optionsHtml}
          </select>
        </div>
        <div>
          <label style="font-size:10px; color:#64748b; font-weight:700; text-transform:uppercase; display:block; margin-bottom:2px;">Qty (${maxQty} max)</label>
          <input type="number" class="otc-qty-input" data-index="${idx}" min="1" max="${maxQty}" value="${item.quantity}" style="width:100%; padding:6px 8px; border:1px solid #cbd5e1; border-radius:6px; font-size:13px; text-align:center;" />
        </div>
        <div>
          <label style="font-size:10px; color:#64748b; font-weight:700; text-transform:uppercase; display:block; margin-bottom:2px;">Instructions</label>
          <input type="text" class="otc-inst-input" data-index="${idx}" value="${escHtml(item.instructions || '')}" placeholder="e.g. 1 tab 3x a day" style="width:100%; padding:6px 8px; border:1px solid #cbd5e1; border-radius:6px; font-size:13px;" />
        </div>
        <div style="padding-top:14px;">
          <button type="button" class="otc-remove-line-btn ph-btn ph-btn-sm" data-index="${idx}" style="background:#fff1f2; color:#e11d48; border:1px solid #fecdd3; padding:5px 8px;" title="Remove line">✕</button>
        </div>
      </div>
    `;
  }).join('');

  if (otcSummaryCounter) {
    const totalQty = otcLineItems.reduce((acc, it) => acc + (parseInt(it.quantity, 10) || 0), 0);
    otcSummaryCounter.textContent = `${otcLineItems.length} medicine${otcLineItems.length !== 1 ? 's' : ''} (${totalQty} units)`;
  }
}

async function handleOtcDispenseSubmit() {
  if (otcLineItems.length === 0) {
    showToast('Add at least one medicine to dispense.', 'warning');
    return;
  }

  const patientName = (otcPatientNameInp?.value || '').trim() || 'Walk-in Patient';
  const notes = (otcNotesInp?.value || '').trim() || null;

  const payloadItems = [];
  const seenIds = new Set();

  for (let i = 0; i < otcLineItems.length; i++) {
    const it = otcLineItems[i];
    const medId = Number(it.medicineId);
    const qty = parseInt(it.quantity, 10);

    if (!medId) {
      showToast(`Please select a valid medicine for item #${i + 1}.`, 'warning');
      return;
    }
    if (seenIds.has(medId)) {
      showToast(`Duplicate medicine selected. Please combine quantities.`, 'warning');
      return;
    }
    seenIds.add(medId);

    const targetMed = medicines.find(m => m.id === medId);
    if (!targetMed) {
      showToast(`Medicine not found in inventory.`, 'error');
      return;
    }

    if (isNaN(qty) || qty <= 0) {
      showToast(`Enter a quantity greater than 0 for ${targetMed.name}.`, 'warning');
      return;
    }
    if (qty > targetMed.qty) {
      showToast(`Requested ${qty} for ${targetMed.name}, but only ${targetMed.qty} is in stock.`, 'warning');
      return;
    }

    payloadItems.push({
      medicine_id: medId,
      quantity: qty,
      instructions: (it.instructions || '').trim() || null
    });
  }

  setLoading(otcSubmitBtn, true);
  try {
    const sb = await getSupabase();
    const { data, error } = await sb.rpc('dispense_otc_medicines', {
      p_items: payloadItems,
      p_citizen_id: null,
      p_walkin_name: patientName,
      p_patient_name: patientName,
      p_notes: notes
    });

    if (error) throw new Error(error.message);
    if (data?.error) throw new Error(data.error);

    const refNo = data.reference_no || 'OTC-COMPLETED';
    showToast(`OTC Dispense complete (${refNo}). Stock updated.`, 'success');

    closeOtcModal();

    if (otcReceiptRef) otcReceiptRef.textContent = refNo;
    if (otcReceiptPatient) otcReceiptPatient.textContent = patientName;
    if (otcReceiptItems) {
      otcReceiptItems.innerHTML = payloadItems.map(p => {
        const m = medicines.find(x => x.id === p.medicine_id);
        return `<div style="display:flex; justify-content:space-between; margin-bottom:4px;">
          <span>• <strong>${escHtml(m?.name || 'Medicine')}</strong>${p.instructions ? ` <em>(${escHtml(p.instructions)})</em>` : ''}</span>
          <span style="font-weight:700; color:#0369a1;">${p.quantity} ${escHtml(m?.unit || '')}</span>
        </div>`;
      }).join('');
    }

    if (otcReceiptModal) {
      otcReceiptModal.classList.remove('hidden');
      otcReceiptModal.style.display = 'flex';
    }

    await loadMedicines();
    renderMedicines();

  } catch (err) {
    showToast(err.message || 'Failed to dispense OTC medicines.', 'error');
  } finally {
    setLoading(otcSubmitBtn, false);
  }
}

// Wire OTC event listeners
if (openOtcDispenseBtn) openOtcDispenseBtn.addEventListener('click', openOtcModal);
if (otcCancelBtn) otcCancelBtn.addEventListener('click', closeOtcModal);
if (otcModalCloseIcon) otcModalCloseIcon.addEventListener('click', closeOtcModal);
if (otcModal) {
  otcModal.addEventListener('click', (e) => {
    if (e.target === otcModal) closeOtcModal();
  });
}
if (otcAddLineBtn) {
  otcAddLineBtn.addEventListener('click', () => {
    const otcMeds = medicines.filter(m => (m.drug_classification || '').toLowerCase() === 'otc' && m.qty > 0);
    if (otcMeds.length === 0) {
      showToast('No in-stock OTC medicines available.', 'warning');
      return;
    }
    const usedIds = new Set(otcLineItems.map(it => it.medicineId));
    const nextMed = otcMeds.find(m => !usedIds.has(m.id)) || otcMeds[0];
    otcLineItems.push({ medicineId: nextMed.id, quantity: 1, instructions: '' });
    renderOtcLineItems();
  });
}
if (otcSubmitBtn) otcSubmitBtn.addEventListener('click', handleOtcDispenseSubmit);
if (otcReceiptCloseBtn) {
  otcReceiptCloseBtn.addEventListener('click', () => {
    if (otcReceiptModal) {
      otcReceiptModal.classList.add('hidden');
      otcReceiptModal.style.display = 'none';
    }
  });
}

if (otcItemsContainer) {
  otcItemsContainer.addEventListener('change', (e) => {
    const idx = parseInt(e.target.dataset.index, 10);
    if (isNaN(idx) || !otcLineItems[idx]) return;

    if (e.target.classList.contains('otc-med-select')) {
      otcLineItems[idx].medicineId = Number(e.target.value);
      renderOtcLineItems();
    } else if (e.target.classList.contains('otc-qty-input')) {
      otcLineItems[idx].quantity = Math.max(1, parseInt(e.target.value, 10) || 1);
      renderOtcLineItems();
    } else if (e.target.classList.contains('otc-inst-input')) {
      otcLineItems[idx].instructions = e.target.value;
    }
  });

  otcItemsContainer.addEventListener('input', (e) => {
    const idx = parseInt(e.target.dataset.index, 10);
    if (isNaN(idx) || !otcLineItems[idx]) return;

    if (e.target.classList.contains('otc-inst-input')) {
      otcLineItems[idx].instructions = e.target.value;
    } else if (e.target.classList.contains('otc-qty-input')) {
      otcLineItems[idx].quantity = parseInt(e.target.value, 10) || 0;
    }
  });

  otcItemsContainer.addEventListener('click', (e) => {
    const removeBtn = e.target.closest('.otc-remove-line-btn');
    if (!removeBtn) return;
    const idx = parseInt(removeBtn.dataset.index, 10);
    if (!isNaN(idx) && otcLineItems[idx]) {
      otcLineItems.splice(idx, 1);
      renderOtcLineItems();
    }
  });
}

// ── Init ──────────────────────────────────────────────────────────────────────
async function reloadSchemaCache() {
  try {
    const url = String(window.UKONEK_CONFIG?.SUPABASE_URL || '').trim();
    const key = String(window.UKONEK_CONFIG?.SUPABASE_ANON_KEY || '').trim();
    if (!url || !key) return;
    // POST to the PostgREST schema cache reload endpoint
    await fetch(`${url}/rest/v1/`, {
      method: 'GET',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Accept-Profile': 'public' }
    });
  } catch (_) {}
}

window.addEventListener('pagehide', () => {
  handleAutoLogoutOnClose();
});

window.addEventListener('beforeunload', () => {
  handleAutoLogoutOnClose();
});

async function init() {
  const allowed = await guardAccess();
  if (!allowed) return;

  try {
    const user = await ensurePharmacistSession();
    const name = [user.first_name, user.last_name].filter(Boolean).join(' ') || user.username || 'Pharmacist';
    if (userNameEl) userNameEl.textContent = `${name} — Pharmacist`;
  } catch (_) {
    return;
  }

  // Start presence tracking so the pharmacist is seen as Active in Recent Staff lists
  startPresenceHeartbeat();

  await reloadSchemaCache();
  await loadMedicines();
  renderMedicines();
}

init();
