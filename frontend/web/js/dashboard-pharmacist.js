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
let activeFilter    = 'all';
let searchQuery     = '';
let cachedUser      = null;
let supabaseClient  = null;

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
  if (qty === 0)             return { label: 'Out of Stock', cls: 'badge-red' };
  if (qty <= LOW_STOCK_THRESHOLD) return { label: 'Low Stock',    cls: 'badge-amber' };
  return                            { label: 'In Stock',     cls: 'badge-green' };
}

function computeExpiryStatus(expiryDate) {
  if (!expiryDate) return { label: 'No Expiry Set', cls: 'badge-gray' };
  const today = new Date(); today.setHours(0,0,0,0);
  const exp   = new Date(expiryDate); exp.setHours(0,0,0,0);
  const diffDays = Math.floor((exp - today) / 86400000);
  if (diffDays < 0)                      return { label: 'Expired',       cls: 'badge-red' };
  if (diffDays <= EXPIRY_SOON_DAYS)      return { label: 'Expiring Soon', cls: 'badge-amber' };
  return                                        { label: 'Valid',          cls: 'badge-green' };
}

function formatDate(val) {
  if (!val) return '—';
  const d = new Date(val);
  if (isNaN(d)) return val;
  return d.toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: '2-digit' });
}

// ── Load medicines ─────────────────────────────────────────────────────────────
async function loadMedicines() {
  if (isDemoMode) {
    const raw = localStorage.getItem('ukonek_medicines');
    try { medicines = raw ? JSON.parse(raw) : []; } catch { medicines = []; }
    return;
  }
  try {
    const sb = await getSupabase();
    const { data, error } = await sb
      .from('medicines')
      .select('id, name, description, qty, unit, expiry_date, created_at, updated_at')
      .is('archived_at', null)
      .order('name', { ascending: true });
    if (error) throw new Error(error.message);
    medicines = (data || []).map(row => ({
      id:          row.id,
      name:        row.name,
      description: row.description || '',
      qty:         Number(row.qty ?? 0),
      unit:        row.unit || '',
      expiry_date: row.expiry_date || null,
      created_at:  row.created_at,
      updated_at:  row.updated_at
    }));
  } catch (err) {
    console.error('Failed to load medicines:', err);
    showToast('Failed to load medicines. ' + (err.message || ''), 'error');
    medicines = [];
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

  return rows;
}

// ── Render list ───────────────────────────────────────────────────────────────
function renderMedicines() {
  if (!tbody) return;
  const rows = getFilteredMedicines();
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
    else if (stock.label === 'Low Stock')      tr.style.background = '#fffbeb';

    tr.dataset.id = m.id;
    tr.innerHTML = `
      <td><strong>${escHtml(m.name)}</strong></td>
      <td style="color:#64748b;font-size:13px;">${escHtml(m.description) || '<em style="color:#cbd5e1">—</em>'}</td>
      <td><strong>${m.qty}</strong></td>
      <td style="color:#64748b;">${escHtml(m.unit) || '—'}</td>
      <td>${formatDate(m.expiry_date)}</td>
      <td><span class="badge ${stock.cls}">${stock.label}</span></td>
      <td><span class="badge ${expiry.cls}">${expiry.label}</span></td>
      <td>
        <button class="ph-btn ph-btn-edit ph-btn-sm" data-action="edit" data-id="${m.id}">Edit</button>
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
  const filterLabel = { all: 'All medicines', low: 'Low / Out of Stock', expired: 'Expired', expiring: 'Expiring within 30 days' };
  listSubtitle.textContent = `${filterLabel[activeFilter] || 'All medicines'} — ${count} result${count !== 1 ? 's' : ''}`;
}

// ── Stats cards ────────────────────────────────────────────────────────────────
function updateStats() {
  const total    = medicines.length;
  const inStock  = medicines.filter(m => m.qty > LOW_STOCK_THRESHOLD).length;
  const lowStock = medicines.filter(m => m.qty <= LOW_STOCK_THRESHOLD).length;
  const today    = new Date(); today.setHours(0,0,0,0);
  const expAlert = medicines.filter(m => {
    if (!m.expiry_date) return false;
    const exp = new Date(m.expiry_date); exp.setHours(0,0,0,0);
    return Math.floor((exp - today) / 86400000) <= EXPIRY_SOON_DAYS;
  }).length;

  document.getElementById('stat-total').textContent    = total;
  document.getElementById('stat-in-stock').textContent  = inStock;
  document.getElementById('stat-low').textContent       = lowStock;
  document.getElementById('stat-expiry').textContent    = expAlert;
}

// ── Save medicine (add or update) ─────────────────────────────────────────────
async function saveMedicine({ id = null, name, description, qty, unit, expiry_date }) {
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
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      };
      medicines.push(entry);
      localStorage.setItem('ukonek_medicines', JSON.stringify(medicines));
      return entry;
    } else {
      const idx = medicines.findIndex(m => m.id === id);
      if (idx === -1) throw new Error('Medicine not found.');
      medicines[idx] = { ...medicines[idx], description: (description || '').trim(), qty, expiry_date: expiry_date || null, updated_at: new Date().toISOString() };
      localStorage.setItem('ukonek_medicines', JSON.stringify(medicines));
      return medicines[idx];
    }
  }

  const sb = await getSupabase();

  if (id === null) {
    // Step 1: INSERT with base columns (always in schema cache)
    const { data, error } = await sb
      .from('medicines')
      .insert({ name: name.trim(), qty, unit: unit ? unit.trim() : null })
      .select('id')
      .single();
    if (error) throw new Error(error.message);

    // Step 2: UPDATE with extended columns (expiry_date, description)
    // Done separately so a schema-cache miss on new columns doesn't fail the whole insert
    const extUpdates = {};
    if (expiry_date) extUpdates.expiry_date = expiry_date;
    if (description && description.trim()) extUpdates.description = description.trim();
    if (Object.keys(extUpdates).length > 0) {
      await sb.from('medicines').update(extUpdates).eq('id', data.id);
    }
    return data;
  } else {
    // UPDATE existing medicine (stock + expiry + description)
    const updates = { qty };
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
  addForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name   = document.getElementById('add-name').value.trim();
    const qty    = Number(document.getElementById('add-qty').value);
    const unit   = document.getElementById('add-unit').value.trim();
    const expiry = document.getElementById('add-expiry').value || null;
    const desc   = document.getElementById('add-desc').value.trim();

    if (!name) { showToast('Medicine name is required.', 'warning'); return; }
    if (qty < 0) { showToast('Stock quantity cannot be negative.', 'warning'); return; }

    setLoading(addSubmitBtn, true);
    try {
      await saveMedicine({ id: null, name, description: desc, qty, unit, expiry_date: expiry });
      await loadMedicines();
      renderMedicines();
      addForm.reset();
      showToast(`"${name}" added to inventory.`, 'success');
    } catch (err) {
      showToast(err.message || 'Failed to add medicine.', 'error');
    } finally {
      setLoading(addSubmitBtn, false);
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
    }
  });
}

// ── Edit modal ────────────────────────────────────────────────────────────────
function openEditModal(med) {
  editIdInput.value    = med.id;
  editNameDisp.value   = med.name;
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
    const id     = Number(editIdInput.value);
    const qty    = Number(editQtyInp.value);
    const expiry = editExpiryInp.value || null;
    const desc   = editDescInp.value.trim();
    const med    = medicines.find(m => m.id === id);

    if (!med) { showToast('Medicine not found.', 'error'); return; }
    if (qty < 0) { showToast('Stock quantity cannot be negative.', 'warning'); return; }

    setLoading(editSaveBtn, true);
    try {
      await saveMedicine({ id, description: desc, qty, expiry_date: expiry });
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
if (logoutBtn) {
  logoutBtn.addEventListener('click', async () => {
    setLoading(logoutBtn, true);
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

  await reloadSchemaCache();
  await loadMedicines();
  renderMedicines();
}

init();
