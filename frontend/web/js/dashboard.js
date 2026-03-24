import { getAuthenticatedStaffProfile, signOutStaff, sendStaffApprovalEmail } from './services/authService.js';
import {
  listStaff,
  listPendingStaff,
  approvePendingStaff,
  rejectPendingStaff,
  deleteStaffAccount
} from './services/staffService.js';

const sidebar = document.getElementById('sidebar');
const burger = document.getElementById('burger');
const back = document.getElementById('back');

function showToast(message, type = 'info') {
  const containerId = 'toast-container';
  let container = document.getElementById(containerId);
  if (!container) {
    container = document.createElement('div');
    container.id = containerId;
    container.className = 'toast-container';
    document.body.appendChild(container);
  }
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  requestAnimationFrame(() => { toast.classList.add('show'); });
  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => { toast.remove(); }, 240);
  }, 4200);
}

// --- Sidebar ---
function state() {
  if (!sidebar) return;
  const collapsed = sidebar.classList.contains('collapsed');
  const slid = sidebar.classList.contains('slid');
  burger.textContent = (slid || !collapsed) ? '←' : '☰';
  if (back) back.style.display = (collapsed && !slid) ? 'none' : 'inline-block';
}

if (burger) {
  burger.addEventListener('click', () => {
    if (window.innerWidth <= 900) {
      sidebar.classList.toggle('slid');
      sidebar.classList.remove('collapsed');
    } else {
      sidebar.classList.toggle('collapsed');
    }
    state();
  });
  window.addEventListener('resize', state);
}

if (back) {
  back.addEventListener('click', () => {
    sidebar.classList.add('collapsed');
    sidebar.classList.remove('slid');
    state();
  });
}

document.addEventListener('click', (e) => {
  if (window.innerWidth <= 900 && sidebar && sidebar.classList.contains('slid')) {
    const inside = sidebar.contains(e.target) || (burger && burger.contains(e.target)) || (back && back.contains(e.target));
    if (!inside) { sidebar.classList.remove('slid'); state(); }
  }
});

state();

// --- Logout ---
async function performLogout() {
  try {
    await signOutStaff();
  } catch (error) {
    console.error('Logout error:', error);
  } finally {
    window.location.replace('./index.html');
  }
}

const logoutBtn = document.getElementById('logout-btn');
const logoutConfirmModal = document.getElementById('logout-confirm-modal');
const logoutConfirmYesBtn = document.getElementById('logout-confirm-yes');
const logoutConfirmNoBtn = document.getElementById('logout-confirm-no');

if (logoutBtn) {
  logoutBtn.addEventListener('click', () => {
    if (logoutConfirmModal) { logoutConfirmModal.style.display = 'flex'; return; }
    performLogout();
  });
}
if (logoutConfirmYesBtn) {
  logoutConfirmYesBtn.addEventListener('click', () => {
    if (logoutConfirmModal) logoutConfirmModal.style.display = 'none';
    performLogout();
  });
}
if (logoutConfirmNoBtn) {
  logoutConfirmNoBtn.addEventListener('click', () => {
    if (logoutConfirmModal) logoutConfirmModal.style.display = 'none';
  });
}

// --- Session check via Supabase Auth ---
async function ensureAuthenticatedSession() {
  try {
    const profile = await getAuthenticatedStaffProfile();
    if (!profile) {
      window.location.replace('./index.html');
      return null;
    }
    return profile;
  } catch (error) {
    console.error('Session check failed:', error);
    window.location.replace('./index.html');
    return null;
  }
}

function isAdminUser(user) {
  return String(user?.role || '').trim().toLowerCase() === 'admin';
}

function toTitleCase(value) {
  const lower = String(value || '').trim().toLowerCase();
  if (!lower) return 'Unknown';
  return lower.charAt(0).toUpperCase() + lower.slice(1);
}

function getDisplayFirstName(user) {
  const preferred = user?.first_name || user?.firstName || user?.firstname;
  if (preferred && String(preferred).trim()) return String(preferred).trim();
  return String(user?.username || '').trim() || 'User';
}

function updateNonAdminWorkspace(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  const roleTitle = toTitleCase(role);

  const titleNode = document.getElementById('non-admin-title');
  if (titleNode) titleNode.textContent = `${roleTitle} Workspace`;

  const subtitleNode = document.getElementById('non-admin-subtitle');
  if (subtitleNode) {
    subtitleNode.textContent = role === 'doctor'
      ? 'Track your daily clinical tasks and coordinate with the admin team for account-related requests.'
      : 'Track your daily operations and coordinate with the admin team for account-related requests.';
  }

  const permissionsNode = document.getElementById('non-admin-permissions');
  if (permissionsNode) {
    permissionsNode.textContent = 'Admin Command Center modules are restricted to admin accounts. Your role can continue using non-admin workspace functions.';
  }

  const usernameNode = document.getElementById('non-admin-username');
  if (usernameNode) usernameNode.textContent = user?.username || '—';

  const roleNode = document.getElementById('non-admin-role');
  if (roleNode) roleNode.textContent = roleTitle;

  const emailNode = document.getElementById('non-admin-email');
  if (emailNode) emailNode.textContent = user?.email || '—';
}

function applyRoleAccess(user) {
  const adminAccess = isAdminUser(user);
  if (!adminAccess) {
    document.querySelectorAll('.admin-only').forEach((element) => { element.classList.add('hidden'); });
  }

  const userNameNode = document.querySelector('.user-name');
  if (userNameNode) userNameNode.textContent = getDisplayFirstName(user);

  const userRoleNode = document.querySelector('.user-pos');
  if (userRoleNode) {
    const roleText = String(user?.role || 'Staff');
    userRoleNode.textContent = roleText.charAt(0).toUpperCase() + roleText.slice(1);
  }

  const nonAdminSection = document.getElementById('non-admin-section');
  if (adminAccess) {
    if (nonAdminSection) nonAdminSection.classList.add('hidden');
    return;
  }

  hideAllSections();
  clearActiveNav();
  updateNonAdminWorkspace(user);
  if (nonAdminSection) nonAdminSection.classList.remove('hidden');
}

window.addEventListener('pageshow', async (event) => {
  const navEntries = performance.getEntriesByType('navigation');
  const navType = navEntries && navEntries.length > 0 ? navEntries[0].type : '';
  if (!event.persisted && navType !== 'back_forward') return;
  const sessionUser = await ensureAuthenticatedSession();
  if (sessionUser) applyRoleAccess(sessionUser);
});

// --- Search ---
const searchInput = document.getElementById('search-input');
if (searchInput) {
  searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const q = searchInput.value.trim();
      if (q) console.log('Search:', q);
    }
  });
}

// --- Dropdown for Users menu ---
const navBtn = document.querySelector('.nav-btn');
const dropdownMenu = document.querySelector('.dropdown-menu');
if (navBtn && dropdownMenu) {
  navBtn.addEventListener('click', (e) => {
    e.preventDefault();
    dropdownMenu.classList.toggle('hidden');
  });
}

// --- Section navigation ---
const navLinks = document.querySelectorAll('.nav-item[data-section]');
const dropdownItems = document.querySelectorAll('.dropdown-item');
const dashboardSection = document.getElementById('dashboard-section');
const usersSection = document.getElementById('users-section');

const statTotalStaff = document.getElementById('stat-total-staff');
const statPendingStaff = document.getElementById('stat-pending-staff');
const statDoctors = document.getElementById('stat-doctors');
const statActiveStaff = document.getElementById('stat-active-staff');
const dashboardPendingPreview = document.getElementById('dashboard-pending-preview');
const dashboardActivePreview = document.getElementById('dashboard-active-preview');
const dashboardLastSync = document.getElementById('dashboard-last-sync');

const dashRefreshBtn = document.getElementById('dash-refresh-btn');
const dashOpenPendingBtn = document.getElementById('dash-open-pending-btn');
const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');

function hideAllSections() {
  if (dashboardSection) dashboardSection.classList.add('hidden');
  if (usersSection) usersSection.classList.add('hidden');
  const nonAdminSection = document.getElementById('non-admin-section');
  if (nonAdminSection) nonAdminSection.classList.add('hidden');
  const accountMgmt = document.getElementById('account-management');
  if (accountMgmt) accountMgmt.classList.add('hidden');
}

function clearActiveNav() {
  navLinks.forEach((link) => link.classList.remove('is-active'));
  if (navBtn) navBtn.classList.remove('is-active');
}

navLinks.forEach(link => {
  link.addEventListener('click', (e) => {
    e.preventDefault();
    const section = link.getAttribute('data-section');
    hideAllSections();
    clearActiveNav();
    link.classList.add('is-active');
    if (section === 'dashboard' && dashboardSection) dashboardSection.classList.remove('hidden');
    if (dropdownMenu) dropdownMenu.classList.add('hidden');
  });
});

dropdownItems.forEach(item => {
  item.addEventListener('click', (e) => {
    e.preventDefault();
    const section = item.getAttribute('data-section');
    hideAllSections();
    clearActiveNav();
    if (navBtn) navBtn.classList.add('is-active');
    if (usersSection) usersSection.classList.remove('hidden');
    const subsection = document.getElementById(section);
    if (subsection) subsection.classList.remove('hidden');
  });
});

const dashboardLink = document.querySelector('.nav-item[data-section="dashboard"]');
if (dashboardLink && !dashboardLink.classList.contains('hidden')) {
  dashboardLink.classList.add('is-active');
}

// --- Data store ---
const storedAccounts = new Map();
let latestStaffList = [];
let latestPendingList = [];

function formatDateTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString();
}

function renderDashboardInsights() {
  if (statTotalStaff) statTotalStaff.textContent = String(latestStaffList.length);
  if (statPendingStaff) statPendingStaff.textContent = String(latestPendingList.length);

  const doctorsCount = latestStaffList.filter((u) => String(u.role || '').toLowerCase() === 'doctor').length;
  if (statDoctors) statDoctors.textContent = String(doctorsCount);

  const activeCount = latestStaffList.filter((u) => String(u.status || '').toLowerCase() === 'active').length;
  if (statActiveStaff) statActiveStaff.textContent = String(activeCount);

  if (dashboardPendingPreview) {
    const rows = latestPendingList.slice(0, 5);
    dashboardPendingPreview.innerHTML = rows.length
      ? rows.map((user) => `
          <tr>
            <td class="table-cell">${user.username || '—'}</td>
            <td class="table-cell">${user.employee_id || '—'}</td>
            <td class="table-cell">${user.role ? user.role.charAt(0).toUpperCase() + user.role.slice(1) : '—'}</td>
            <td class="table-cell">${formatDateTime(user.created_at)}</td>
          </tr>
        `).join('')
      : '<tr><td class="table-cell" colspan="4">No pending registrations.</td></tr>';
  }

  if (dashboardActivePreview) {
    const rows = latestStaffList.slice(0, 5);
    dashboardActivePreview.innerHTML = rows.length
      ? rows.map((user) => `
          <tr>
            <td class="table-cell">${user.username || '—'}</td>
            <td class="table-cell">${user.role ? user.role.charAt(0).toUpperCase() + user.role.slice(1) : '—'}</td>
            <td class="table-cell"><span class="badge-${String(user.status || '').toLowerCase()}">${user.status || '—'}</span></td>
            <td class="table-cell">${formatDateTime(user.created_at)}</td>
          </tr>
        `).join('')
      : '<tr><td class="table-cell" colspan="4">No active accounts found.</td></tr>';
  }

  if (dashboardLastSync) {
    dashboardLastSync.textContent = `Last synced: ${new Date().toLocaleTimeString()}`;
  }
}

function openUsersSubsection(subsectionId) {
  hideAllSections();
  if (usersSection) usersSection.classList.remove('hidden');
  const subsection = document.getElementById(subsectionId);
  if (subsection) subsection.classList.remove('hidden');
}

// =======================================================================
// Load staff data via Supabase
// =======================================================================
async function loadStaffData() {
  try {
    latestStaffList = await listStaff();

    const accountsTbody = document.getElementById('accounts-tbody');
    if (accountsTbody) {
      accountsTbody.innerHTML = '';
      latestStaffList.forEach(user => {
        const identifier = user.username || user.employee_id;
        storedAccounts.set(identifier, user);

        const row = document.createElement('tr');
        row.className = 'account-row';
        row.setAttribute('data-role', user.role.toLowerCase());
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">${user.username || '—'}</td>
          <td class="table-cell">${user.employee_id || '—'}</td>
          <td class="table-cell">${user.role.charAt(0).toUpperCase() + user.role.slice(1)}</td>
          <td class="table-cell"><span class="badge-${user.status.toLowerCase()}">${user.status}</span></td>
        `;
        accountsTbody.appendChild(row);
        attachAccountRowListener(row);
      });
    }

    renderDashboardInsights();
  } catch (error) {
    console.error('Error loading staff:', error);
  }
}

// =======================================================================
// Load pending staff data via Supabase
// =======================================================================
async function loadPendingStaffData() {
  try {
    latestPendingList = await listPendingStaff();

    const pendingTbody = document.getElementById('pending-tbody');
    if (pendingTbody) {
      pendingTbody.innerHTML = '';
      latestPendingList.forEach(user => {
        const identifier = user.username || user.employee_id;
        storedAccounts.set(identifier, user);

        const row = document.createElement('tr');
        row.className = 'pending-row';
        row.setAttribute('data-role', user.role.toLowerCase());
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">${user.username || '—'}</td>
          <td class="table-cell">${user.employee_id || '—'}</td>
          <td class="table-cell">${user.role.charAt(0).toUpperCase() + user.role.slice(1)}</td>
          <td class="table-cell">${new Date(user.created_at).toLocaleString()}</td>
        `;
        pendingTbody.appendChild(row);
        attachPendingRowListener(row);
      });
    }

    renderDashboardInsights();
  } catch (error) {
    console.error('Error loading pending staff:', error);
  }
}

// --- Init data ---
async function initDashboardData() {
  const sessionUser = await ensureAuthenticatedSession();
  if (!sessionUser) return;

  applyRoleAccess(sessionUser);

  if (!isAdminUser(sessionUser)) return;

  if (dashboardSection) dashboardSection.classList.remove('hidden');
  if (dashboardLink) dashboardLink.classList.add('is-active');
  await Promise.all([loadStaffData(), loadPendingStaffData()]);
}

initDashboardData();

if (dashRefreshBtn) {
  dashRefreshBtn.addEventListener('click', async () => {
    await Promise.all([loadStaffData(), loadPendingStaffData()]);
    showToast('Dashboard data refreshed.', 'info');
  });
}

if (dashOpenPendingBtn) {
  dashOpenPendingBtn.addEventListener('click', () => {
    openUsersSubsection('account-management');
    if (tabPending) tabPending.click();
  });
}

if (refreshAccountsBtn) {
  refreshAccountsBtn.addEventListener('click', async () => {
    await Promise.all([loadStaffData(), loadPendingStaffData()]);
    showToast('Account tables refreshed.', 'info');
  });
}

// --- Role filter ---
const roleFilter = document.getElementById('role-filter');
if (roleFilter) {
  roleFilter.addEventListener('change', (e) => {
    const filterValue = e.target.value.toLowerCase();
    document.querySelectorAll('.account-row').forEach(row => {
      const role = row.getAttribute('data-role');
      row.style.display = (filterValue === '' || role === filterValue) ? '' : 'none';
    });
  });
}

// --- Account Details Modal ---
let currentAccountData = null;
let currentAction = null;

function attachAccountRowListener(row) {
  row.addEventListener('click', () => {
    const identifier = row.getAttribute('data-id');
    const user = storedAccounts.get(identifier);
    if (!user) return;

    currentAccountData = { ...user };

    const firstName = String(user.first_name || '').trim();
    const lastName = String(user.last_name || '').trim();
    const fullName = `${firstName} ${lastName}`.replace(/\s+/g, ' ').trim();
    const birthdayValue = user.birthday ? new Date(user.birthday) : null;
    const birthdayText = birthdayValue && !Number.isNaN(birthdayValue.getTime())
      ? birthdayValue.toLocaleDateString() : '—';

    document.getElementById('modal-name').textContent = fullName || user.username || '—';
    document.getElementById('modal-email').textContent = user.email || '—';
    document.getElementById('modal-role').textContent = user.role.charAt(0).toUpperCase() + user.role.slice(1);
    document.getElementById('modal-status').textContent = user.status;
    document.getElementById('modal-contact').textContent = user.employee_id || '—';
    document.getElementById('modal-bday').textContent = birthdayText;

    const extraFields = ['address'];
    extraFields.forEach(field => {
      const el = document.getElementById(`modal-${field}`);
      if (el) el.textContent = user[field] || '—';
    });

    document.getElementById('modal-confirm-section').style.display = 'none';
    document.getElementById('modal-actions').style.display = 'flex';

    document.getElementById('account-modal').style.display = 'flex';
  });
}

document.querySelectorAll('.account-row').forEach(attachAccountRowListener);

// --- Tab switching ---
const tabRegistered = document.getElementById('tab-registered');
const tabPending = document.getElementById('tab-pending');
const registeredPane = document.getElementById('registered-pane');
const pendingPane = document.getElementById('pending-pane');
if (tabRegistered && tabPending && registeredPane && pendingPane) {
  tabRegistered.addEventListener('click', () => {
    tabRegistered.classList.add('active');
    tabPending.classList.remove('active');
    registeredPane.classList.remove('hidden');
    pendingPane.classList.add('hidden');
  });
  tabPending.addEventListener('click', () => {
    tabPending.classList.add('active');
    tabRegistered.classList.remove('active');
    pendingPane.classList.remove('hidden');
    registeredPane.classList.add('hidden');
  });
}

// --- Pending modal logic ---
function attachPendingRowListener(row) {
  row.addEventListener('click', () => {
    const identifier = row.getAttribute('data-id');
    const stored = storedAccounts.get(identifier);
    if (!stored) return;

    let pendingModal = document.getElementById('pending-modal');
    if (!pendingModal) {
      pendingModal = document.createElement('div');
      pendingModal.id = 'pending-modal';
      pendingModal.className = 'modal-overlay';
      pendingModal.innerHTML = `
        <div class="modal-content">
          <h2 class="modal-title">Pending Registration</h2>
          <div class="modal-group"><label class="modal-label">Username</label><p id="pending-username" class="modal-text"></p></div>
          <div class="modal-group"><label class="modal-label">Employee ID</label><p id="pending-employee-id" class="modal-text"></p></div>
          <div class="modal-group"><label class="modal-label">Email</label><p id="pending-email" class="modal-text"></p></div>
          <div class="modal-group"><label class="modal-label">Role</label><p id="pending-role" class="modal-text"></p></div>
          <div class="modal-group"><label class="modal-label">Submitted</label><p id="pending-submitted" class="modal-text"></p></div>
          <div class="modal-actions">
            <button id="pending-accept" class="btn btn-confirm">ACCEPT</button>
            <button id="pending-reject" class="btn btn-delete">REJECT</button>
            <button id="pending-close" class="btn-close">Close</button>
          </div>
          <div id="pending-confirm" class="modal-confirm-section" style="display:none">
            <p id="pending-confirm-text" class="modal-confirm-text"></p>
            <div class="flex gap-12">
              <button id="pending-confirm-yes" class="btn btn-confirm">Confirm</button>
              <button id="pending-confirm-no" class="btn-cancel">Cancel</button>
            </div>
          </div>
        </div>`;
      document.body.appendChild(pendingModal);

      document.getElementById('pending-close').addEventListener('click', () => {
        pendingModal.style.display = 'none';
      });
    }

    document.getElementById('pending-username').textContent = stored.username || '—';
    document.getElementById('pending-employee-id').textContent = stored.employee_id || '—';
    document.getElementById('pending-email').textContent = stored.email || '—';
    document.getElementById('pending-role').textContent = stored.role ? (stored.role.charAt(0).toUpperCase() + stored.role.slice(1)) : '';
    document.getElementById('pending-submitted').textContent = formatDateTime(stored.created_at);

    pendingModal.style.display = 'flex';

    const showConfirm = (text, onConfirmAction) => {
      const global = document.getElementById('pending-action-confirm-modal');
      if (!global) {
        document.getElementById('pending-confirm-text').textContent = text;
        document.getElementById('pending-confirm').style.display = 'block';
        const yes = document.getElementById('pending-confirm-yes');
        const no = document.getElementById('pending-confirm-no');
        const cleanup = () => { document.getElementById('pending-confirm').style.display = 'none'; yes.onclick = null; no.onclick = null; };
        yes.onclick = () => { cleanup(); onConfirmAction(); pendingModal.style.display = 'none'; };
        no.onclick = () => { cleanup(); };
        return;
      }

      if (pendingModal) pendingModal.style.display = 'none';
      document.getElementById('pending-action-text').textContent = text;
      global.style.display = 'flex';
      const yes = document.getElementById('pending-action-yes');
      const no = document.getElementById('pending-action-no');
      const cleanup = () => { global.style.display = 'none'; yes.onclick = null; no.onclick = null; };
      yes.onclick = () => { cleanup(); onConfirmAction(); };
      no.onclick = () => { cleanup(); };
    };

    // --- Approve via Supabase RPC ---
    document.getElementById('pending-accept').onclick = () => {
      showConfirm('Accept this registration and activate the account?', async () => {
        try {
          await approvePendingStaff(stored.id);
          if (stored.email) {
            try {
              await sendStaffApprovalEmail(stored.email);
              showToast('Account approved. Approval email sent.', 'success');
            } catch (mailError) {
              console.error('Approval email error:', mailError);
              showToast('Account approved, but failed to send email notification.', 'info');
            }
          } else {
            showToast('Account approved successfully.', 'success');
          }
          loadStaffData();
          loadPendingStaffData();
        } catch (err) {
          console.error(err);
          showToast(err?.message || 'Server error', 'error');
        }
      });
    };

    // --- Reject via Supabase RPC ---
    document.getElementById('pending-reject').onclick = () => {
      showConfirm('Reject this registration? This will permanently delete the submission.', async () => {
        try {
          await rejectPendingStaff(stored.id);
          showToast('Account rejected', 'success');
          loadPendingStaffData();
        } catch (err) {
          console.error(err);
          showToast(err?.message || 'Server error', 'error');
        }
      });
    };
  });
}

document.querySelectorAll('.pending-row').forEach(attachPendingRowListener);

// --- Account Modal close ---
const closeModalBtn = document.getElementById('modal-close-btn');
if (closeModalBtn) {
  closeModalBtn.addEventListener('click', () => {
    document.getElementById('account-modal').style.display = 'none';
    currentAccountData = null;
    currentAction = null;
  });
}

// --- Edit button ---
const editBtn = document.getElementById('modal-edit-btn');
if (editBtn) {
  editBtn.addEventListener('click', () => {
    currentAction = 'edit';
    document.getElementById('modal-confirm-text').textContent = 'Are you sure you want to edit this account?';
    document.getElementById('modal-actions').style.display = 'none';
    document.getElementById('modal-confirm-section').style.display = 'block';
  });
}

// --- Delete button ---
const deleteBtn = document.getElementById('modal-delete-btn');
if (deleteBtn) {
  deleteBtn.addEventListener('click', () => {
    currentAction = 'delete';
    document.getElementById('modal-confirm-text').textContent = 'Are you sure you want to delete this account? This action cannot be undone.';
    document.getElementById('modal-actions').style.display = 'none';
    document.getElementById('modal-confirm-section').style.display = 'block';
  });
}

// --- Confirm button (delete via Supabase RPC) ---
const confirmBtn = document.getElementById('modal-confirm-btn');
if (confirmBtn) {
  confirmBtn.addEventListener('click', async () => {
    if (currentAction === 'edit') {
      console.log('Editing account:', currentAccountData);
      alert('Account updated successfully');
      document.getElementById('account-modal').style.display = 'none';
      currentAccountData = null;
      currentAction = null;
    } else if (currentAction === 'delete') {
      try {
        if (!currentAccountData || !currentAccountData.id) {
          showToast('Unable to delete: missing account id.', 'error');
          return;
        }

        await deleteStaffAccount(currentAccountData.id);

        document.getElementById('account-modal').style.display = 'none';
        document.getElementById('modal-confirm-section').style.display = 'none';
        document.getElementById('modal-actions').style.display = 'flex';
        currentAccountData = null;
        currentAction = null;

        await Promise.all([loadStaffData(), loadPendingStaffData()]);
        showToast('Account deleted successfully.', 'success');
      } catch (error) {
        console.error('Delete account error:', error);
        showToast('Server error during deletion.', 'error');
      }
    }
  });
}

// --- Cancel button ---
const cancelBtn = document.getElementById('modal-cancel-btn');
if (cancelBtn) {
  cancelBtn.addEventListener('click', () => {
    document.getElementById('modal-confirm-section').style.display = 'none';
    document.getElementById('modal-actions').style.display = 'flex';
    currentAction = null;
  });
}
