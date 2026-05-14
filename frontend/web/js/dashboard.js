const sidebar = document.getElementById('sidebar');
const burger = document.getElementById('burger');

const getApiBase = () => {
  const configBase = String(window.UKONEK_CONFIG?.API_BASE || '').trim();
  if (configBase) return configBase;
  return '';
};
const API_BASE = getApiBase();
const isApiMode = API_BASE.length > 0;
const isDemoMode = Boolean(window.UKONEK_CONFIG?.FORCE_DEMO);
let authServiceModulePromise = null;
let staffServiceModulePromise = null;
let supabaseModulePromise = null;
let authSessionModulePromise = null;

let cachedSessionUser = null;
let sessionUserRole = null;
const DEFAULT_SECTION_ID = 'dashboard-section';
const STAFF_PRESENCE_TIMEOUT_MS = 3 * 60 * 1000;
const STAFF_PRESENCE_HEARTBEAT_MS = 60 * 1000;
const ADMIN_DASHBOARD_REFRESH_MS = 15000;
let presenceHeartbeatTimer = null;
let adminDashboardRefreshTimer = null;
let adminDashboardRefreshInFlight = false;
const DASHBOARD_REQUEST_TIMEOUT_MS = 15000;

function withTimeout(promise, timeoutMs, timeoutMessage) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(timeoutMessage));
      }, timeoutMs);
    })
  ]);
}
const pagePreloader = document.getElementById('page-preloader');
let pagePreloaderDismissed = false;

function dismissPagePreloader() {
  if (pagePreloaderDismissed) return;
  pagePreloaderDismissed = true;
  if (pagePreloader) {
    pagePreloader.classList.add('hidden');
  }
  document.body.classList.remove('dashboard-loading');
}

// Dismiss preloader shortly after the page finishes loading
if (document.readyState === 'complete') {
  setTimeout(dismissPagePreloader, 500);
} else {
  window.addEventListener('load', () => {
    setTimeout(dismissPagePreloader, 500);
  });
}
// Failsafe: always dismiss after 5 seconds even if window.load never fires
setTimeout(dismissPagePreloader, 5000);

/**
 * Flicker-free DOM swap: builds new content into a DocumentFragment off-screen,
 * then replaces the container's children in a single paint. Prevents the blank
 * flash caused by clearing innerHTML before new data is ready.
 * @param {Element} container - The element whose children will be replaced.
 * @param {function(DocumentFragment): void} buildFn - Receives a fragment; append rows into it.
 */
function swapContainer(container, buildFn) {
  if (!container) return;
  const fragment = document.createDocumentFragment();
  buildFn(fragment);
  container.replaceChildren(fragment);
}

function setLoading(btn, isLoading) {
  if (!btn) return;
  const label = btn.querySelector('.btn-label');
  const spinner = btn.querySelector('.btn-spinner');
  if (isLoading) {
    btn.disabled = true;
    btn.classList.add('is-loading');
    if (label) label.dataset.originalText = label.textContent;
    if (label) label.textContent = 'SAVING...';
  } else {
    btn.disabled = false;
    btn.classList.remove('is-loading');
    if (label && label.dataset.originalText) {
      label.textContent = label.dataset.originalText;
    }
  }
}

function getSectionFromHash() {
  const value = String(window.location.hash || '').replace(/^#/, '').trim();
  if (!value) return null;
  return document.getElementById(value) ? value : null;
}

function setSectionHash(sectionId) {
  if (!sectionId) return;
  const nextHash = `#${sectionId}`;
  if (window.location.hash === nextHash) return;

  if (window.history && typeof window.history.replaceState === 'function') {
    window.history.replaceState(null, '', nextHash);
    return;
  }

  window.location.hash = sectionId;
}

function detectRoleFromTitle() {
  const storedRole = String(sessionStorage.getItem('ukonek_role') || '').trim().toLowerCase();
  if (storedRole) return storedRole;

  const title = document.title.toLowerCase();
  if (title.includes('admin')) return 'doctor';
  if (title.includes('pharmacist')) return 'pharmacist';
  return 'nurse';
}

const DEMO_REGISTERED_USERS = [
  {
    username: 'bcruz',
    first_name: 'Ben',
    last_name: 'Cruz',
    employee_id: 'UK-1007',
    role: 'nurse',
    status: 'Active',
    availability_status: 'available',
    created_at: '2024-11-10T10:30:00Z',
    email: 'bcruz@ukonek.local',
    birthday: '1988-07-22'
  },
  {
    username: 'creyes',
    first_name: 'Carla',
    last_name: 'Reyes',
    employee_id: 'UK-1015',
    role: 'doctor',
    status: 'Inactive',
    availability_status: 'unavailable',
    created_at: '2024-12-01T08:15:00Z',
    email: 'creyes@ukonek.local',
    birthday: '1985-01-14'
  }
];

const demoDelay = (ms = 500) => new Promise((resolve) => setTimeout(resolve, ms));
const makeDemoId = () => (typeof crypto !== 'undefined' && crypto.randomUUID
  ? crypto.randomUUID()
  : `demo-${Date.now()}-${Math.random().toString(16).slice(2)}`);

const makeDemoEmployeeId = () => {
  const existingNumbers = DEMO_REGISTERED_USERS
    .map((user) => {
      const match = String(user.employee_id || '').match(/(\d+)/);
      return match ? Number(match[1]) : NaN;
    })
    .filter(Number.isFinite);

  const nextNumber = existingNumbers.length > 0
    ? Math.max(...existingNumbers) + 1
    : 1001;

  return `UK-${nextNumber}`;
};


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

  requestAnimationFrame(() => {
    toast.classList.add('show');
  });

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => {
      toast.remove();
    }, 240);
  }, 4200);
}

function state() {
  if (!sidebar || !burger) return;
  const collapsed = sidebar.classList.contains('collapsed');
  const slid = sidebar.classList.contains('slid');
  const isMobile = window.innerWidth <= 900;
  const expanded = isMobile ? slid : !collapsed;
  burger.setAttribute('aria-expanded', expanded ? 'true' : 'false');
  burger.classList.toggle('is-expanded', expanded);
}

function loadAuthServiceModule() {
  if (!authServiceModulePromise) {
    authServiceModulePromise = import('./services/authService.js').catch((error) => {
      authServiceModulePromise = null;
      throw error;
    });
  }
  return authServiceModulePromise;
}

function loadStaffServiceModule() {
  if (!staffServiceModulePromise) {
    staffServiceModulePromise = import('./services/staffService.js').catch((error) => {
      staffServiceModulePromise = null;
      throw error;
    });
  }
  return staffServiceModulePromise;
}

function loadSupabaseModule() {
  if (!supabaseModulePromise) {
    supabaseModulePromise = import('./supabase-config.js').catch((error) => {
      supabaseModulePromise = null;
      throw error;
    });
  }
  return supabaseModulePromise;
}

function loadAuthSessionModule() {
  if (!authSessionModulePromise) {
    authSessionModulePromise = import('./services/sessionAuth.js').catch((error) => {
      authSessionModulePromise = null;
      throw error;
    });
  }
  return authSessionModulePromise;
}

if (burger) {
  burger.addEventListener('click', () => {
    if (window.innerWidth <= 900) {
      sidebar.classList.toggle('slid');
      sidebar.classList.remove('collapsed');
    } else {
      closeSidebarDropdownMenus();
      sidebar.classList.toggle('collapsed');
    }
    state();
  });
  window.addEventListener('resize', state);
}



document.addEventListener('click', (e) => {
  if (window.innerWidth <= 900 && sidebar && sidebar.classList.contains('slid')) {
    const inside = sidebar.contains(e.target) || (burger && burger.contains(e.target));
    if (!inside) {
      sidebar.classList.remove('slid');
      state();
    }
  }
});

state();

async function performLogout() {
  try {
    const authService = await loadAuthServiceModule();
    await authService.signOutStaff();
    const authSession = await loadAuthSessionModule();
    authSession.clearAuthSessionMeta();
    sessionStorage.removeItem('ukonek_role');
  } catch (error) {
    console.warn('Sign out warning:', error);
  } finally {
    window.location.replace('./index.html');
  }
}


const logoutBtn = document.getElementById('logout-btn');
const logoutConfirmModal = document.getElementById('logout-confirm-modal');
const logoutConfirmYesBtn = document.getElementById('logout-confirm-yes');
const logoutConfirmNoBtn = document.getElementById('logout-confirm-no');
const notifBtn = document.getElementById('notif-btn');
const notificationPanel = document.getElementById('notification-panel');
const notificationList = document.getElementById('notification-list');
const notificationEmptyState = document.getElementById('notification-empty');
const notificationCloseBtn = document.getElementById('notif-close-btn');

function getNotificationDismissStorageKey() {
  const today = new Date();
  const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  const userKey = String(cachedSessionUser?.id || sessionUserRole || 'guest').trim();
  return `ukonek_notif_dismissed_${userKey}_${dateKey}`;
}

function getDismissedNotificationIds() {
  try {
    const raw = localStorage.getItem(getNotificationDismissStorageKey());
    const parsed = raw ? JSON.parse(raw) : [];
    return new Set(Array.isArray(parsed) ? parsed.map((value) => String(value)) : []);
  } catch (_) {
    return new Set();
  }
}

function setDismissedNotificationIds(idSet) {
  localStorage.setItem(
    getNotificationDismissStorageKey(),
    JSON.stringify(Array.from(idSet))
  );
}

function dismissNotification(id) {
  if (!id) return;
  const dismissed = getDismissedNotificationIds();
  dismissed.add(String(id));
  setDismissedNotificationIds(dismissed);
}

function showLogoutConfirmModal() {
  if (!logoutConfirmModal) return;
  logoutConfirmModal.classList.remove('hidden');
}

function hideLogoutConfirmModal() {
  if (!logoutConfirmModal) return;
  logoutConfirmModal.classList.add('hidden');
}

function isLogoutConfirmModalOpen() {
  return Boolean(logoutConfirmModal && !logoutConfirmModal.classList.contains('hidden'));
}

if (logoutBtn) {
  logoutBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      showLogoutConfirmModal();
      return;
    }
    performLogout();
  });
}

if (logoutConfirmYesBtn) {
  logoutConfirmYesBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      hideLogoutConfirmModal();
    }
    performLogout();
  });
}

if (logoutConfirmNoBtn) {
  logoutConfirmNoBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      hideLogoutConfirmModal();
    }
  });
}

if (logoutConfirmModal) {
  logoutConfirmModal.addEventListener('click', (event) => {
    if (event.target === logoutConfirmModal) {
      hideLogoutConfirmModal();
    }
  });
}

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && isLogoutConfirmModalOpen()) {
    hideLogoutConfirmModal();
  }
});

if (notifBtn && notificationPanel) {
  notifBtn.addEventListener('click', (event) => {
    event.preventDefault();
    toggleNotificationPanel();
  });
}

if (notificationCloseBtn) {
  notificationCloseBtn.addEventListener('click', () => hideNotificationPanel());
}

const dialogModal = document.getElementById('dialog-modal');
const dialogTitle = document.getElementById('dialog-title');
const dialogMessage = document.getElementById('dialog-message');
const dialogInput1Wrap = document.getElementById('dialog-input-1-wrap');
const dialogInput1Label = document.getElementById('dialog-input-1-label');
const dialogInput1 = document.getElementById('dialog-input-1');
const dialogInput2Wrap = document.getElementById('dialog-input-2-wrap');
const dialogInput2Label = document.getElementById('dialog-input-2-label');
const dialogInput2 = document.getElementById('dialog-input-2');
const dialogError = document.getElementById('dialog-error');
const dialogConfirmBtn = document.getElementById('dialog-confirm-btn');
const dialogCancelBtn = document.getElementById('dialog-cancel-btn');

let activeDialogResolver = null;

function closeDialogModal(result = { confirmed: false, values: [] }) {
  if (dialogModal) dialogModal.classList.add('hidden');
  if (activeDialogResolver) {
    activeDialogResolver(result);
    activeDialogResolver = null;
  }
}

function openDialogModal({
  title = 'Confirm',
  message = '',
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  inputs = []
} = {}) {
  if (!dialogModal) {
    return Promise.resolve({ confirmed: false, values: [] });
  }

  if (dialogTitle) dialogTitle.textContent = title;
  if (dialogMessage) dialogMessage.textContent = message;
  if (dialogConfirmBtn) dialogConfirmBtn.textContent = confirmText;
  if (dialogCancelBtn) dialogCancelBtn.textContent = cancelText;
  if (dialogError) {
    dialogError.textContent = '';
    dialogError.classList.add('hidden');
  }

  const inputConfigs = Array.isArray(inputs) ? inputs.slice(0, 2) : [];
  const first = inputConfigs[0] || null;
  const second = inputConfigs[1] || null;

  if (dialogInput1Wrap && dialogInput1 && dialogInput1Label) {
    if (first) {
      dialogInput1Wrap.classList.remove('hidden');
      dialogInput1Label.textContent = first.label || 'Input';
      dialogInput1.type = first.type || 'text';
      dialogInput1.placeholder = first.placeholder || '';
      dialogInput1.value = first.initialValue || '';
    } else {
      dialogInput1Wrap.classList.add('hidden');
      dialogInput1.value = '';
    }
  }

  if (dialogInput2Wrap && dialogInput2 && dialogInput2Label) {
    if (second) {
      dialogInput2Wrap.classList.remove('hidden');
      dialogInput2Label.textContent = second.label || 'Input';
      dialogInput2.type = second.type || 'text';
      dialogInput2.placeholder = second.placeholder || '';
      dialogInput2.value = second.initialValue || '';
    } else {
      dialogInput2Wrap.classList.add('hidden');
      dialogInput2.value = '';
    }
  }

  dialogModal.classList.remove('hidden');
  setTimeout(() => {
    if (first && dialogInput1) dialogInput1.focus();
    else if (dialogConfirmBtn) dialogConfirmBtn.focus();
  }, 0);

  return new Promise((resolve) => {
    activeDialogResolver = resolve;
  });
}

if (dialogCancelBtn) {
  dialogCancelBtn.addEventListener('click', () => closeDialogModal({ confirmed: false, values: [] }));
}

if (dialogConfirmBtn) {
  dialogConfirmBtn.addEventListener('click', () => {
    const values = [];
    if (dialogInput1Wrap && !dialogInput1Wrap.classList.contains('hidden') && dialogInput1) {
      values.push(String(dialogInput1.value || '').trim());
    }
    if (dialogInput2Wrap && !dialogInput2Wrap.classList.contains('hidden') && dialogInput2) {
      values.push(String(dialogInput2.value || '').trim());
    }
    closeDialogModal({ confirmed: true, values });
  });
}

if (dialogModal) {
  dialogModal.addEventListener('click', (event) => {
    if (event.target === dialogModal) {
      closeDialogModal({ confirmed: false, values: [] });
    }
  });
}

async function ensureAuthenticatedSession(force = false) {
  if (!force && cachedSessionUser) {
    sessionUserRole = cachedSessionUser.role || sessionUserRole;
    return cachedSessionUser;
  }

  try {
    const authService = await loadAuthServiceModule();
    const profile = await withTimeout(
      authService.getAuthenticatedStaffProfile(),
      DASHBOARD_REQUEST_TIMEOUT_MS,
      'Session validation timed out. Please refresh the page.'
    );

    if (!profile) {
      window.location.replace('./index.html');
      return null;
    }

    cachedSessionUser = profile;
    sessionUserRole = String(profile.role || detectRoleFromTitle()).toLowerCase();
    const authSession = await loadAuthSessionModule();
    authSession.setAuthSessionMeta({
      role: sessionUserRole,
      userId: profile?.id || null,
      email: profile?.email || null
    });
    return profile;
  } catch (error) {
    console.error('Session validation failed:', error);
    window.location.replace('./index.html');
    return null;
  }
}

function getSessionRole() {
  const role = (sessionUserRole || detectRoleFromTitle() || '').toLowerCase();
  return role === 'staff' ? 'nurse' : role;
}


function isAdminUser(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  return role === 'admin' || role === 'doctor' || role === 'nurse' || role === 'staff';
}

const SECTION_ROLE_RULES = {
  'dashboard-section': ['doctor', 'nurse', 'pharmacist'],
  'users-section': ['doctor', 'nurse', 'pharmacist'],
  'reports-section': ['doctor', 'nurse'],
  'medicine-section': ['doctor', 'nurse', 'pharmacist'],
  'consultation-section': ['doctor', 'nurse', 'pharmacist'],
  'schedule-section': ['doctor', 'nurse', 'pharmacist'],
  'vitals-section': ['doctor', 'nurse', 'pharmacist'],
  'queue-section': ['doctor', 'nurse', 'pharmacist'],

  'profile-section': ['doctor', 'nurse', 'pharmacist']
};

function isSectionAllowedForRole(sectionId, role) {
  let roleKey = String(role || '').trim().toLowerCase();
  if (roleKey === 'staff') roleKey = 'nurse';
  const allowed = SECTION_ROLE_RULES[sectionId];
  if (!allowed || allowed.length === 0) return true;
  return allowed.includes(roleKey);
}

function syncRoleNavigationAccess(role) {
  document.querySelectorAll('[data-section]').forEach((element) => {
    const sectionId = element.getAttribute('data-section');
    if (!sectionId || element.classList.contains('section-top')) return;

    if (isSectionAllowedForRole(sectionId, role)) {
      element.classList.remove('hidden');
    } else {
      element.classList.add('hidden');
    }
  });
}

function toTitleCase(value) {
  const lower = String(value || '').trim().toLowerCase();
  if (!lower) return 'Unknown';
  return lower.charAt(0).toUpperCase() + lower.slice(1);
}

function getDisplayFirstName(user) {
  const preferred =
    user?.first_name ||
    user?.firstName ||
    user?.firstname;

  if (preferred && String(preferred).trim()) {
    return String(preferred).trim();
  }

  return String(user?.username || '').trim() || 'User';
}

function isDoctorRole(value) {
  return String(value || '').trim().toLowerCase() === 'doctor';
}

function isScheduleRole(value) {
  const key = String(value || '').trim().toLowerCase();
  return key === 'doctor' || key === 'nurse' || key === 'pharmacist';
}

function getDoctorDisplayName(doctor) {
  if (!doctor) return 'Doctor';
  const first = String(doctor.first_name || '').trim();
  const last = String(doctor.last_name || '').trim();
  const full = `${first} ${last}`.trim();
  return full || doctor.username || 'Doctor';
}

function getSpecializationValue(user) {
  return String(
    user?.doctor_specialization ||
    user?.doctorSpecialization ||
    user?.specialization ||
    ''
  ).trim();
}

function getDoctorSpecializationText(doctor) {
  const value = getSpecializationValue(doctor);
  return value || '—';
}

const AVAILABILITY_LABELS = {
  available: 'Available',
  on_break: 'On Break',
  unavailable: 'Unavailable'
};

function normalizeAvailabilityStatus(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (raw === 'on break' || raw === 'on_break') return 'on_break';
  if (raw === 'unavailable') return 'unavailable';
  return 'available';
}

function getAvailabilityStatusText(user) {
  const status = normalizeAvailabilityStatus(user?.availability_status || user?.availabilityStatus);
  return AVAILABILITY_LABELS[status] || 'Available';
}

function getAvailabilityBadgeClass(user) {
  const status = normalizeAvailabilityStatus(user?.availability_status || user?.availabilityStatus);
  if (status === 'available') return 'badge-available';
  if (status === 'on_break') return 'badge-break';
  return 'badge-unavailable';
}

function getRoleLogoConfig(roleValue) {
  const key = String(roleValue || '').trim().toLowerCase();
  switch (key) {
    case 'admin':
      return { className: 'role-logo-admin', label: 'Admin Dashboard', icon: 'shield' };
    case 'doctor':
      return { className: 'role-logo-doctor', label: 'Doctor', icon: 'stethoscope' };
    case 'nurse':
      return { className: 'role-logo-nurse', label: 'Nurse', icon: 'heart' };
    case 'pharmacist':
      return { className: 'role-logo-pharmacist', label: 'Pharmacist', icon: 'capsule' };
    case 'staff':
      return { className: 'role-logo-nurse', label: 'Nurse Dashboard', icon: 'heart' };
    case 'citizen':
      return { className: 'role-logo-citizen', label: 'Citizen', icon: 'user' };
    default:
      return { className: 'role-logo-default', label: 'User', icon: 'user' };
  }
}

function getRoleLogoSvg(iconName) {
  switch (iconName) {
    case 'shield':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l7 3v6c0 5-3.5 9.5-7 11-3.5-1.5-7-6-7-11V5l7-3z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9 12l2 2 4-4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    case 'stethoscope':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3v5a4 4 0 0 0 8 0V3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M10 12v2a4 4 0 0 0 8 0v-2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="18" cy="10" r="2" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>';
    case 'heart':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7-4.4-9-8.5C1.3 9.2 3 6 6.3 6c2.1 0 3.2 1.2 3.7 2 .5-.8 1.6-2 3.7-2C17 6 18.7 9.2 17 12.5 15 16.6 8 21 8 21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    case 'spark':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l1.8 4.2L18 9l-4.2 1.8L12 15l-1.8-4.2L6 9l4.2-1.8L12 3z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M18.5 15l.9 2.1L21.5 18l-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9.9-2.1z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    case 'briefcase':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="7" width="18" height="12" rx="2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M3 12h18" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>';
    default:
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M5 20a7 7 0 0 1 14 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
  }
}

function applyRoleLogos(roleValue) {
  const config = getRoleLogoConfig(roleValue);
  const targets = [
    document.getElementById('topbar-role-logo'),
    document.getElementById('profile-role-logo')
  ];
  const roleClasses = [
    'role-logo-admin',
    'role-logo-doctor',
    'role-logo-nurse',
    'role-logo-pharmacist',
    'role-logo-staff',
    'role-logo-citizen',
    'role-logo-default'
  ];

  targets.forEach((node) => {
    if (!node) return;
    node.classList.remove(...roleClasses);
    node.classList.add(config.className);
    node.innerHTML = getRoleLogoSvg(config.icon);
    node.title = config.label;
    node.setAttribute('aria-label', `${config.label} role icon`);
  });
}

function updateNonAdminWorkspace(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  const roleTitle = toTitleCase(role);

  const titleNode = document.getElementById('non-admin-title');
  if (titleNode) titleNode.textContent = `${roleTitle} Workspace`;

  const subtitleNode = document.getElementById('non-admin-subtitle');
  if (subtitleNode) {
    subtitleNode.textContent = (role === 'doctor' || role === 'admin')
      ? 'Track your daily clinical tasks and coordinate with the lead doctor for account-related requests.'
      : 'Track your daily operations and coordinate with the lead nurse for account-related requests.';
  }

  const permissionsNode = document.getElementById('non-admin-permissions');
  if (permissionsNode) {
    permissionsNode.textContent = 'Doctor Dashboard modules are restricted to doctor accounts. Your role can continue using the standard workspace.';
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
  const role = String(user?.role || detectRoleFromTitle()).trim().toLowerCase();
  document.querySelectorAll('.admin-only').forEach((element) => {
    const isSectionContainer = element.classList.contains('section-top');
    if (adminAccess) {
      // Keep section visibility controlled by navigation helpers.
      if (!isSectionContainer) {
        element.classList.remove('hidden');
      }
    } else {
      element.classList.add('hidden');
    }
  });

  syncRoleNavigationAccess(role);

  sessionUserRole = role || sessionUserRole;

  const userNameNode = document.querySelector('.user-name');
  if (userNameNode) {
    userNameNode.textContent = getDisplayFirstName(user);
  }

  const userRoleNode = document.querySelector('.user-pos');
  if (userRoleNode) {
    const roleText = String(user?.role || 'Nurse');
    userRoleNode.textContent = roleText.charAt(0).toUpperCase() + roleText.slice(1);
  }
  applyRoleLogos(user?.role || 'nurse');
  applyConsultationAccess();

  // Update main dashboard titles based on role
  const mainDashTitle = document.getElementById('main-dashboard-title');
  const mainTopbarTitle = document.getElementById('main-topbar-title');
  if (mainDashTitle || mainTopbarTitle) {
    const roleText = (role === 'doctor' || role === 'admin') ? 'Doctor' : toTitleCase(role);
    if (mainDashTitle) mainDashTitle.textContent = `${roleText} Dashboard`;
    if (mainTopbarTitle) mainTopbarTitle.textContent = `${roleText} Systems Overview`;
  }

  const nonAdminSection = document.getElementById('non-admin-section');
  if (adminAccess) {
    if (nonAdminSection) nonAdminSection.classList.add('hidden');
    return;
  }

  const registeredPane = document.getElementById('registered-pane');
  const patientsPane = document.getElementById('citizens-pane');
  const usersNavBtn = document.querySelector('.nav-btn[data-section="users-section"]');

  if (registeredPane) registeredPane.classList.add('hidden');
  if (patientsPane) patientsPane.classList.remove('hidden');
  if (usersNavBtn) {
    usersNavBtn.dataset.pane = 'citizens-pane';
  }

  updateNonAdminWorkspace(user);
  if (nonAdminSection) nonAdminSection.classList.add('hidden');
}

const MEDICINE_PERMISSIONS = {
  doctor:     { adjust: false, add: false },
  nurse:      { adjust: false, add: false },
  pharmacist: { adjust: true, add: true },
  pharmacist: { adjust: true, add: true }
};

const CONSULTATION_PERMISSIONS = {
  doctor: { consult: true, prescribe: true }
};

function canAdjustMedicineInventory(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(MEDICINE_PERMISSIONS[key]?.adjust);
}

function canAddNewMedicine(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(MEDICINE_PERMISSIONS[key]?.add);
}

function canConsultPatients(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(CONSULTATION_PERMISSIONS[key]?.consult);
}

function canCreatePrescriptions(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(CONSULTATION_PERMISSIONS[key]?.prescribe);
}

function applyConsultationAccess() {
  const canConsult = canConsultPatients();
  const consultBtn = document.getElementById('open-consult-modal-btn');
  if (consultBtn) {
    consultBtn.classList.toggle('hidden', !canConsult);
    consultBtn.disabled = !canConsult;
  }
}

window.addEventListener('pageshow', async (event) => {
  const navEntries = performance.getEntriesByType('navigation');
  const navType = navEntries && navEntries.length > 0 ? navEntries[0].type : '';
  const restoredFromHistory = event.persisted || navType === 'back_forward';
  if (!restoredFromHistory) {
    return;
  }

  const sessionUser = await ensureAuthenticatedSession();
  if (sessionUser) {
    applyRoleAccess(sessionUser);
  }
});

// Search input handler
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

// Dropdown toggle + unified nav handler (no more overlaps)
const navContainer = document.querySelector('.nav');

function closeSidebarDropdownMenus(exceptItem = null) {
  document.querySelectorAll('.nav-item.dropdown').forEach((item) => {
    if (exceptItem && item === exceptItem) return;
    item.classList.remove('open');
    const menu = item.querySelector('.dropdown-menu');
    if (menu) menu.classList.add('hidden');
  });
}

if (navContainer) {
  navContainer.addEventListener('click', (e) => {
    const el = e.target.closest('[data-section], .nav-btn');
    if (!el) return;

    e.preventDefault();
    e.stopPropagation();

    const sectionId = el.getAttribute('data-section');
    const sectionOptions = {
      tab: el.dataset.tab,
      pane: el.dataset.pane
    };
    const isDropdownBtn = el.classList.contains('nav-btn');
    const isDropdownItem = el.classList.contains('dropdown-item');
    const parentItem = el.closest('.nav-item.dropdown');
    const activeMenu = parentItem ? parentItem.querySelector('.dropdown-menu') : null;

    // Keep submenu parent open while navigating within dropdown items.
    if (isDropdownItem && activeMenu) {
      closeSidebarDropdownMenus(parentItem);
      activeMenu.classList.remove('hidden');
      if (parentItem) parentItem.classList.add('open');
    }

    // Toggle dropdown when clicking a nav button.
    if (isDropdownBtn && activeMenu) {
      const willOpen = activeMenu.classList.contains('hidden');
      closeSidebarDropdownMenus(parentItem);
      activeMenu.classList.toggle('hidden', !willOpen);
      if (parentItem) parentItem.classList.toggle('open', willOpen);
    }

    // Nav activation logic
    if (sectionId || isDropdownBtn) {
      const targetId = sectionId || el.getAttribute('data-section');
      if (targetId) {
        navigateToSection(targetId, sectionOptions);
      }
    }
  });
}

document.addEventListener('click', (event) => {
  if (!sidebar) return;
  if (sidebar.contains(event.target)) return;
  closeSidebarDropdownMenus();
});

function parseDateValue(value) {
  if (!value) return null;
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    const [year, month, day] = value.split('-').map(Number);
    return new Date(year, month - 1, day);
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function getTodayNotifications() {
  const startOfDay = new Date();
  startOfDay.setHours(0, 0, 0, 0);
  const endOfDay = new Date(startOfDay);
  endOfDay.setDate(endOfDay.getDate() + 1);

  const isToday = (value) => {
    const parsed = parseDateValue(value);
    return parsed && parsed >= startOfDay && parsed < endOfDay;
  };

  const items = [];

  latestAnnouncementsList.forEach((announcement) => {
    if (!isToday(announcement?.created_at)) return;
    const parsedDate = parseDateValue(announcement?.created_at);
    const id = `announcement:${announcement?.id || announcement?.title || ''}:${parsedDate ? parsedDate.toISOString().slice(0, 10) : ''}`;
    items.push({
      id,
      type: 'Announcement',
      title: announcement?.title || 'Announcement',
      detail: announcement?.preview || announcement?.content || '',
      date: parsedDate
    });
  });

  latestFeedbackList.forEach((feedback) => {
    if (!isToday(feedback?.created_at)) return;
    const parsedDate = parseDateValue(feedback?.created_at);
    const id = `feedback:${feedback?.id || feedback?.subject || ''}:${parsedDate ? parsedDate.toISOString().slice(0, 10) : ''}`;
    items.push({
      id,
      type: 'Feedback',
      title: feedback?.subject || 'Feedback received',
      detail: feedback?.from || 'Anonymous',
      date: parsedDate
    });
  });

  const dismissed = getDismissedNotificationIds();
  return items
    .filter((item) => !dismissed.has(String(item.id)))
    .sort((a, b) => {
    const aTime = a.date ? a.date.getTime() : 0;
    const bTime = b.date ? b.date.getTime() : 0;
    return bTime - aTime;
  });
}

function populateNotificationPanel() {
  if (!notificationList) return;
  const items = getTodayNotifications();
  notificationList.innerHTML = '';

  if (!items.length) {
    if (notificationEmptyState) notificationEmptyState.classList.remove('hidden');
    return;
  }

  if (notificationEmptyState) notificationEmptyState.classList.add('hidden');

  items.forEach((item) => {
    const li = document.createElement('li');
    li.className = 'notification-item';
    li.setAttribute('data-type', item.type.toLowerCase());

    const body = document.createElement('div');
    body.className = 'notification-body';
    
    const header = document.createElement('div');
    header.className = 'notification-header';
    
    const typeLabel = document.createElement('span');
    typeLabel.className = `notif-type notif-type-${item.type.toLowerCase()}`;
    typeLabel.textContent = item.type.toUpperCase();
    header.appendChild(typeLabel);

    const title = document.createElement('span');
    title.className = 'notification-title';
    title.textContent = item.title;
    header.appendChild(title);
    
    body.appendChild(header);

    const meta = document.createElement('div');
    meta.className = 'notif-meta';
    const timeStamp = item.date
      ? item.date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true })
      : 'Today';
    meta.textContent = item.detail ? `${timeStamp} • ${item.detail}` : timeStamp;
    body.appendChild(meta);

    li.appendChild(body);

    const clearBtn = document.createElement('button');
    clearBtn.type = 'button';
    clearBtn.className = 'notification-dismiss';
    clearBtn.textContent = '×';
    clearBtn.setAttribute('aria-label', 'Clear notification');
    clearBtn.addEventListener('click', () => {
      dismissNotification(item.id);
      populateNotificationPanel();
    });
    li.appendChild(clearBtn);

    notificationList.appendChild(li);
  });
}

function showNotificationPanel() {
  if (!notificationPanel) return;
  populateNotificationPanel();
  notificationPanel.classList.remove('hidden');
}

function hideNotificationPanel() {
  if (!notificationPanel) return;
  notificationPanel.classList.add('hidden');
}

function toggleNotificationPanel() {
  if (!notificationPanel) return;
  const willShow = notificationPanel.classList.contains('hidden');
  if (willShow) showNotificationPanel();
  else hideNotificationPanel();
}

document.addEventListener('click', (event) => {
  if (!notificationPanel || notificationPanel.classList.contains('hidden')) return;
  if (notificationPanel.contains(event.target)) return;
  if (notifBtn && notifBtn.contains(event.target)) return;
  hideNotificationPanel();
});

async function showSection(sectionId, options = {}) {
  if (!sectionId) return;

  const user = await ensureAuthenticatedSession();
  if (!user) return;
  let role = String(user?.role || getSessionRole()).toLowerCase();
  if (role === 'staff') role = 'nurse';
  if (!isSectionAllowedForRole(sectionId, role)) {
    showToast('Access denied for this section.', 'warning');
    if (sectionId !== 'profile-section') {
      showSection('profile-section');
    }
    return;
  }

  const targetSection = document.getElementById(sectionId);
  if (targetSection) {
    targetSection.classList.remove('hidden');
    
    // Dynamic refresh for section content
    switch (sectionId) {
      case 'schedule-section':
        loadSchedules(user);
        break;
      case 'profile-section':
        if (user) populateProfile(user);
        break;
      case 'medicine-section':
      case 'consultation-section':
        initClinicalData();
        break;
      case 'dashboard-section':
        if (isAdminUser(user) && latestStaffList.length === 0) {
          await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
        }
        renderDashboardInsights();
        break;
      case 'reports-section':
        initReportsSection();
        const subTab = options.tab || 'tab-announcements';
        if (subTab === 'tab-stats') {
          renderClinicalStats();
        }
        break;
      case 'lab-section':
        initLabSection();
        break;
      case 'queue-section':
        if (typeof appointments !== 'undefined' && appointments.loadQueueTickets) {
          appointments.loadQueueTickets();
        }
        break;
      case 'vitals-section':
        initVitalsSection();
        break;
      case 'consultation-section':
        initClinicalData();
        initConsultationTabs();
        break;
      // Add more as needed
    }
    const { tab, pane } = options;

    if (sectionId === 'users-section') {
      const defaultPane = isAdminUser(user) ? 'registered-pane' : 'citizens-pane';
      const targetPane = pane || defaultPane;

      if (isAdminUser(user) && latestStaffList.length === 0) {
        await loadStaffData();
      }

      // Always refresh citizens when opening the Citizens pane (or for non-admin default view)
      // to avoid stale/empty first-render tables.
      if (targetPane === 'citizens-pane' || !isAdminUser(user) || latestPatientsList.length === 0) {
        await loadPatientData();
      }

      if (pane === 'registration-pane') {
        toggleUsersPane('registration-pane');
      } else {
        toggleUsersPane('accounts-pane');
        revealPane(targetPane);
      }
    } else if (pane) {
      revealPane(pane);
    }

    if (tab) {
      const tabBtn = document.getElementById(tab);
      if (tabBtn) tabBtn.click();
    }

    return;
  }
}

// Registration handlers from script.js (adapted for dashboard)
const EYE_OPEN_ICON = `
<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path fill="currentColor" d="M12 5c-5.5 0-9.3 4.1-10.7 6.1a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19s9.3-4.1 10.7-6.1a1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5zm0 11a5 5 0 1 1 0-10 5 5 0 0 1 0 10zm0-2.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/>
</svg>`;

const EYE_CLOSED_ICON = `
<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path fill="currentColor" d="M2.3 1.3a1 1 0 0 0-1.4 1.4l3 3A13.8 13.8 0 0 0 1.3 11a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19a12 12 0 0 0 4.6-.9l3.1 3.1a1 1 0 1 0 1.4-1.4zm7.5 10.3a2.5 2.5 0 0 0 3.6 2.4l-3.5-3.5c0 .4-.1.7-.1 1.1zM12 7a5 5 0 0 1 5 5c0 .7-.1 1.3-.4 1.9l1.5 1.5a13.8 13.8 0 0 0 4.6-4.4 1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5c-1.4 0-2.7.3-3.8.8l1.5 1.5c.6-.2 1.5-.3 2.3-.3z"/>
</svg>`;

function setupPasswordVisibilityToggles(root = document) {
  const passwordInputs = root.querySelectorAll('input[type="password"]');
  passwordInputs.forEach((input) => {
    if (input.dataset.toggleAttached === 'true') return;
    const wrapper = document.createElement('div');
    wrapper.className = 'password-input-wrap';
    input.parentNode.insertBefore(wrapper, input);
    wrapper.appendChild(input);
    const toggleBtn = document.createElement('button');
    toggleBtn.type = 'button';
    toggleBtn.className = 'password-toggle';
    toggleBtn.setAttribute('aria-label', 'Show password');
    toggleBtn.setAttribute('aria-pressed', 'false');
    toggleBtn.innerHTML = EYE_OPEN_ICON;
    toggleBtn.addEventListener('click', () => {
      const showPassword = input.type === 'password';
      input.type = showPassword ? 'text' : 'password';
      toggleBtn.innerHTML = showPassword ? EYE_CLOSED_ICON : EYE_OPEN_ICON;
      toggleBtn.setAttribute('aria-label', showPassword ? 'Hide password' : 'Show password');
      toggleBtn.setAttribute('aria-pressed', showPassword ? 'true' : 'false');
    });
    wrapper.appendChild(toggleBtn);
    input.dataset.toggleAttached = 'true';
  });
}

const registerForm = document.getElementById('register-form');
const registerSubmitBtn = document.getElementById('register-submit-btn');
const registrationSuccessModal = document.getElementById('registration-success-modal');
const regSuccessDashboardBtn = document.getElementById('reg-success-dashboard-btn');
const regSuccessUsersBtn = document.getElementById('reg-success-users-btn');
const backToDashboardBtn = document.getElementById('back-to-dashboard-btn');
const registrationBackBtn = document.getElementById('registration-back-btn');

async function createStaffAccountDirect(payload) {
  if (isDemoMode) {
    await demoDelay();
    const demoUser = {
      username: payload.username,
      first_name: payload.first_name,
      middle_name: payload.middle_name,
      last_name: payload.last_name,
      employee_id: payload.employee_id || makeDemoEmployeeId(),
      role: payload.role,
      status: payload.status || 'Active',
      created_at: new Date().toISOString(),
      email: payload.email,
      birthday: payload.birthday || ''
    };
    DEMO_REGISTERED_USERS.unshift(demoUser);
    return;
  }

  if (isApiMode) {
    const apiPayload = {
      ...payload,
      directCreate: true,
      skipOtp: true
    };

    const endpoints = [
      `${API_BASE}/api/staff`,
      `${API_BASE}/api/staff/create-account`,
      `${API_BASE}/api/staff/register`
    ];

    let lastError = null;
    for (const endpoint of endpoints) {
      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(apiPayload),
          credentials: 'include'
        });

        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
          throw new Error(data.message || `Request failed (${response.status})`);
        }

        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError || new Error('Unable to create account in API mode.');
  }

  const { supabase } = await loadSupabaseModule();
  try {
    const { data, error } = await supabase.rpc('create_staff_account_admin', {
      p_first_name: payload.first_name,
      p_middle_name: payload.middle_name,
      p_last_name: payload.last_name,
      p_birthday: payload.birthday,
      p_gender: payload.gender,
      p_username: payload.username,
      p_email: payload.email,
      p_role: payload.role,
      p_password: payload.password,
      p_consent_given: Boolean(payload.consent_given),
      p_status: payload.status || 'Active'
    });

    if (error) {
      throw new Error(error.message || 'Unable to create account.');
    }

    if (data && data.error) {
      throw new Error(data.error);
    }
  } catch (err) {
    // Provide more actionable guidance for network-level failures
    console.error('RPC create_staff_account_admin error:', err);
    const msg = String(err?.message || '').toLowerCase();
    if (msg.includes('failed to fetch') || msg.includes('networkerror') || msg.includes('network request failed') || err?.name === 'TypeError') {
      throw new Error('Network error communicating with Supabase (Failed to fetch).\n- Ensure you are serving the frontend over HTTP (not file://).\n- Confirm `SUPABASE_URL` and `SUPABASE_ANON_KEY` in frontend/web/js/runtime-config.js are correct.\n- Add your app origin to the Supabase project allowed origins (CORS).\n- Ensure the `create_staff_account_admin` function/migration is applied to the database.\nCheck the browser DevTools Network tab for the failing request for more details.');
    }
    throw err;
  }
}

if (registerForm) {
  registerForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Get values
    const first_name = document.getElementById('reg-first-name').value.trim();
    const middle_name = document.getElementById('reg-middle-name').value.trim();
    const last_name = document.getElementById('reg-last-name').value.trim();
    const birthday = document.getElementById('reg-birthday').value;
    const gender = document.getElementById('reg-gender').value;
    const username = document.getElementById('reg-username').value.trim();
    const email = document.getElementById('reg-email').value.trim();
    const password = document.getElementById('reg-password').value;
    const confirmPassword = document.getElementById('reg-confirm-password').value;
    const role = document.getElementById('reg-role').value;
    const allowedRegRoles = ['admin', 'doctor', 'nurse', 'pharmacist'];

    const err = document.getElementById('register-error');
    const success = document.getElementById('register-success');

    if (err) {
      err.textContent = '';
      err.style.display = 'none';
    }
    if (success) {
      success.textContent = '';
      success.style.display = 'none';
    }

    if (!first_name || !last_name || !username || !email || !role) {
      if (err) {
        err.textContent = 'Please fill in all required fields.';
        err.style.display = 'block';
      }
      return;
    }

    if (!allowedRegRoles.includes(String(role).trim().toLowerCase())) {
      if (err) {
        err.textContent = 'Role must be doctor, nurse, or pharmacist.';
        err.style.display = 'block';
      }
      return;
    }

    if (!password || password.length < 8) {
      if (err) {
        err.textContent = 'Password must be at least 8 characters.';
        err.style.display = 'block';
      }
      return;
    }

    if (password !== confirmPassword) {
      if (err) {
        err.textContent = 'Passwords do not match.';
        err.style.display = 'block';
      }
      return;
    }

    // Visual feedback
    if (registerSubmitBtn) {
      registerSubmitBtn.disabled = true;
      const label = registerSubmitBtn.querySelector('.btn-label');
      if (label) label.textContent = 'CREATING...';
    }

    try {
      const payload = {
        first_name,
        middle_name: middle_name || null,
        last_name,
        birthday: birthday || null,
        gender: gender || null,
        username,
        email: email.toLowerCase(),
        role,
        password,
        consent_given: true,
        status: 'Active'
      };

      await createStaffAccountDirect(payload);

      if (registerForm) registerForm.reset();
      if (registrationSuccessModal) registrationSuccessModal.classList.remove('hidden');

      storedAccounts.clear();
      await loadStaffData();

      if (success) {
        success.textContent = 'Account created successfully.';
        success.style.display = 'block';
      }
      showToast('Account created successfully.', 'success');

    } catch (error) {
      if (err) {
        err.textContent = error.message || 'Unable to create account.';
        err.style.display = 'block';
      }
    } finally {
      if (registerSubmitBtn) {
        registerSubmitBtn.disabled = false;
        const label = registerSubmitBtn.querySelector('.btn-label');
        if (label) label.textContent = 'CREATE ACCOUNT';
      }
    }
  });
}

const regRoleInput = document.getElementById('reg-role');

// Success modal buttons
if (regSuccessDashboardBtn) {
  regSuccessDashboardBtn.addEventListener('click', () => {
    if (registrationSuccessModal) registrationSuccessModal.classList.add('hidden');
    hideAllSections();
    if (dashboardSection) dashboardSection.classList.remove('hidden');
  });
}

if (regSuccessUsersBtn) {
  regSuccessUsersBtn.addEventListener('click', () => {
    if (registrationSuccessModal) registrationSuccessModal.classList.add('hidden');
    navigateToSection('users-section', { pane: 'registered-pane' });
  });
}

// Back to dashboard
if (backToDashboardBtn) {
  backToDashboardBtn.addEventListener('click', () => {
    hideAllSections();
    if (dashboardSection) dashboardSection.classList.remove('hidden');
  });
}

if (registrationBackBtn) {
  registrationBackBtn.addEventListener('click', () => {
    toggleUsersPane('accounts-pane');
    revealPane('registered-pane');
  });
}

// Name field validation (letters only)
['reg-first-name', 'reg-middle-name', 'reg-last-name'].forEach(fieldId => {
  const input = document.getElementById(fieldId);
  if (input) {
    input.addEventListener('input', function () {
      this.value = this.value.replace(/\d+/g, '');
    });
  }
});

// Email validation
const emailInput = document.getElementById('reg-email');
if (emailInput) {
  emailInput.addEventListener('blur', function () {
    const emailError = document.getElementById('err-reg-email');
    const email = this.value.trim();
    if (!email) {
      if (emailError) emailError.classList.add('hidden');
      return;
    }
    if (!validateEmail(email)) {
      if (emailError) {
        emailError.textContent = 'Please enter a valid email address';
        emailError.classList.remove('hidden');
      }
    } else {
      if (emailError) emailError.classList.add('hidden');
    }
  });
}

// Password toggles
setupPasswordVisibilityToggles();

// Init registration section handlers after DOM load
document.addEventListener('DOMContentLoaded', () => {
  setupPasswordVisibilityToggles();
});

// --- Profile & Schedule role-based helpers ---
async function initProfileAndSchedule() {
  const user = await ensureAuthenticatedSession();
  if (user) {
    applyRoleAccess(user);
    populateProfile(user);
    await loadSchedules(user);
    subscribeToStaffAvailability();
  }
}

function populateProfile(user) {
  const name = document.getElementById('profile-name');
  const email = document.getElementById('profile-email');
  const role = document.getElementById('profile-role');

  if (name) name.value = user?.first_name || user?.username || '';
  if (email) email.value = user?.email || '';
  if (role) role.value = toTitleCase(user?.role || '');
  applyRoleLogos(user?.role || 'nurse');
}

async function saveMyProfileToSupabase({ displayName }) {
  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase.rpc('update_my_staff_profile', {
    p_display_name: displayName
  });

  if (error) {
    throw new Error(error.message || 'Failed to update profile.');
  }

  if (data && data.error) {
    throw new Error(data.error);
  }

  return data;
}

const profileSaveBtn = document.getElementById('profile-save-btn');
if (profileSaveBtn) {
  profileSaveBtn.addEventListener('click', async () => {
    const name = document.getElementById('profile-name').value.trim();
    const email = document.getElementById('profile-email').value.trim();
    const role = String(document.getElementById('profile-role')?.value || '').trim().toLowerCase();

    const form = new FormData();
    form.append('displayName', name);
    form.append('email', email);
    if (!name) {
      showToast('Display name is required.', 'error');
      return;
    }

    try {
      profileSaveBtn.disabled = true;

      let saved = false;
      if (isApiMode) {
        try {
          const resp = await fetch(`${API_BASE}/api/staff/profile`, {
            method: 'POST',
            credentials: 'include',
            body: form
          });

          if (resp.ok) {
            saved = true;
          }
        } catch (_) {
          // Fall back to Supabase RPC when API profile route is unavailable.
        }
      }

      if (!saved && !isDemoMode) {
        await saveMyProfileToSupabase({
          displayName: name
        });
      }

      cachedSessionUser = {
        ...(cachedSessionUser || {}),
        first_name: name || cachedSessionUser?.first_name,
        email: email || cachedSessionUser?.email
      };

      const user = await ensureAuthenticatedSession(true);
      if (user) {
        populateProfile(user);
        applyRoleAccess(user);
      }

      showToast('Profile updated', 'success');
      if (isAdminUser(cachedSessionUser)) {
        await loadStaffData();
      }
    } catch (err) {
      console.error(err);
      showToast(err?.message || 'Unable to save profile.', 'error');
    } finally {
      profileSaveBtn.disabled = false;
    }
  });
}

const profileForm = document.getElementById('profile-form');
if (profileForm) {
  profileForm.addEventListener('submit', (event) => {
    event.preventDefault();
    if (profileSaveBtn) profileSaveBtn.click();
  });
}

// Profile cancel - reset to session values
const profileCancelBtn = document.getElementById('profile-cancel-btn');
if (profileCancelBtn) {
  profileCancelBtn.addEventListener('click', async () => {
    const user = await ensureAuthenticatedSession(true);
    if (user) populateProfile(user);
    else {
      const form = document.getElementById('profile-form');
      if (form) form.reset();
    }
  });
}

// --- Schedule handling (doctor schedules + staff availability). Admins can create/update/delete; others view only ---
let cachedScheduleStaff = [];
let cachedScheduleDoctors = [];
let cachedScheduleEntries = [];
let staffAvailabilityChannel = null;

function formatScheduleTime(value) {
  const normalized = normalizeTimeHHMM(value);
  if (!normalized) return '—';

  const [hours, minutes] = normalized.split(':').map(Number);
  const date = new Date();
  date.setHours(hours, minutes, 0, 0);
  return date.toLocaleTimeString([], {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  });
}

function normalizeTimeHHMM(value) {
  const text = String(value || '').trim();
  const match = text.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return '';
  const hours = String(Math.min(23, Math.max(0, Number(match[1])))).padStart(2, '0');
  const minutes = String(Math.min(59, Math.max(0, Number(match[2])))).padStart(2, '0');
  return `${hours}:${minutes}`;
}

function parseLegacyTimeRange(value) {
  const text = String(value || '').trim();
  if (!text) {
    return { start: '', end: '' };
  }

  const parts = text.split('-').map((item) => normalizeTimeHHMM(item));
  if (parts.length >= 2) {
    return { start: parts[0], end: parts[1] };
  }

  return { start: normalizeTimeHHMM(text), end: '' };
}

function toMinutes(value) {
  const normalized = normalizeTimeHHMM(value);
  if (!normalized) return NaN;
  const [hours, minutes] = normalized.split(':').map(Number);
  return (hours * 60) + minutes;
}

function normalizeScheduleRecord(item) {
  const date = item?.schedule_date || item?.date || '';
  const doctorId = item?.doctor_staff_id ?? null;

  let start = normalizeTimeHHMM(item?.start_time || '');
  let end = normalizeTimeHHMM(item?.end_time || '');

  if (!start && item?.time) {
    const parsed = parseLegacyTimeRange(item.time);
    start = parsed.start;
    if (!end) end = parsed.end;
  }

  return {
    ...item,
    doctor_staff_id: doctorId,
    schedule_date: date,
    start_time: start,
    end_time: end
  };
}

function getTodayScheduleDateKey() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function isPastScheduleDateValue(value) {
  const dateText = String(value || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText)) return false;
  return dateText < getTodayScheduleDateKey();
}

function isScheduleExpired(entry) {
  const scheduleDate = String(entry?.schedule_date || entry?.date || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(scheduleDate)) return false;

  if (isPastScheduleDateValue(scheduleDate)) return true;

  const today = getTodayScheduleDateKey();
  if (scheduleDate !== today) return false;

  const end = normalizeTimeHHMM(entry?.end_time || '');
  if (!end) return false;

  const [endHour, endMinute] = end.split(':').map((item) => Number(item));
  if (!Number.isFinite(endHour) || !Number.isFinite(endMinute)) return false;

  const now = new Date();
  const nowMinutes = (now.getHours() * 60) + now.getMinutes();
  const endMinutes = (endHour * 60) + endMinute;
  return endMinutes < nowMinutes;
}

async function purgePastSchedules(records, user, source = 'doctor_schedules') {
  const normalized = Array.isArray(records) ? records : [];
  const expired = normalized.filter((entry) => isScheduleExpired(entry));

  // Always keep expired items out of the live UI list.
  const activeRecords = normalized.filter((entry) => !isScheduleExpired(entry));

  if (!expired.length) return activeRecords;

  const expiredIds = expired
    .map((entry) => entry?.id)
    .filter((id) => id !== null && id !== undefined && String(id).trim() !== '');

  if (!expiredIds.length || !isAdminUser(user)) {
    return activeRecords;
  }

  try {
    if (isApiMode || source === 'api') {
      await Promise.all(expiredIds.map(async (id) => {
        const response = await fetch(`${API_BASE}/api/schedules/${id}`, {
          method: 'DELETE',
          credentials: 'include'
        });
        if (!response.ok) {
          throw new Error(`Failed to auto-delete schedule ${id}`);
        }
      }));
    } else {
      const { supabase } = await loadSupabaseModule();
      const tableName = source === 'schedules' ? 'schedules' : 'doctor_schedules';
      const { error } = await supabase.from(tableName).delete().in('id', expiredIds);
      if (error) throw error;
    }
  } catch (error) {
    console.error('Auto-delete past schedules failed:', error);
  }

  return activeRecords;
}

function hasScheduleConflict({ doctorStaffId, scheduleDate, startTime, endTime, excludeId }) {
  const targetDoctor = String(doctorStaffId || '').trim();
  const targetDate = String(scheduleDate || '').trim();
  const startMinutes = toMinutes(startTime);
  const endMinutes = toMinutes(endTime);

  if (!targetDoctor || !targetDate || !Number.isFinite(startMinutes) || !Number.isFinite(endMinutes)) {
    return false;
  }

  return cachedScheduleEntries.some((entry) => {
    if (excludeId && String(entry?.id || '') === String(excludeId)) return false;
    if (String(entry?.doctor_staff_id || '') !== targetDoctor) return false;
    if (String(entry?.schedule_date || '') !== targetDate) return false;

    const existingStart = toMinutes(entry?.start_time || '');
    const existingEnd = toMinutes(entry?.end_time || '');
    if (!Number.isFinite(existingStart) || !Number.isFinite(existingEnd)) return false;

    return startMinutes < existingEnd && endMinutes > existingStart;
  });
}

function renderScheduleDoctors(staffList, user) {
  const doctorTbody = document.getElementById('schedule-doctors-tbody');
  const nurseTbody = document.getElementById('schedule-nurses-tbody');
  if (!doctorTbody || !nurseTbody) return;

  const doctors = staffList.filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'doctor' || r === 'specialist';
  });
  const nurses = staffList.filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'nurse' || r === 'staff';
  });

  const buildRows = (list, emptyMsg) => (fragment) => {
    if (!list.length) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td class="table-cell" colspan="4">${emptyMsg}</td>`;
      fragment.appendChild(tr);
      return;
    }
    list.forEach((staff) => {
      const tr = document.createElement('tr');
      const statusText = getAvailabilityStatusText(staff);
      const statusClass = getAvailabilityBadgeClass(staff);
      const availabilityStatus = normalizeAvailabilityStatus(
        staff?.availability_status || staff?.availabilityStatus
      );
      tr.innerHTML = `
        <td class="table-cell">${getDoctorDisplayName(staff)}</td>
        <td class="table-cell">${staff.email || '—'}</td>
        <td class="table-cell"><span class="${statusClass}">${statusText}</span></td>
        <td class="table-cell"></td>
      `;

      const actionsCell = tr.querySelector('td:last-child');
      if (!actionsCell) return;

      const canEditAvailability = isAdminUser(user);
      const toggleGroup = document.createElement('div');
      toggleGroup.className = 'availability-toggle-group';
      toggleGroup.dataset.staffId = String(staff.id || '');

      const options = [
        { value: 'available', label: 'Available', className: 'availability-available' },
        { value: 'on_break', label: 'On Break', className: 'availability-break' },
        { value: 'unavailable', label: 'Unavailable', className: 'availability-unavailable' }
      ];

      options.forEach((option) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `chip-btn chip-btn-outline availability-toggle ${option.className}`;
        btn.textContent = option.label;
        btn.dataset.status = option.value;
        btn.disabled = !canEditAvailability;
        if (availabilityStatus === option.value) {
          btn.classList.add('is-active');
        }
        btn.addEventListener('click', () => handleAvailabilityToggle(staff, option.value, toggleGroup));
        toggleGroup.appendChild(btn);
      });

      actionsCell.appendChild(toggleGroup);
      fragment.appendChild(tr);
    });
  };

  swapContainer(doctorTbody, buildRows(doctors, 'No doctor accounts found.'));
  swapContainer(nurseTbody, buildRows(nurses, 'No nurse accounts found.'));
}

function updateAvailabilityInCaches(staffId, status, newRow = null) {
  const normalized = normalizeAvailabilityStatus(status);
  const updateList = (list) => {
    const idx = list.findIndex((item) => String(item?.id || '') === String(staffId));
    if (idx < 0) return;
    const record = list[idx];
    record.availability_status = normalized;
    if (newRow) Object.assign(record, newRow);
  };

  updateList(cachedScheduleStaff);
  updateList(cachedScheduleDoctors);
  updateList(latestStaffList);
}

function setAvailabilityButtonsLoading(toggleGroup, isLoading) {
  if (!toggleGroup) return;
  toggleGroup.classList.toggle('is-loading', Boolean(isLoading));
  toggleGroup.querySelectorAll('button').forEach((btn) => {
    if (isLoading) {
      if (!btn.dataset.wasDisabled) {
        btn.dataset.wasDisabled = btn.disabled ? 'true' : 'false';
      }
      btn.disabled = true;
      return;
    }

    const wasDisabled = btn.dataset.wasDisabled === 'true';
    btn.disabled = wasDisabled;
    delete btn.dataset.wasDisabled;
  });
}

function applyAvailabilityToggleState(toggleGroup, status) {
  if (!toggleGroup) return;
  const normalized = normalizeAvailabilityStatus(status);
  toggleGroup.querySelectorAll('button').forEach((btn) => {
    const btnStatus = normalizeAvailabilityStatus(btn.dataset.status);
    btn.classList.toggle('is-active', btnStatus === normalized);
  });
}

async function updateStaffAvailabilityById(staffId, status) {
  if (!staffId) throw new Error('Missing staff id.');
  const normalized = normalizeAvailabilityStatus(status);

  if (isDemoMode) {
    updateAvailabilityInCaches(staffId, normalized);
    return true;
  }

  if (isApiMode) {
    try {
      const resp = await fetch(`${API_BASE}/api/staff/${staffId}/availability`, {
        method: 'PATCH',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: normalized })
      });
      if (resp.ok) {
        return true;
      }
    } catch (_) {
      // Fall back to Supabase RPC.
    }
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase.rpc('set_staff_availability', {
    p_target_staff_id: Number(staffId),
    p_status: normalized
  });

  if (error) {
    throw new Error(error.message || 'Unable to update availability status.');
  }

  return true;
}

async function handleAvailabilityToggle(staff, nextStatus, toggleGroup) {
  if (!staff || !toggleGroup) return;
  if (!isAdminUser(cachedSessionUser)) return;

  const staffId = staff.id;
  const prevStatus = normalizeAvailabilityStatus(staff?.availability_status);
  const normalizedNext = normalizeAvailabilityStatus(nextStatus);
  if (prevStatus === normalizedNext) return;

  applyAvailabilityToggleState(toggleGroup, normalizedNext);
  updateAvailabilityInCaches(staffId, normalizedNext);
  setAvailabilityButtonsLoading(toggleGroup, true);

  try {
    await updateStaffAvailabilityById(staffId, normalizedNext);
    const statusNode = toggleGroup.closest('tr')?.querySelector('td:nth-child(3) span');
    if (statusNode) {
      statusNode.className = getAvailabilityBadgeClass({ availability_status: normalizedNext });
      statusNode.textContent = AVAILABILITY_LABELS[normalizedNext] || 'Available';
    }
  } catch (error) {
    updateAvailabilityInCaches(staffId, prevStatus);
    applyAvailabilityToggleState(toggleGroup, prevStatus);
    showToast(error?.message || 'Unable to update availability.', 'error');
  } finally {
    setAvailabilityButtonsLoading(toggleGroup, false);
  }
}

async function subscribeToStaffAvailability() {
  if (staffAvailabilityChannel) return;
  if (isDemoMode) return;

  try {
    const { supabase } = await loadSupabaseModule();
    staffAvailabilityChannel = supabase
      .channel('staff-availability')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'staff' }, (payload) => {
        const updated = payload?.new;
        if (!updated || !updated.id) return;
        if (!isScheduleRole(updated.role)) return;
        updateAvailabilityInCaches(updated.id, updated.availability_status, updated);
        if (!document.getElementById('schedule-section')?.classList.contains('hidden')) {
          renderScheduleDoctors(cachedScheduleStaff, cachedSessionUser);
        }
      })
      .subscribe();
  } catch (error) {
    console.warn('Realtime availability subscription failed:', error);
  }
}

function populateScheduleDoctorSelect(selectedDoctorId = null) {
  const select = document.getElementById('sched-doctor-id');
  if (!select) return;

  const selected = selectedDoctorId ? String(selectedDoctorId) : '';
  select.innerHTML = '<option value="">Select staff member</option>';

  cachedScheduleDoctors.forEach((doctor) => {
    const option = document.createElement('option');
    option.value = String(doctor.id);
    option.textContent = `${getDoctorDisplayName(doctor)}${doctor.email ? ` (${doctor.email})` : ''}`;
    if (selected && option.value === selected) {
      option.selected = true;
    }
    select.appendChild(option);
  });
}

async function loadSchedules(user) {
  let schedules = [];
  let staffRoster = [];
  let doctors = [];
  let scheduleSource = 'doctor_schedules';

  try {
    if (isApiMode) {
      scheduleSource = 'api';
      const [schedulesResp, staffResp] = await Promise.all([
        fetch(`${API_BASE}/api/schedules`, { credentials: 'include' }),
        fetch(`${API_BASE}/api/staff`, { credentials: 'include' })
      ]);

      if (schedulesResp.ok) {
        schedules = await schedulesResp.json();
      }

      if (staffResp.ok) {
        const staff = await staffResp.json();
        staffRoster = Array.isArray(staff) ? staff : [];
        doctors = staffRoster.filter((item) => isScheduleRole(item?.role));
      }

      if (!schedulesResp.ok || !staffResp.ok || doctors.length === 0 || schedules.length === 0) {
        const [staffService, supabaseModule] = await Promise.all([loadStaffServiceModule(), loadSupabaseModule()]);
        const { supabase } = supabaseModule;

        if (doctors.length === 0) {
          const fallbackStaff = await staffService.listStaff();
          staffRoster = Array.isArray(fallbackStaff) ? fallbackStaff : [];
          doctors = staffRoster.filter((item) => isScheduleRole(item?.role));
        }

        if (schedules.length === 0) {
          let scheduleData = [];
          let scheduleError = null;

          ({ data: scheduleData, error: scheduleError } = await supabase
            .from('doctor_schedules')
            .select('*')
            .order('schedule_date', { ascending: true })
            .order('start_time', { ascending: true }));

          if (scheduleError) {
            scheduleSource = 'schedules';
            const legacyResult = await supabase
              .from('schedules')
              .select('*')
              .order('date', { ascending: true });

            if (!legacyResult.error) {
              schedules = (legacyResult.data || []).map((item) => ({
                id: item.id,
                doctor_name: item.doctor || 'Doctor',
                schedule_date: item.date,
                start_time: item.time,
                end_time: null,
                notes: null,
                doctor_staff_id: null
              }));
            }
          } else {
            scheduleSource = 'doctor_schedules';
            schedules = scheduleData || [];
          }
        }
      }
    } else {
      const [staffService, supabaseModule] = await Promise.all([loadStaffServiceModule(), loadSupabaseModule()]);
      const { supabase } = supabaseModule;

      const staffRpc = await supabase.rpc('list_staff_accounts');
      const staff = !staffRpc.error
        ? (Array.isArray(staffRpc.data) ? staffRpc.data : [])
        : await staffService.listStaff();
      staffRoster = Array.isArray(staff) ? staff : [];
      doctors = staffRoster.filter((item) => isScheduleRole(item?.role));

      const scheduleRpc = await supabase.rpc('list_doctor_schedules');
      if (!scheduleRpc.error) {
        schedules = Array.isArray(scheduleRpc.data) ? scheduleRpc.data : [];
      }

      let scheduleData = schedules;
      let scheduleError = scheduleRpc.error || null;

      if (!scheduleData.length) {
        ({ data: scheduleData, error: scheduleError } = await supabase
          .from('doctor_schedules')
          .select('*')
          .order('schedule_date', { ascending: true })
          .order('start_time', { ascending: true }));
      }

      if (scheduleError) {
        scheduleSource = 'schedules';
        const legacyResult = await supabase
          .from('schedules')
          .select('*')
          .order('date', { ascending: true });

        if (legacyResult.error) throw scheduleError;
        schedules = (legacyResult.data || []).map((item) => ({
          id: item.id,
          doctor_name: item.doctor || 'Doctor',
          schedule_date: item.date,
          start_time: item.time,
          end_time: null,
          notes: null,
          doctor_staff_id: null
        }));
      } else {
        schedules = scheduleData || [];
      }
    }
  } catch (err) {
    console.error('Error loading schedules:', err);
    schedules = [];
    doctors = [];
  }

  schedules = (Array.isArray(schedules) ? schedules : []).map(normalizeScheduleRecord);
  schedules = await purgePastSchedules(schedules, user, scheduleSource);
  cachedScheduleEntries = [...schedules];

  cachedScheduleStaff = Array.isArray(staffRoster) ? staffRoster.filter((item) => isScheduleRole(item?.role)) : [];
  cachedScheduleDoctors = Array.isArray(doctors) ? [...doctors] : [];
  populateScheduleDoctorSelect();
  renderScheduleDoctors(cachedScheduleStaff, user);
  renderSchedules(schedules, user, cachedScheduleDoctors);
}

async function upsertScheduleRecord({ id, doctorId, doctorName, date, startTime, endTime, notes }) {
  const apiPayload = {
    doctor: doctorName,
    doctor_staff_id: Number(doctorId),
    date,
    start_time: startTime,
    end_time: endTime,
    time: `${startTime}-${endTime}`,
    notes: notes || null
  };

  if (isApiMode) {
    try {
      const url = id ? `${API_BASE}/api/schedules/${id}` : `${API_BASE}/api/schedules`;
      const method = id ? 'PUT' : 'POST';
      const resp = await fetch(url, {
        method,
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(apiPayload)
      });

      if (resp.ok) {
        return true;
      }
    } catch (_) {
      // Fall back to Supabase path below.
    }
  }

  const { supabase } = await loadSupabaseModule();

  const rpcPayload = {
    p_id: id ? Number(id) : null,
    p_doctor_staff_id: Number(doctorId),
    p_schedule_date: date,
    p_start_time: startTime,
    p_end_time: endTime,
    p_notes: notes || null
  };

  const rpcResult = await supabase.rpc('upsert_doctor_schedule_admin', rpcPayload);
  if (!rpcResult.error) {
    return true;
  }
  const payload = {
    doctor_staff_id: Number(doctorId),
    doctor_name: doctorName,
    schedule_date: date,
    start_time: startTime,
    end_time: endTime,
    notes: notes || null,
    created_by_staff_id: Number(cachedSessionUser?.id) || null
  };

  let result;
  if (id) {
    result = await supabase.from('doctor_schedules').update(payload).eq('id', id);
    if (result.error) {
      result = await supabase
        .from('schedules')
        .update({ doctor: doctorName, date, time: `${startTime}-${endTime}` })
        .eq('id', id);
    }
  } else {
    result = await supabase.from('doctor_schedules').insert(payload);
    if (result.error) {
      result = await supabase
        .from('schedules')
        .insert({ doctor: doctorName, date, time: `${startTime}-${endTime}` });
    }
  }

  if (result.error) throw result.error;
  return true;
}

async function deleteScheduleRecordById(id) {
  if (isApiMode) {
    try {
      const resp = await fetch(`${API_BASE}/api/schedules/${id}`, { method: 'DELETE', credentials: 'include' });
      if (resp.ok) {
        return true;
      }
    } catch (_) {
      // Fall back to Supabase path below.
    }
  }

  const { supabase } = await loadSupabaseModule();

  const rpcResult = await supabase.rpc('delete_doctor_schedule_admin', {
    p_id: Number(id)
  });
  if (!rpcResult.error) {
    return true;
  }

  let result = await supabase.from('doctor_schedules').delete().eq('id', id);
  if (result.error) {
    result = await supabase.from('schedules').delete().eq('id', id);
  }
  if (result.error) throw result.error;
  return true;
}

function renderSchedules(schedules, user, doctors = []) {
  const tbody = document.getElementById('schedule-tbody');
  const calendar = document.getElementById('calendar-container');
  if (!tbody || !calendar) return;

  const doctorMap = new Map((doctors || []).map((doctor) => [String(doctor.id), doctor]));

  tbody.innerHTML = '';
  calendar.innerHTML = '';

  const dates = [...new Set((schedules || []).map((item) => item.schedule_date || item.date).filter(Boolean))];
  const dateList = document.createElement('div');
  dateList.style.display = 'flex';
  dateList.style.gap = '8px';
  dateList.style.flexWrap = 'wrap';

  const showAllBtn = document.createElement('button');
  showAllBtn.type = 'button';
  showAllBtn.className = 'chip-btn';
  showAllBtn.textContent = 'All Dates';
  showAllBtn.addEventListener('click', () => {
    Array.from(tbody.querySelectorAll('tr')).forEach((tr) => {
      tr.style.display = '';
    });
  });
  dateList.appendChild(showAllBtn);

  dates.forEach((dateValue) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip-btn';
    btn.textContent = dateValue;
    btn.addEventListener('click', () => {
      Array.from(tbody.querySelectorAll('tr')).forEach((tr) => {
        tr.style.display = tr.dataset.date === dateValue ? '' : 'none';
      });
    });
    dateList.appendChild(btn);
  });
  calendar.appendChild(dateList);

  if (!schedules.length) {
    tbody.innerHTML = '<tr><td class="table-cell" colspan="5">No schedules found.</td></tr>';
    return;
  }

  schedules.forEach((schedule) => {
    const doctorId = schedule.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    const doctor = doctorId ? doctorMap.get(doctorId) : null;
    const doctorName = schedule.doctor_name || getDoctorDisplayName(doctor) || 'Doctor';
    const scheduleDate = schedule.schedule_date || schedule.date || '—';
    const startTime = formatScheduleTime(schedule.start_time || schedule.time);
    const endTime = formatScheduleTime(schedule.end_time);

    const tr = document.createElement('tr');
    tr.dataset.date = scheduleDate;
    tr.innerHTML = `
      <td class="table-cell">${doctorName}</td>
      <td class="table-cell">${scheduleDate}</td>
      <td class="table-cell">${startTime}</td>
      <td class="table-cell">${endTime}</td>
      <td class="table-cell"></td>
    `;

    const actionsTd = tr.querySelector('td:last-child');
    if (isAdminUser(user)) {
      const editBtn = document.createElement('button');
      editBtn.className = 'btn small outline admin-only';
      editBtn.textContent = 'Edit';
      editBtn.addEventListener('click', () => openScheduleModal('edit', schedule));

      const delBtn = document.createElement('button');
      delBtn.className = 'btn small btn-delete admin-only';
      delBtn.textContent = 'Delete';
      delBtn.addEventListener('click', async () => {
        const confirmation = await openDialogModal({
          title: 'Delete Schedule',
          message: 'Delete this schedule?',
          confirmText: 'Delete',
          cancelText: 'Cancel'
        });
        if (!confirmation.confirmed) return;
        try {
          await deleteScheduleRecordById(schedule.id);
          showToast('Schedule deleted', 'success');
          initProfileAndSchedule();
        } catch (err) {
          console.error(err);
          showToast('Unable to delete schedule', 'error');
        }
      });

      actionsTd.appendChild(editBtn);
      actionsTd.appendChild(delBtn);
    } else {
      actionsTd.textContent = '-';
    }

    tbody.appendChild(tr);
    attachDetailRow(tr, () => ({
      tag: 'Schedule',
      title: doctorName,
      subtitle: scheduleDate,
      items: [
        { label: 'Doctor', value: doctorName },
        { label: 'Date', value: scheduleDate },
        { label: 'Start Time', value: startTime },
        { label: 'End Time', value: endTime },
        { label: 'Notes', value: schedule.notes || '—' },
        { label: 'Schedule ID', value: schedule.id || '—' }
      ]
    }));
  });
}

// Schedule editor modal logic
function openScheduleModal(mode = 'create', schedule = null) {
  const modal = document.getElementById('schedule-editor-modal');
  const form = document.getElementById('schedule-form');
  const idInput = document.getElementById('sched-id');
  const doctorInput = document.getElementById('sched-doctor-id');
  const dateInput = document.getElementById('sched-date');
  const startInput = document.getElementById('sched-start-time');
  const endInput = document.getElementById('sched-end-time');
  const notesInput = document.getElementById('sched-notes');
  const deleteBtn = document.getElementById('sched-delete-btn');
  const errorNode = document.getElementById('sched-form-error');

  if (!modal || !form || !idInput || !doctorInput || !dateInput || !startInput || !endInput) return;

  errorNode.textContent = '';
  populateScheduleDoctorSelect(schedule?.doctor_staff_id || null);

  if (mode === 'edit' && schedule) {
    idInput.value = schedule.id || '';
    doctorInput.value = schedule.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    dateInput.value = schedule.schedule_date || schedule.date || '';
    startInput.value = normalizeTimeHHMM(schedule.start_time || schedule.time || '');
    endInput.value = normalizeTimeHHMM(schedule.end_time || '');
    if (notesInput) notesInput.value = schedule.notes || '';
    deleteBtn.classList.remove('hidden');
  } else {
    idInput.value = '';
    doctorInput.value = schedule?.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    dateInput.value = '';
    startInput.value = '';
    endInput.value = '';
    if (notesInput) notesInput.value = '';
    deleteBtn.classList.add('hidden');
  }

  modal.classList.remove('hidden');
}

function closeScheduleModal() {
  const modal = document.getElementById('schedule-editor-modal');
  if (modal) modal.classList.add('hidden');
}

function showScheduleSuccessModal() {
  const modal = document.getElementById('schedule-success-modal');
  if (modal) modal.classList.remove('hidden');
}

function hideScheduleSuccessModal() {
  const modal = document.getElementById('schedule-success-modal');
  if (modal) modal.classList.add('hidden');
}

// submit handler
const schedForm = document.getElementById('schedule-form');
if (schedForm) {
  schedForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = document.getElementById('sched-id').value;
    const doctorId = String(document.getElementById('sched-doctor-id').value || '').trim();
    const date = document.getElementById('sched-date').value;
    const startTime = String(document.getElementById('sched-start-time').value || '').trim();
    const endTime = String(document.getElementById('sched-end-time').value || '').trim();
    const notes = String(document.getElementById('sched-notes')?.value || '').trim();
    const errorNode = document.getElementById('sched-form-error');
    errorNode.textContent = '';

    if (!doctorId || !date || !startTime || !endTime) {
      errorNode.textContent = 'Doctor, date, start time, and end time are required.';
      return;
    }

    if (startTime >= endTime) {
      errorNode.textContent = 'End time must be after start time.';
      return;
    }

    if (hasScheduleConflict({
      doctorStaffId: doctorId,
      scheduleDate: date,
      startTime,
      endTime,
      excludeId: id || null
    })) {
      errorNode.textContent = 'This doctor already has an overlapping schedule on that date.';
      return;
    }

    try {
      const selectedDoctor = cachedScheduleDoctors.find((item) => String(item.id) === doctorId);
      const doctorName = selectedDoctor ? getDoctorDisplayName(selectedDoctor) : 'Doctor';

      await upsertScheduleRecord({
        id,
        doctorId,
        doctorName,
        date,
        startTime,
        endTime,
        notes
      });

      closeScheduleModal();
      initProfileAndSchedule();
      navigateToSection('schedule-section');

      if (id) {
        showToast('Schedule updated', 'success');
      } else {
        showToast('Schedule created successfully', 'success');
      }
    } catch (err) {
      console.error(err);
      errorNode.textContent = err.message || 'Network error';
    }
  });
}

// delete from modal
const schedDeleteBtn = document.getElementById('sched-delete-btn');
if (schedDeleteBtn) {
  schedDeleteBtn.addEventListener('click', async () => {
    const id = document.getElementById('sched-id').value;
    if (!id) return;
    const confirmation = await openDialogModal({
      title: 'Delete Schedule',
      message: 'Delete this schedule?',
      confirmText: 'Delete',
      cancelText: 'Cancel'
    });
    if (!confirmation.confirmed) return;
    try {
      await deleteScheduleRecordById(id);
      showToast('Schedule deleted', 'success');
      closeScheduleModal();
      initProfileAndSchedule();
      navigateToSection('schedule-section');
    } catch (err) {
      console.error(err);
      showToast('Unable to delete schedule', 'error');
    }
  });
}

// modal cancel
const schedCancelBtn = document.getElementById('sched-cancel-btn');
if (schedCancelBtn) schedCancelBtn.addEventListener('click', () => closeScheduleModal());

// wire create button to open modal
const createScheduleBtn = document.getElementById('create-schedule-btn');
if (createScheduleBtn) {
  createScheduleBtn.addEventListener('click', () => openScheduleModal('create'));
}

const scheduleSuccessOkBtn = document.getElementById('schedule-success-ok-btn');
if (scheduleSuccessOkBtn) {
  scheduleSuccessOkBtn.addEventListener('click', () => hideScheduleSuccessModal());
}

async function initializeDashboard() {
  try {
    // Master init - call all content population functions
    await initProfileAndSchedule().catch(e => console.error('Profile init failed:', e));
    await initClinicalData().catch(e => console.error('Clinical init failed:', e));
    const tabStats = document.getElementById('tab-stats');
    const statsPane = document.getElementById('stats-pane');

    if (tabAnnouncements && tabFeedback && tabStats) {
      tabAnnouncements.onclick = () => {
        tabAnnouncements.classList.add('active');
        tabFeedback.classList.remove('active');
        tabStats.classList.remove('active');
        announcementsPane.classList.remove('hidden');
        feedbackPane.classList.add('hidden');
        statsPane.classList.add('hidden');
      };
      tabFeedback.onclick = () => {
        tabAnnouncements.classList.remove('active');
        tabFeedback.classList.add('active');
        tabStats.classList.remove('active');
        announcementsPane.classList.add('hidden');
        feedbackPane.classList.remove('hidden');
        statsPane.classList.add('hidden');
        refreshFeedbackData();
      };
      tabStats.onclick = () => {
        tabAnnouncements.classList.remove('active');
        tabFeedback.classList.remove('active');
        tabStats.classList.add('active');
        announcementsPane.classList.add('hidden');
        feedbackPane.classList.add('hidden');
        statsPane.classList.remove('hidden');
        renderClinicalStats();
      };
    }
    initReportsSection();
    await Promise.all([
      refreshAnnouncementsData().catch((err) => console.warn('Announcements failed:', err)),
      refreshFeedbackData().catch((err) => console.warn('Feedback failed:', err))
    ]);
    await initDashboardData();
  } catch (error) {
    console.error('Dashboard initialization failed:', error);
    dismissPagePreloader(); // Guarantee interaction even on partial failure
  }
}

// Initialize on DOM ready
const startDashboard = async () => {
  await initializeDashboard();
  navigateToSection(getSectionFromHash() || DEFAULT_SECTION_ID);
};

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', startDashboard);
} else {
  startDashboard();
}



// Nav-related elements (keep globals for other code)
const dashboardSection = document.getElementById('dashboard-section');
const usersSection = document.getElementById('users-section');
const reportsSection = document.getElementById('reports-section');
const newRegistrationSection = document.getElementById('new-registration');

const statTotalStaff = document.getElementById('stat-total-staff');
const statDoctors = document.getElementById('stat-doctors');
const statActiveStaff = document.getElementById('stat-active-staff');
const statAnnouncements = document.getElementById('stat-announcements');
const statReports = document.getElementById('stat-reports');
const statPatients = document.getElementById('stat-citizens');
const dashboardActivePreview = document.getElementById('dashboard-active-preview');
const dashboardLastSync = document.getElementById('dashboard-last-sync');

const dashRefreshBtn = document.getElementById('dash-refresh-btn');
const staffRegisterBtn = document.getElementById('staff-register-btn');
const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');
const patientsTbody = document.getElementById('citizens-tbody');
const citizensTableWrap = document.getElementById('citizens-table-wrap');
const staffFinderInput = document.getElementById('staff-finder-input');
const roleFilterInput = document.getElementById('role-filter');
const citizensFinderInput = document.getElementById('citizens-finder-input');
const userPaneIds = ['accounts-pane', 'registration-pane'];
const chartAnimationState = { frameId: null };

// ── Citizen Health Records Modal ──────────────────────────────────────────────

const citizenHealthModal = document.getElementById('citizen-health-modal');

function closeCitizenHealthModal() {
  if (citizenHealthModal) citizenHealthModal.classList.add('hidden');
}

document.getElementById('chr-close-btn')?.addEventListener('click', closeCitizenHealthModal);
document.getElementById('chr-export-btn')?.addEventListener('click', () => {
  const dateSpan = document.getElementById('chr-print-date');
  if (dateSpan) dateSpan.textContent = new Date().toLocaleString();
  window.print();
});
citizenHealthModal?.addEventListener('click', (e) => {
  if (e.target === citizenHealthModal) closeCitizenHealthModal();
});

// Tab switching
citizenHealthModal?.addEventListener('click', (e) => {
  const tab = e.target.closest('.chr-tab');
  if (!tab) return;
  const targetId = tab.dataset.chrTab;
  citizenHealthModal.querySelectorAll('.chr-tab').forEach(t => {
    const active = t.dataset.chrTab === targetId;
    t.style.color = active ? '#0369a1' : '#64748b';
    t.style.borderBottomColor = active ? '#0369a1' : 'transparent';
    t.classList.toggle('active', active);
  });
  citizenHealthModal.querySelectorAll('.chr-tab-content').forEach(c => {
    c.style.display = c.id === targetId ? '' : 'none';
  });
});

function chrEmptyState(msg) {
  return `<p style="color:#94a3b8;font-size:13px;padding:12px 0;">${msg}</p>`;
}

function chrLoadingState() {
  return `<p style="color:#94a3b8;font-size:13px;padding:12px 0;">Loading…</p>`;
}

async function openCitizenHealthModal(citizen) {
  if (!citizenHealthModal) return;

  // Reset tabs to first
  citizenHealthModal.querySelectorAll('.chr-tab').forEach((t, i) => {
    const active = i === 0;
    t.style.color = active ? '#0369a1' : '#64748b';
    t.style.borderBottomColor = active ? '#0369a1' : 'transparent';
    t.classList.toggle('active', active);
  });
  citizenHealthModal.querySelectorAll('.chr-tab-content').forEach((c, i) => {
    c.style.display = i === 0 ? '' : 'none';
  });

  // Header
  const fullName = [citizen.firstname, citizen.surname].filter(Boolean).join(' ') || citizen.username || citizen.name || '—';
  document.getElementById('chr-name').textContent = fullName;
  document.getElementById('chr-meta').textContent = citizen.email || '';

  // Profile strip
  const profileEl = document.getElementById('chr-profile');
  const profileFields = [
    { label: 'Sex', value: citizen.sex || '—' },
    { label: 'Age', value: citizen.age || '—' },
    { label: 'Date of Birth', value: citizen.date_of_birth ? new Date(citizen.date_of_birth).toLocaleDateString() : '—' },
    { label: 'Contact', value: citizen.contact_number || '—' },
    { label: 'Address', value: citizen.complete_address || '—' },
    { label: 'Emergency Name', value: citizen.emergency_contact_complete_name || '—' },
    { label: 'Emergency Phone', value: citizen.emergency_contact_contact_number || '—' },
    { label: 'Relation', value: citizen.relation || '—' },
  ];
  profileEl.innerHTML = profileFields.map(f => `
    <div>
      <div style="font-size:11px;color:#94a3b8;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">${f.label}</div>
      <div style="font-size:13px;color:#1e293b;margin-top:2px;">${f.value}</div>
    </div>
  `).join('');

  // Set loading state on all tab bodies
  ['chr-consultations-body','chr-vitals-body','chr-prescriptions-body','chr-laborders-body']
    .forEach(id => { const el = document.getElementById(id); if (el) el.innerHTML = chrLoadingState(); });

  citizenHealthModal.classList.remove('hidden');

  // Fetch all health data in parallel
  try {
    const { supabase } = await loadSupabaseModule();
    const citizenId = Number(citizen.id);

    const [consultRes, vitalsRes, rxRes, labRes] = await Promise.all([
      supabase.from('consultations')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .or(`patient_citizen_id.eq.${citizenId},patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('consulted_at', { ascending: false })
        .limit(50),
      supabase.from('vital_signs')
        .select('*, nurse:staff!nurse_id(first_name,last_name)')
        .eq('citizen_id', citizenId)
        .order('created_at', { ascending: false })
        .limit(50),
      supabase.from('prescription_headers')
        .select('id,issued_at,patient_identifier,doctor:staff!doctor_staff_id(first_name,last_name),items:prescription_items(*)')
        .or(`patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('issued_at', { ascending: false })
        .limit(50),
      supabase.from('lab_orders')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .or(`patient_citizen_id.eq.${citizenId},patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('created_at', { ascending: false })
        .limit(50),
    ]);

    // Render Consultations
    const consultEl = document.getElementById('chr-consultations-body');
    if (consultEl) {
      const rows = consultRes.data || [];
      if (!rows.length) {
        consultEl.innerHTML = chrEmptyState('No consultation records found.');
      } else {
        consultEl.innerHTML = `
          <table class="accounts-table" style="width:100%;">
            <thead><tr class="table-header-row">
              <th class="table-header-cell">Date</th>
              <th class="table-header-cell">Diagnosis</th>
              <th class="table-header-cell">Doctor</th>
            </tr></thead>
            <tbody id="chr-consults-list"></tbody>
          </table>`;
        const tbody = document.getElementById('chr-consults-list');
        rows.forEach(r => {
          const tr = document.createElement('tr');
          tr.style.cursor = 'pointer';
          tr.innerHTML = `
            <td class="table-cell" style="white-space:nowrap;">${r.consulted_at ? new Date(r.consulted_at).toLocaleDateString() : '—'}</td>
            <td class="table-cell"><strong>${r.diagnosis || '—'}</strong></td>
            <td class="table-cell" style="white-space:nowrap;">${r.doctor ? `Dr. ${r.doctor.first_name} ${r.doctor.last_name}` : '—'}</td>
          `;
          tr.addEventListener('click', () => {
            showDataDetail('Consultation Record', {
              'Date': r.consulted_at ? new Date(r.consulted_at).toLocaleString() : '—',
              'Doctor': r.doctor ? `Dr. ${r.doctor.first_name} ${r.doctor.last_name}` : '—',
              'Diagnosis': r.diagnosis || '—',
              'Symptoms': r.symptoms || '—',
              'HPI': r.hpi || '—',
              'PMH': r.pmh || '—',
              'Allergies': r.allergies || '—',
              'Physical Exam': r.physical_exam ? JSON.stringify(r.physical_exam, null, 2) : '—',
              'Doctor Notes': r.notes || '—'
            });
          });
          tbody.appendChild(tr);
        });
      }
    }

    // Render Vitals
    const vitalsEl = document.getElementById('chr-vitals-body');
    if (vitalsEl) {
      const rows = vitalsRes.data || [];
      if (!rows.length) {
        vitalsEl.innerHTML = chrEmptyState('No vital sign records found.');
      } else {
        vitalsEl.innerHTML = `
          <table class="accounts-table" style="width:100%;">
            <thead><tr class="table-header-row">
              <th class="table-header-cell">Date</th>
              <th class="table-header-cell">Assessment</th>
              <th class="table-header-cell">Nurse</th>
            </tr></thead>
            <tbody id="chr-vitals-list"></tbody>
          </table>`;
        const tbody = document.getElementById('chr-vitals-list');
        rows.forEach(r => {
          const tr = document.createElement('tr');
          tr.style.cursor = 'pointer';
          tr.innerHTML = `
            <td class="table-cell" style="white-space:nowrap;">${r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'}</td>
            <td class="table-cell">BP: ${r.blood_pressure || '—'} | Temp: ${r.temperature || '—'}°C</td>
            <td class="table-cell" style="white-space:nowrap;">${r.nurse ? `${r.nurse.first_name} ${r.nurse.last_name}` : '—'}</td>
          `;
          tr.addEventListener('click', () => {
            showDataDetail('Vital Assessment', {
              'Date': r.created_at ? new Date(r.created_at).toLocaleString() : '—',
              'Assessed By': r.nurse ? `${r.nurse.first_name} ${r.nurse.last_name}` : '—',
              'Chief Complaint': r.chief_complaint || '—',
              'Blood Pressure': r.blood_pressure || '—',
              'Temperature': r.temperature ? `${r.temperature} °C` : '—',
              'Heart Rate': r.heart_rate ? `${r.heart_rate} bpm` : '—',
              'Resp. Rate': r.respiratory_rate ? `${r.respiratory_rate} bpm` : '—',
              'SpO2': r.oxygen_saturation ? `${r.oxygen_saturation}%` : '—',
              'Current Meds': r.current_medications || '—',
              'Notes': r.notes || '—'
            });
          });
          tbody.appendChild(tr);
        });
      }
    }

    // Render Prescriptions
    const rxEl = document.getElementById('chr-prescriptions-body');
    if (rxEl) {
      const rows = rxRes.data || [];
      if (!rows.length) {
        rxEl.innerHTML = chrEmptyState('No prescriptions found.');
      } else {
        rxEl.innerHTML = rows.map(rx => {
          const items = (rx.items || []).map(it =>
            `<li style="font-size:12px;color:#374151;">${it.medicine_name} — ${it.quantity} ${it.unit || ''} ${it.dosage ? `(${it.dosage})` : ''} ${it.frequency || ''} ${it.duration ? `for ${it.duration}` : ''}</li>`
          ).join('');
          const doctor = rx.doctor ? `Dr. ${rx.doctor.first_name} ${rx.doctor.last_name}` : '—';
          const date = rx.issued_at ? new Date(rx.issued_at).toLocaleDateString() : '—';
          return `
            <div style="border:1px solid #e2e8f0;border-radius:10px;padding:14px 16px;margin-bottom:10px;">
              <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-size:13px;font-weight:600;color:#1e293b;">${date}</span>
                <span style="font-size:12px;color:#64748b;">${doctor}</span>
              </div>
              <ul style="margin:0;padding-left:18px;">${items || '<li style="font-size:12px;color:#94a3b8;">No items</li>'}</ul>
            </div>`;
        }).join('');
      }
    }

    // Render Lab Orders
    const labEl = document.getElementById('chr-laborders-body');
    if (labEl) {
      const rows = labRes.data || [];
      if (!rows.length) {
        labEl.innerHTML = chrEmptyState('No lab orders found.');
      } else {
        labEl.innerHTML = `
          <table class="accounts-table" style="width:100%;">
            <thead><tr class="table-header-row">
              <th class="table-header-cell">Date</th>
              <th class="table-header-cell">Test</th>
              <th class="table-header-cell">Status</th>
              <th class="table-header-cell">Doctor</th>
            </tr></thead>
            <tbody>${rows.map(r => {
              const statusClass = r.status === 'Completed' ? 'badge badge-success' : 'badge badge-warning';
              return `<tr>
                <td class="table-cell" style="white-space:nowrap;">${r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'}</td>
                <td class="table-cell"><strong>${r.test_name || '—'}</strong></td>
                <td class="table-cell"><span class="${statusClass}">${r.status || '—'}</span></td>
                <td class="table-cell" style="white-space:nowrap;">${r.doctor ? `Dr. ${r.doctor.first_name} ${r.doctor.last_name}` : '—'}</td>
              </tr>`;
            }).join('')}
            </tbody>
          </table>`;
      }
    }


  } catch (err) {
    console.error('Failed to load citizen health records:', err);
    ['chr-consultations-body','chr-vitals-body','chr-prescriptions-body','chr-laborders-body','chr-appointments-body']
      .forEach(id => {
        const el = document.getElementById(id);
        if (el) el.innerHTML = chrEmptyState('Failed to load records.');
      });
  }
}



function applyStaffFinder() {
  const query = String(staffFinderInput?.value || '').trim().toLowerCase();
  const selectedRole = String(roleFilterInput?.value || '').trim().toLowerCase();
  const rows = document.querySelectorAll('#accounts-tbody tr.account-row');
  rows.forEach((row) => {
    const text = row.textContent ? row.textContent.toLowerCase() : '';
    const rowRole = String(row.getAttribute('data-role') || '').trim().toLowerCase();
    const matchesQuery = !query || text.includes(query);
    const matchesRole = !selectedRole || rowRole === selectedRole;
    row.style.display = matchesQuery && matchesRole ? '' : 'none';
  });
}


function renderCitizensTable(filteredList) {
  if (!patientsTbody) return;

  swapContainer(patientsTbody, (fragment) => {
    if (filteredList.length === 0) {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td class="table-cell" colspan="4">No citizen accounts found.</td>';
      fragment.appendChild(tr);
      return;
    }
    filteredList.forEach(user => {
      const row = document.createElement('tr');
      row.className = 'citizen-row';
      row.style.cursor = 'pointer';
      const fullName = [user.firstname, user.surname].filter(Boolean).join(' ') || user.username || '—';
      row.innerHTML = `
        <td class="table-cell">${fullName}</td>
        <td class="table-cell">${user.email || '—'}</td>
        <td class="table-cell">${user.contact_number || '—'}</td>
        <td class="table-cell">${formatDateTime(user.created_at)}</td>
        <td class="table-cell" style="text-align:center;">
          <button class="chip-btn" style="margin:0; padding:4px 12px; font-size:11px; background:#f0f9ff; color:#0369a1; border:1px solid #bae6fd;">View Records</button>
        </td>
      `;
      row.addEventListener('click', async () => {
        // Fetch full citizen profile (includes health-related fields not in the list query)
        try {
          const { supabase } = await loadSupabaseModule();
          const { data } = await supabase
            .from('citizens')
            .select('id,firstname,surname,username,email,contact_number,sex,age,date_of_birth,complete_address,emergency_contact_complete_name,emergency_contact_contact_number,relation,created_at')
            .eq('id', user.id)
            .single();
          openCitizenHealthModal(data || user);
        } catch (_) {
          openCitizenHealthModal(user);
        }
      });
      fragment.appendChild(row);
    });
  });
}


function applyCitizensFinder() {
  const query = String(citizensFinderInput?.value || '').trim().toLowerCase();
  const filtered = latestPatientsList.filter((citizen) => {
    if (!query) return true;
    const fullName = [citizen.firstname, citizen.surname].filter(Boolean).join(' ').toLowerCase();
    const username = String(citizen?.username || '').toLowerCase();
    const email = String(citizen?.email || '').toLowerCase();
    const contact = String(citizen?.contact_number || '').toLowerCase();
    return fullName.includes(query) || username.includes(query) || email.includes(query) || contact.includes(query);
  });

  renderCitizensTable(filtered);
}

if (staffFinderInput) {
  staffFinderInput.addEventListener('input', applyStaffFinder);
}

if (roleFilterInput) {
  roleFilterInput.addEventListener('change', applyStaffFinder);
}

if (citizensFinderInput) {
  citizensFinderInput.addEventListener('input', applyCitizensFinder);
}



function toggleUsersPane(targetId = 'accounts-pane') {
  userPaneIds.forEach((paneId) => {
    const pane = document.getElementById(paneId);
    if (!pane) return;
    if (paneId === targetId) pane.classList.remove('hidden');
    else pane.classList.add('hidden');
  });
}

function revealPane(paneId) {
  if (!paneId) return;
  const paneEl = document.getElementById(paneId);
  if (!paneEl) return;
  paneEl.classList.remove('hidden');

  // Update Users Section Title if applicable
  const mgmtTitle = document.getElementById('user-mgmt-title');
  if (mgmtTitle) {
    if (paneId === 'registered-pane') mgmtTitle.textContent = 'Staff Management';
    else if (paneId === 'citizens-pane') mgmtTitle.textContent = 'Citizen Management';
  }

  const parent = paneEl.parentElement;
  if (!parent) return;
  Array.from(parent.children).forEach((sibling) => {
    if (sibling === paneEl) return;
    if (sibling.id && sibling.id.endsWith('-pane')) sibling.classList.add('hidden');
  });
}

function hideAllSections() {
  // Hide ALL section-top elements
  document.querySelectorAll('.section-top').forEach(section => section.classList.add('hidden'));
  // Hide specific panes too
  document.querySelectorAll('[id*="-pane"].hidden, .tab-pane').forEach(pane => pane.classList.add('hidden'));
}

function clearActiveNav() {
  // Clear ALL active nav states
  document.querySelectorAll('[data-section], .nav-btn, .nav-item.is-active').forEach(el => el.classList.remove('is-active'));
  document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
}

function navigateToSection(sectionId, options = {}) {
  const targetId = document.getElementById(sectionId) ? sectionId : DEFAULT_SECTION_ID;
  let currentRole = getSessionRole();
  if (currentRole === 'staff') currentRole = 'nurse';
  const allowedTarget = isSectionAllowedForRole(targetId, currentRole)
    ? targetId
    : (isSectionAllowedForRole('users-section', currentRole) ? 'users-section' : 'profile-section');

  if (allowedTarget !== targetId) {
    showToast('Access denied for this section.', 'warning');
  }

  hideAllSections();
  clearActiveNav();
  const targetSection = document.getElementById(allowedTarget);
  if (targetSection) targetSection.classList.remove('hidden');
  showSection(allowedTarget, options);
  const navMatch = document.querySelector(`.nav [data-section="${allowedTarget}"]`);
  if (navMatch) navMatch.classList.add('is-active');
  setSectionHash(allowedTarget);
}





// Reports tabs switching
const tabFeedback = document.getElementById('tab-feedback');
const tabAnnouncements = document.getElementById('tab-announcements');
const feedbackPane = document.getElementById('feedback-pane');
const announcementsPane = document.getElementById('announcements-pane');
if (tabFeedback && tabAnnouncements && feedbackPane && announcementsPane) {
  tabFeedback.addEventListener('click', () => {
    tabFeedback.classList.add('active');
    tabAnnouncements.classList.remove('active');
    feedbackPane.classList.remove('hidden');
    announcementsPane.classList.add('hidden');
  });
  tabAnnouncements.addEventListener('click', () => {
    tabAnnouncements.classList.add('active');
    tabFeedback.classList.remove('active');
    announcementsPane.classList.remove('hidden');
    feedbackPane.classList.add('hidden');
  });
}

// Reports refresh button
const reportsRefreshBtn = document.getElementById('reports-refresh-btn');
if (reportsRefreshBtn) {
  reportsRefreshBtn.addEventListener('click', async () => {
    await Promise.all([refreshAnnouncementsData(), refreshFeedbackData()]);
    showToast('Reports data refreshed.', 'info');
  });
}

// Create announcement modal handlers
const createAnnouncementBtn = document.getElementById('create-announcement-btn');
const createAnnouncementModal = document.getElementById('create-announcement-modal');
const createAnnouncementForm = document.getElementById('create-announcement-form');
const annSubmitBtn = document.getElementById('ann-submit-btn');
const annCancelBtn = document.getElementById('ann-cancel-btn');
const annFormError = document.getElementById('ann-form-error');

const editAnnouncementModal = document.getElementById('edit-announcement-modal');
const editAnnouncementForm = document.getElementById('edit-announcement-form');
const editAnnIdInput = document.getElementById('edit-announcement-id');
const editAnnTitleInput = document.getElementById('edit-ann-title');
const editAnnContentInput = document.getElementById('edit-ann-content');
const editAnnSubmitBtn = document.getElementById('edit-ann-submit-btn');
const editAnnCancelBtn = document.getElementById('edit-ann-cancel-btn');
const editAnnFormError = document.getElementById('edit-ann-form-error');

let currentAnnouncementDetail = null;

function openEditAnnouncementModal(announcement) {
  if (!announcement || !editAnnouncementModal || !editAnnouncementForm) return;

  currentAnnouncementDetail = announcement;
  if (editAnnIdInput) editAnnIdInput.value = String(announcement.id || '');
  if (editAnnTitleInput) editAnnTitleInput.value = String(announcement.title || '').trim();
  if (editAnnContentInput) editAnnContentInput.value = String(announcement.content || announcement.body || '').trim();
  const visibilitySelect = document.getElementById('edit-ann-visibility');
  if (visibilitySelect) visibilitySelect.value = String(announcement.visibility || 'all').trim();
  if (editAnnFormError) editAnnFormError.style.display = 'none';

  editAnnouncementModal.classList.remove('hidden');
}

function closeEditAnnouncementModal() {
  if (!editAnnouncementModal) return;
  editAnnouncementModal.classList.add('hidden');
  if (editAnnouncementForm) editAnnouncementForm.reset();
  if (editAnnFormError) editAnnFormError.style.display = 'none';
  currentAnnouncementDetail = null;
}

if (createAnnouncementBtn && createAnnouncementModal) {
  createAnnouncementBtn.addEventListener('click', () => {
    createAnnouncementModal.classList.remove('hidden');
  });
}

if (annCancelBtn && createAnnouncementModal) {
  annCancelBtn.addEventListener('click', () => {
    createAnnouncementModal.classList.add('hidden');
    if (createAnnouncementForm) createAnnouncementForm.reset();
    if (annFormError) annFormError.style.display = 'none';
  });
}

if (createAnnouncementModal) {
  createAnnouncementModal.addEventListener('click', (e) => {
    if (e.target === createAnnouncementModal) {
      createAnnouncementModal.classList.add('hidden');
      if (createAnnouncementForm) createAnnouncementForm.reset();
      if (annFormError) annFormError.style.display = 'none';
    }
  });
}

if (createAnnouncementForm && annSubmitBtn) {
  createAnnouncementForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const title = document.getElementById('ann-title').value.trim();
    const content = document.getElementById('ann-content').value.trim();
    const visibility = (document.getElementById('ann-visibility')?.value || 'all').trim();

    if (!title || !content) {
      if (annFormError) {
        annFormError.textContent = 'Title and content are required.';
        annFormError.style.display = 'block';
      }
      return;
    }

    annSubmitBtn.disabled = true;
    const spinner = annSubmitBtn.querySelector('.btn-spinner');
    const label = annSubmitBtn.querySelector('.btn-label');
    if (spinner) spinner.style.display = 'inline-block';
    if (label) label.textContent = 'PUBLISHING...';

    try {
      await createAnnouncementEntry({ title, content, visibility });
      await refreshAnnouncementsData();
      renderDashboardInsights();

      showToast('Announcement created successfully.', 'success');
      if (createAnnouncementModal) createAnnouncementModal.classList.add('hidden');
      createAnnouncementForm.reset();
    } catch (error) {
      console.error('Error:', error);
      if (annFormError) {
        annFormError.textContent = 'Failed to create announcement.';
        annFormError.style.display = 'block';
      }
    } finally {
      annSubmitBtn.disabled = false;
      if (spinner) spinner.style.display = 'none';
      if (label) label.textContent = 'PUBLISH ANNOUNCEMENT';
    }
  });
}

if (editAnnCancelBtn) {
  editAnnCancelBtn.addEventListener('click', () => {
    closeEditAnnouncementModal();
  });
}

if (editAnnouncementModal) {
  editAnnouncementModal.addEventListener('click', (event) => {
    if (event.target === editAnnouncementModal) {
      closeEditAnnouncementModal();
    }
  });
}

if (editAnnouncementForm && editAnnSubmitBtn) {
  editAnnouncementForm.addEventListener('submit', async (event) => {
    event.preventDefault();

    const announcementId = String(editAnnIdInput?.value || '').trim();
    const title = String(editAnnTitleInput?.value || '').trim();
    const content = String(editAnnContentInput?.value || '').trim();
    const visibility = (document.getElementById('edit-ann-visibility')?.value || 'all').trim();

    if (!announcementId || !title || !content) {
      if (editAnnFormError) {
        editAnnFormError.textContent = 'Announcement ID, title, and content are required.';
        editAnnFormError.style.display = 'block';
      }
      return;
    }

    editAnnSubmitBtn.disabled = true;
    const spinner = editAnnSubmitBtn.querySelector('.btn-spinner');
    const label = editAnnSubmitBtn.querySelector('.btn-label');
    if (spinner) spinner.style.display = 'inline-block';
    if (label) label.textContent = 'SAVING...';

    try {
      await updateAnnouncementEntry(announcementId, { title, content, visibility });
      await refreshAnnouncementsData();
      renderDashboardInsights();

      closeEditAnnouncementModal();
      showToast('Announcement updated successfully.', 'success');
    } catch (error) {
      console.error('Error updating announcement:', error);
      if (editAnnFormError) {
        editAnnFormError.textContent = error.message || 'Failed to update announcement.';
        editAnnFormError.style.display = 'block';
      }
    } finally {
      editAnnSubmitBtn.disabled = false;
      if (spinner) spinner.style.display = 'none';
      if (label) label.textContent = 'SAVE CHANGES';
    }
  });
}

// Top-right quick create announcement button (same modal)
const createAnnouncementTopBtn = document.getElementById('create-announcement-topright');
if (createAnnouncementTopBtn && createAnnouncementModal) {
  createAnnouncementTopBtn.addEventListener('click', () => {
    createAnnouncementModal.classList.remove('hidden');
  });
}

// Announcement detail modal logic
const announcementDetailModal = document.getElementById('announcement-detail-modal');
const announcementDetailClose = document.getElementById('announcement-detail-close');
const announcementDetailDelete = document.getElementById('announcement-detail-delete');
const announcementDetailTitle = document.getElementById('announcement-detail-title');
const announcementDetailBody = document.getElementById('announcement-detail-body');
const announcementDetailDate = document.getElementById('announcement-detail-date');
const dataDetailModal = document.getElementById('data-detail-modal');
const dataDetailDismissBtn = document.getElementById('data-detail-dismiss');
const dataDetailActions = document.getElementById('data-detail-actions');
const dataDetailTitle = document.getElementById('data-detail-title');
const dataDetailSubtitle = document.getElementById('data-detail-subtitle');
const dataDetailList = document.getElementById('data-detail-list');
const dataDetailTag = document.getElementById('data-detail-tag');

function formatDetailValue(value) {
  if (value === null || value === undefined) return '—';
  if (Array.isArray(value)) return value.length ? value.join(', ') : '—';
  if (value instanceof Date) {
    return Number.isNaN(value.getTime())
      ? '—'
      : value.toLocaleString([], {
        year: 'numeric',
        month: 'numeric',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        second: '2-digit',
        hour12: true
      });
  }
  if (typeof value === 'object') {
    return Object.keys(value).length ? JSON.stringify(value, null, 2) : '—';
  }
  const str = String(value).trim();
  return str || '—';
}

function openDataDetail(config = {}) {
  if (!dataDetailModal) return;
  const {
    title = 'Record Detail',
    subtitle = '',
    tag = '',
    items = [],
    actions = []
  } = config;

  if (dataDetailTitle) dataDetailTitle.textContent = title;
  if (dataDetailSubtitle) {
    dataDetailSubtitle.textContent = subtitle || '';
    dataDetailSubtitle.style.display = subtitle ? 'block' : 'none';
  }
  if (dataDetailTag) {
    dataDetailTag.textContent = tag || '';
    dataDetailTag.style.display = tag ? 'block' : 'none';
  }

  if (dataDetailList) {
    dataDetailList.innerHTML = '';
    if (!items.length) {
      const fallbackDt = document.createElement('dt');
      fallbackDt.textContent = 'Details';
      const fallbackDd = document.createElement('dd');
      fallbackDd.textContent = 'No additional data available.';
      dataDetailList.appendChild(fallbackDt);
      dataDetailList.appendChild(fallbackDd);
    } else {
      items.forEach(({ label, value }) => {
        const dt = document.createElement('dt');
        dt.textContent = label || '';
        const dd = document.createElement('dd');
        dd.textContent = formatDetailValue(value);
        dataDetailList.appendChild(dt);
        dataDetailList.appendChild(dd);
      });
    }
  }

  if (dataDetailActions) {
    dataDetailActions.querySelectorAll('button[data-detail-dynamic="true"]').forEach(btn => btn.remove());
    if (Array.isArray(actions) && actions.length) {
      actions.forEach(action => {
        if (!action || typeof action.onClick !== 'function') return;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.dataset.detailDynamic = 'true';
        const baseClass = action.className || 'btn';
        btn.className = baseClass;
        btn.textContent = action.label || 'Action';
        btn.addEventListener('click', (event) => {
          event.preventDefault();
          action.onClick(event);
        });
        if (dataDetailDismissBtn) {
          dataDetailActions.insertBefore(btn, dataDetailDismissBtn);
        } else {
          dataDetailActions.appendChild(btn);
        }
      });
    }
  }

  dataDetailModal.classList.remove('hidden');
}

function closeDataDetail() {
  if (dataDetailModal) dataDetailModal.classList.add('hidden');
}

function attachDetailRow(row, detailFactory) {
  if (!row || typeof detailFactory !== 'function' || !dataDetailModal) return;
  if (row.dataset.detailAttached === 'true') return;
  row.dataset.detailAttached = 'true';
  row.style.cursor = 'pointer';
  row.addEventListener('click', (event) => {
    if (event.target.closest('button, a, input, textarea, select, label')) return;
    const detail = detailFactory(row);
    if (detail) openDataDetail(detail);
  });
}


if (dataDetailDismissBtn) dataDetailDismissBtn.addEventListener('click', closeDataDetail);
if (dataDetailModal) {
  dataDetailModal.addEventListener('click', (event) => {
    if (event.target === dataDetailModal) closeDataDetail();
  });
}
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (dataDetailModal && !dataDetailModal.classList.contains('hidden')) {
    closeDataDetail();
  }
  if (notificationPanel && !notificationPanel.classList.contains('hidden')) {
    hideNotificationPanel();
  }
  if (dialogModal && !dialogModal.classList.contains('hidden')) {
    closeDialogModal({ confirmed: false, values: [] });
  }
});

if (announcementDetailModal) {
  announcementDetailModal.addEventListener('click', (e) => {
    if (e.target === announcementDetailModal || e.target.classList.contains('modal-close')) {
      announcementDetailModal.classList.add('hidden');
      currentAnnouncementDetail = null;
    }
  });
}
if (announcementDetailClose) {
  announcementDetailClose.addEventListener('click', () => {
    announcementDetailModal.classList.add('hidden');
    currentAnnouncementDetail = null;
  });
}

if (announcementDetailDelete) {
  announcementDetailDelete.addEventListener('click', async () => {
    if (!isAdminUser(cachedSessionUser)) return;
    const announcementId = currentAnnouncementDetail?.id;
    if (!announcementId) return;

    const confirmation = await openDialogModal({
      title: 'Delete Announcement',
      message: 'Delete this announcement? This cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel'
    });
    if (!confirmation.confirmed) return;

    try {
      await deleteAnnouncementEntry(announcementId);
      await refreshAnnouncementsData();
      renderDashboardInsights();
      announcementDetailModal.classList.add('hidden');
      currentAnnouncementDetail = null;
      showToast('Announcement deleted successfully.', 'success');
    } catch (error) {
      console.error('Error deleting announcement:', error);
      showToast(error.message || 'Failed to delete announcement.', 'error');
    }
  });
}





const dashboardLink = document.querySelector('.nav-item[data-section="dashboard"]');
if (dashboardLink && !dashboardLink.classList.contains('hidden')) {
  dashboardLink.classList.add('is-active');
}

// Stored accounts (identifier -> account data)
const storedAccounts = new Map();
let latestStaffList = [];
let latestPatientsList = [];
let latestAnnouncementsList = [];
let latestFeedbackList = [];

// ═══════════════════════════════════════════════════════════════════════════
// FEEDBACK DATA LOADING AND RENDERING
// ═══════════════════════════════════════════════════════════════════════════

async function refreshFeedbackData() {
  if (isDemoMode) {
    // Demo mode: use mock data
    latestFeedbackList = [
      {
        id: 1,
        from_email: 'patient@example.com',
        subject: 'Great service!',
        message: 'The staff was very helpful and professional.',
        rating: 5,
        created_at: new Date().toISOString()
      },
      {
        id: 2,
        from_email: 'user@test.com',
        subject: 'Long wait time',
        message: 'Had to wait for 2 hours before being seen.',
        rating: 3,
        created_at: new Date(Date.now() - 86400000).toISOString()
      }
    ];
    renderFeedbackTable();
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();
    const { data, error } = await supabase
      .from('feedbacks')
      .select(`
        id,
        from_email,
        subject,
        message,
        rating,
        created_at,
        citizen:citizens(id, firstname, surname, email)
      `)
      .order('created_at', { ascending: false })
      .limit(100);

    if (error) {
      console.error('Failed to load feedback:', error);
      showToast('Failed to load feedback data.', 'error');
      latestFeedbackList = [];
      return;
    }

    latestFeedbackList = (data || []).map(item => ({
      id: item.id,
      from_email: item.from_email || item.citizen?.email || 'Anonymous',
      subject: item.subject || 'No subject',
      message: item.message || '',
      rating: item.rating,
      created_at: item.created_at,
      citizen_name: item.citizen 
        ? `${item.citizen.firstname || ''} ${item.citizen.surname || ''}`.trim() 
        : null
    }));

    renderFeedbackTable();
  } catch (err) {
    console.error('Error loading feedback:', err);
    latestFeedbackList = [];
  }
}

function renderFeedbackTable() {
  const tbody = document.getElementById('feedback-tbody');
  if (!tbody) return;

  if (!latestFeedbackList || latestFeedbackList.length === 0) {
    tbody.innerHTML = `
      <tr class="empty-row">
        <td colspan="5" style="text-align:center; padding:40px; color:#64748b;">
          No feedback received yet
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = latestFeedbackList.map(feedback => {
    const rating = feedback.rating ? '⭐'.repeat(feedback.rating) : '—';
    const fromName = feedback.citizen_name || feedback.from_email || 'Anonymous';
    const date = formatDateTime(feedback.created_at);

    return `
      <tr class="clickable-row" data-id="${feedback.id}">
        <td class="table-cell"><strong>${escapeHtml(fromName)}</strong></td>
        <td class="table-cell" style="text-align:center;">${rating}</td>
        <td class="table-cell" style="color:#64748b; font-size:12px; text-align:center;">${date}</td>
        <td class="table-cell" style="text-align:center;">
          <button class="chip-btn chip-btn-danger btn-delete-feedback" data-id="${feedback.id}" style="padding:4px 8px; font-size:10px;">Delete</button>
        </td>
      </tr>
    `;
  }).join('');
}

function openFeedbackDetail(id) {
  const feedback = latestFeedbackList.find(f => f.id === id);
  if (!feedback) return;

  const modal = document.getElementById('feedback-detail-modal');
  const fromEl = document.getElementById('feedback-detail-from');
  const dateEl = document.getElementById('feedback-detail-date');
  const ratingEl = document.getElementById('feedback-detail-rating');
  const subjectEl = document.getElementById('feedback-detail-subject');
  const bodyEl = document.getElementById('feedback-detail-body');
  const deleteBtn = document.getElementById('feedback-detail-delete-btn');

  if (fromEl) fromEl.textContent = feedback.citizen_name || feedback.from_email || 'Anonymous';
  if (dateEl) dateEl.textContent = formatDateTime(feedback.created_at);
  if (ratingEl) ratingEl.innerHTML = feedback.rating ? '⭐'.repeat(feedback.rating) : '—';
  if (subjectEl) subjectEl.textContent = feedback.subject || 'No Subject';
  if (bodyEl) bodyEl.textContent = feedback.message || '';
  if (deleteBtn) deleteBtn.onclick = () => deleteFeedback(feedback.id);

  modal?.classList.remove('hidden');
}

async function deleteFeedback(id) {
  if (!confirm('Are you sure you want to delete this feedback?')) return;
  
  try {
    const { supabase } = await loadSupabaseModule();
    const { error } = await supabase.from('feedbacks').delete().eq('id', id);
    
    if (error) throw error;
    
    showToast('Feedback deleted.', 'success');
    latestFeedbackList = latestFeedbackList.filter(f => f.id !== id);
    renderFeedbackTable();
    // Close the detail modal if open
    document.getElementById('feedback-detail-modal')?.classList.add('hidden');
  } catch (err) {
    console.error('Error deleting feedback:', err);
    showToast('Failed to delete feedback.', 'error');
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

let reportsInitialized = false;
function initReportsSection() {
  if (reportsInitialized) return;
  reportsInitialized = true;

  // Tab switching for Reports
  const reportTabs = document.querySelectorAll('#reports-section .tab');
  const panes = {
    'tab-announcements': document.getElementById('announcements-pane'),
    'tab-feedback': document.getElementById('feedback-pane'),
    'tab-stats': document.getElementById('stats-pane')
  };

  reportTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      reportTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      Object.values(panes).forEach(p => p?.classList.add('hidden'));
      if (panes[tab.id]) panes[tab.id].classList.remove('hidden');
      // If stats chart exists
      if (tab.id === 'tab-stats' && typeof initStatsCharts === 'function') initStatsCharts();
    });
  });

  // Event delegation for row clicks and deletes
  document.getElementById('announcements-tbody')?.addEventListener('click', (e) => {
    const btn = e.target.closest('.btn-delete-announcement');
    if (btn) {
      e.stopPropagation();
      deleteAnnouncement(Number(btn.dataset.id));
      return;
    }
    const row = e.target.closest('.clickable-row');
    if (row) openAnnouncementDetail(Number(row.dataset.id));
  });

  document.getElementById('feedback-tbody')?.addEventListener('click', (e) => {
    const btn = e.target.closest('.btn-delete-feedback');
    if (btn) {
      e.stopPropagation();
      deleteFeedback(Number(btn.dataset.id));
      return;
    }
    const row = e.target.closest('.clickable-row');
    if (row) openFeedbackDetail(Number(row.dataset.id));
  });

  // Close buttons for detail modals
  document.getElementById('announcement-detail-close')?.addEventListener('click', () => {
    document.getElementById('announcement-detail-modal')?.classList.add('hidden');
  });
  document.getElementById('feedback-detail-close')?.addEventListener('click', () => {
    document.getElementById('feedback-detail-modal')?.classList.add('hidden');
  });
  
  // Close on overlay click
  [document.getElementById('announcement-detail-modal'), document.getElementById('feedback-detail-modal')].forEach(m => {
    m?.addEventListener('click', (e) => {
      if (e.target === m) m.classList.add('hidden');
    });
  });
}

async function refreshAnnouncementsData() {
  if (isDemoMode) {
    latestAnnouncementsList = [
      {
        id: 1,
        title: 'Clinic Hours Update',
        content: 'The clinic will be open from 8 AM to 5 PM starting next week.',
        visibility: 'all',
        created_at: new Date().toISOString()
      },
      {
        id: 2,
        title: 'New Services Available',
        content: 'We now offer telemedicine consultations. Book your appointment today!',
        visibility: 'citizen',
        created_at: new Date(Date.now() - 86400000).toISOString()
      }
    ];
    renderAnnouncementsTable();
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();
    const { data, error } = await supabase
      .from('announcements')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) {
      console.error('Failed to load announcements:', error);
      latestAnnouncementsList = [];
      renderAnnouncementsTable();
      return;
    }

    latestAnnouncementsList = data || [];
    renderAnnouncementsTable();
  } catch (err) {
    console.error('Error loading announcements:', err);
    latestAnnouncementsList = [];
    renderAnnouncementsTable();
  }
}

function renderAnnouncementsTable() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;

  if (!latestAnnouncementsList || latestAnnouncementsList.length === 0) {
    tbody.innerHTML = `
      <tr class="empty-row">
        <td colspan="4" style="text-align:center; padding:40px; color:#64748b;">
          No announcements yet
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = latestAnnouncementsList.map(announcement => {
    const title = escapeHtml(announcement.title || 'Untitled');
    const visibilityBadge = getVisibilityBadge(announcement.visibility || 'all');
    const date = formatDateTime(announcement.created_at);

    return `
      <tr class="clickable-row" data-id="${announcement.id}">
        <td class="table-cell"><strong>${title}</strong></td>
        <td class="table-cell" style="text-align:center;">${visibilityBadge}</td>
        <td class="table-cell" style="color:#64748b; font-size:12px; text-align:center;">${date}</td>
        <td class="table-cell" style="text-align:center;">
          <button class="chip-btn chip-btn-danger btn-delete-announcement" data-id="${announcement.id}" style="padding:4px 8px; font-size:10px;">Delete</button>
        </td>
      </tr>
    `;
  }).join('');
}

function openAnnouncementDetail(id) {
  const ann = latestAnnouncementsList.find(a => a.id === id);
  if (!ann) return;

  const modal = document.getElementById('announcement-detail-modal');
  const titleEl = document.getElementById('announcement-detail-title');
  const dateEl = document.getElementById('announcement-detail-date');
  const visEl = document.getElementById('announcement-detail-visibility');
  const bodyEl = document.getElementById('announcement-detail-body');
  const deleteBtn = document.getElementById('announcement-detail-delete-btn');

  if (titleEl) titleEl.textContent = ann.title || 'Untitled';
  if (dateEl) dateEl.textContent = formatDateTime(ann.created_at);
  if (visEl) visEl.innerHTML = getVisibilityBadge(ann.visibility || 'all');
  if (bodyEl) bodyEl.textContent = ann.content || '';
  if (deleteBtn) deleteBtn.onclick = () => deleteAnnouncement(ann.id);

  modal?.classList.remove('hidden');
}

async function deleteAnnouncement(id) {
  if (!confirm('Are you sure you want to delete this announcement?')) return;
  
  try {
    const { supabase } = await loadSupabaseModule();
    const { error } = await supabase.from('announcements').delete().eq('id', id);
    
    if (error) throw error;
    
    showToast('Announcement deleted.', 'success');
    latestAnnouncementsList = latestAnnouncementsList.filter(a => a.id !== id);
    renderAnnouncementsTable();
    // Close the detail modal if open
    document.getElementById('announcement-detail-modal')?.classList.add('hidden');
  } catch (err) {
    console.error('Error deleting announcement:', err);
    showToast('Failed to delete announcement.', 'error');
  }
}

function getVisibilityBadge(visibility) {
  const badges = {
    'all': '<span class="badge" style="background:#e0f2fe; color:#0369a1; font-size:11px; padding:4px 10px;">All</span>',
    'staff': '<span class="badge" style="background:#fef3c7; color:#92400e; font-size:11px; padding:4px 10px;">Staff</span>',
    'citizen': '<span class="badge" style="background:#dcfce7; color:#166534; font-size:11px; padding:4px 10px;">Citizens</span>'
  };
  return badges[visibility] || badges['all'];
}

async function createAnnouncementEntry({ title, content, visibility }) {
  if (isDemoMode) {
    const newAnnouncement = {
      id: Date.now(),
      title,
      content,
      visibility,
      created_at: new Date().toISOString()
    };
    latestAnnouncementsList.unshift(newAnnouncement);
    renderAnnouncementsTable();
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();
    const { data, error } = await supabase
      .from('announcements')
      .insert([{
        title: title.trim(),
        content: content.trim(),
        visibility: visibility || 'all'
      }])
      .select()
      .single();

    if (error) {
      throw new Error(error.message || 'Failed to create announcement');
    }

    return data;
  } catch (err) {
    console.error('Error creating announcement:', err);
    throw err;
  }
}

function formatDateTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString([], {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
    hour12: true
  });
}

function isCurrentlyLoggedInStaffAccount(user) {
  const lastSeenValue = user?.last_seen;
  if (!lastSeenValue) return false;

  const lastSeenAt = new Date(lastSeenValue).getTime();
  if (!Number.isFinite(lastSeenAt)) return false;

  return Date.now() - lastSeenAt <= STAFF_PRESENCE_TIMEOUT_MS;
}

function getStaffPresenceStatus(user) {
  return isCurrentlyLoggedInStaffAccount(user) ? 'Active' : 'Inactive';
}

function getStaffPresenceBadgeClass(user) {
  return isCurrentlyLoggedInStaffAccount(user) ? 'badge-active' : 'badge-inactive';
}

async function pushPresenceHeartbeat() {
  if (isDemoMode) return;

  try {
    const authService = await loadAuthServiceModule();
    await authService.setStaffPresence(true);
  } catch (error) {
    console.warn('Presence heartbeat warning:', error);
  }
}

function stopPresenceHeartbeat() {
  if (!presenceHeartbeatTimer) return;
  clearInterval(presenceHeartbeatTimer);
  presenceHeartbeatTimer = null;
}

function stopAdminDashboardAutoRefresh() {
  if (!adminDashboardRefreshTimer) return;
  clearInterval(adminDashboardRefreshTimer);
  adminDashboardRefreshTimer = null;
}

function startAdminDashboardAutoRefresh() {
  if (adminDashboardRefreshTimer) return;

  const runRefresh = async () => {
    if (adminDashboardRefreshInFlight) return;
    adminDashboardRefreshInFlight = true;
    try {
      await loadStaffData();
    } catch (_) {
      // Keep auto-refresh resilient.
    } finally {
      adminDashboardRefreshInFlight = false;
    }
  };

  adminDashboardRefreshTimer = setInterval(runRefresh, ADMIN_DASHBOARD_REFRESH_MS);
}

function startPresenceHeartbeat() {
  if (isDemoMode || presenceHeartbeatTimer) return;

  pushPresenceHeartbeat();
  presenceHeartbeatTimer = setInterval(pushPresenceHeartbeat, STAFF_PRESENCE_HEARTBEAT_MS);
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

function clearSessionAuthStorageBestEffort() {
  try {
    const keys = Object.keys(window.sessionStorage || {});
    for (const key of keys) {
      if (!key) continue;
      if (key === 'ukonek_role' || key === 'ukonek.auth.session' || key === 'ukonek.auth.tab_id') {
        sessionStorage.removeItem(key);
        continue;
      }

      if (key.startsWith('sb-') && key.includes('-auth-tab-')) {
        sessionStorage.removeItem(key);
      }
    }
  } catch (_) {
    // Ignore storage failures in unload path.
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
  stopAdminDashboardAutoRefresh();
  sendOfflinePresenceOnUnload();
  markStaffOfflineBestEffort();
}

function renderDashboardInsights() {
  if (statTotalStaff) statTotalStaff.textContent = String(latestStaffList.length);

  const announcementsCount = latestAnnouncementsList.length || 0;
  if (statAnnouncements) statAnnouncements.textContent = String(announcementsCount);

  const feedbackCount = latestFeedbackList.length || 0;
  if (statReports) statReports.textContent = String(feedbackCount);

  // Citizens count
  if (statPatients) statPatients.textContent = String(latestPatientsList.length || 0);

  const doctorsCount = latestStaffList.filter((user) => isDoctorRole(user?.role)).length;
  if (statDoctors) statDoctors.textContent = String(doctorsCount);

  const activeCount = latestStaffList.filter(isCurrentlyLoggedInStaffAccount).length;
  if (statActiveStaff) statActiveStaff.textContent = String(activeCount);

  if (dashboardActivePreview) {
    const rows = latestStaffList.slice(0, 5);
    dashboardActivePreview.innerHTML = rows.length
      ? rows.map((user) => `
          <tr>
            <td class="table-cell">${user.username || '—'}</td>
            <td class="table-cell">${user.role ? user.role.charAt(0).toUpperCase() + user.role.slice(1) : '—'}</td>
            <td class="table-cell"><span class="${getStaffPresenceBadgeClass(user)}">${getStaffPresenceStatus(user)}</span></td>
            <td class="table-cell">${formatDateTime(user.created_at)}</td>
          </tr>
        `).join('')
      : '<tr><td class="table-cell" colspan="4">No active accounts found.</td></tr>';
  }

  if (dashboardLastSync) {
    dashboardLastSync.textContent = `Last synced: ${new Date().toLocaleTimeString([], {
      hour: 'numeric',
      minute: '2-digit',
      second: '2-digit',
      hour12: true
    })}`;
  }

  renderDashboardChart();
}

function renderDashboardChart() {
  const canvas = document.getElementById('dashboard-chart');
  const emptyNode = document.getElementById('dashboard-chart-empty');
  const legendList = document.getElementById('dashboard-chart-legend');
  if (!canvas || typeof canvas.getContext !== 'function') return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const metrics = [
    { label: 'Staff', value: latestStaffList.length, color: '#3b82f6' },
    { label: 'Announcements', value: latestAnnouncementsList.length || 0, color: '#14b8a6' },
    { label: 'Feedback', value: latestFeedbackList.length || 0, color: '#a855f7' }
  ];

  const total = metrics.reduce((sum, metric) => sum + (metric.value || 0), 0);
  const hasData = total > 0;

  if (emptyNode) emptyNode.classList.toggle('hidden', hasData);
  if (legendList) {
    legendList.innerHTML = '';
    legendList.classList.toggle('hidden', !hasData);
    if (hasData) {
      metrics.forEach((metric) => {
        const item = document.createElement('li');
        const dot = document.createElement('span');
        dot.className = 'stats-chart-dot';
        dot.style.background = metric.color;
        item.appendChild(dot);
        const label = document.createElement('span');
        label.className = 'stats-chart-label';
        label.textContent = metric.label;
        item.appendChild(label);
        const value = document.createElement('strong');
        value.className = 'stats-chart-value';
        value.textContent = metric.value;
        item.appendChild(value);
        legendList.appendChild(item);
      });
    }
  }

  const baseSize = 320;
  const ratio = window.devicePixelRatio || 1;
  canvas.width = baseSize * ratio;
  canvas.height = baseSize * ratio;
  canvas.style.width = `${baseSize}px`;
  canvas.style.height = `${baseSize}px`;
  if (typeof ctx.resetTransform === 'function') ctx.resetTransform();
  else ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.scale(ratio, ratio);

  if (!hasData) {
    if (chartAnimationState.frameId) {
      cancelAnimationFrame(chartAnimationState.frameId);
      chartAnimationState.frameId = null;
    }
    ctx.clearRect(0, 0, baseSize, baseSize);
    return;
  }

  const segments = metrics
    .filter((metric) => metric.value > 0)
    .map((metric) => ({
      color: metric.color,
      ratio: metric.value / total
    }));

  if (!segments.length) {
    ctx.clearRect(0, 0, baseSize, baseSize);
    return;
  }

  if (chartAnimationState.frameId) {
    cancelAnimationFrame(chartAnimationState.frameId);
    chartAnimationState.frameId = null;
  }

  const dimensions = {
    baseSize,
    centerX: baseSize / 2,
    centerY: baseSize / 2,
    radius: baseSize / 2 - 28,
    ringWidth: 38
  };

  const duration = 900;
  const startTime = performance.now();

  const animate = (timestamp) => {
    const elapsed = Math.min((timestamp - startTime) / duration, 1);
    const eased = easeOutCubic(elapsed);
    drawDashboardPie(ctx, segments, dimensions, eased, total);
    if (elapsed < 1) {
      chartAnimationState.frameId = requestAnimationFrame(animate);
    } else {
      chartAnimationState.frameId = null;
    }
  };

  chartAnimationState.frameId = requestAnimationFrame(animate);
}

function drawDashboardPie(ctx, segments, dimensions, progress, total) {
  const { baseSize, centerX, centerY, radius, ringWidth } = dimensions;
  ctx.clearRect(0, 0, baseSize, baseSize);

  ctx.save();
  const glow = ctx.createRadialGradient(centerX, centerY, radius * 0.1, centerX, centerY, radius + ringWidth);
  glow.addColorStop(0, '#ffffff');
  glow.addColorStop(1, '#dbeafe');
  ctx.fillStyle = glow;
  ctx.globalAlpha = 0.9;
  ctx.beginPath();
  ctx.arc(centerX, centerY, radius + ringWidth / 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  const totalSweep = progress * Math.PI * 2;
  let consumedSweep = 0;
  let startAngle = -Math.PI / 2;

  ctx.lineWidth = ringWidth;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.shadowBlur = 18;
  ctx.shadowColor = 'rgba(15, 23, 42, 0.15)';

  segments.forEach((segment) => {
    const segmentSweep = segment.ratio * Math.PI * 2;
    const drawableSweep = Math.min(segmentSweep, Math.max(totalSweep - consumedSweep, 0));
    if (drawableSweep > 0.0001) {
      ctx.beginPath();
      ctx.strokeStyle = segment.color;
      ctx.arc(centerX, centerY, radius, startAngle, startAngle + drawableSweep);
      ctx.stroke();
    }
    startAngle += segmentSweep;
    consumedSweep += segmentSweep;
  });

  ctx.shadowBlur = 0;

  const innerRadius = radius - ringWidth + 12;
  ctx.beginPath();
  ctx.fillStyle = '#ffffff';
  ctx.arc(centerX, centerY, innerRadius, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = 'rgba(148, 163, 184, 0.35)';
  ctx.lineWidth = 1;
  ctx.stroke();

  ctx.fillStyle = '#0f172a';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = '600 24px "Segoe UI", "Inter", sans-serif';
  ctx.fillText(String(total), centerX, centerY - 6);
  ctx.fillStyle = '#94a3b8';
  ctx.font = '13px "Segoe UI", "Inter", sans-serif';
  ctx.fillText('Total', centerX, centerY + 16);
}

function easeOutCubic(value) {
  return 1 - Math.pow(1 - value, 3);
}

function normalizeCitizenRecord(record) {
  const firstName = String(record?.firstname || '').trim();
  const surname = String(record?.surname || '').trim();
  const fullName = [firstName, surname].filter(Boolean).join(' ').trim();
  const contactNumber = String(record?.contact_number || record?.contactNumber || '').trim();

  return {
    ...record,
    username: record?.username || fullName || record?.name || '',
    name: fullName || record?.name || record?.username || '',
    contact_number: contactNumber,
  };
}

async function listCitizensFromSupabase() {
  console.log('listCitizensFromSupabase called');
  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('citizens')
    .select('id,username,firstname,surname,email,contact_number,created_at')
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Supabase error fetching citizens:', error);
    throw error;
  }
  console.log('Fetched citizens count:', data?.length || 0);
  return (Array.isArray(data) ? data : []).map(normalizeCitizenRecord);
}

// Load citizens (mobile app users)
async function loadPatientData() {
  console.log('loadPatientData called, isApiMode:', isApiMode);
  let list = [];

  if (isDemoMode) {
    list = [];
  } else {
    try {
      if (isApiMode) {
        console.log('Fetching citizens from API...');
        const response = await fetch(`${API_BASE}/api/citizens`, { credentials: 'include' });
        if (response && response.ok) {
          const payload = await response.json();
          list = (Array.isArray(payload) ? payload : []).map(normalizeCitizenRecord);
        } else {
          // Fallback to direct Supabase read when API route is unavailable.
          list = await listCitizensFromSupabase();
        }
      } else {
        list = await listCitizensFromSupabase();
      }
    } catch (error) {
      console.error('Error loading citizens:', error);
      list = [];
    }
  }

  latestPatientsList = Array.isArray(list) ? [...list] : [];

  latestPatientsList.sort((a, b) => {
    const nameA = [a.firstname, a.surname].filter(Boolean).join(' ') || a.username || '';
    const nameB = [b.firstname, b.surname].filter(Boolean).join(' ') || b.username || '';
    return nameA.localeCompare(nameB);
  });

    applyCitizensFinder();
}

// --- Vitals Assessment (QR Scanning & Recording) ---
let html5QrcodeScanner = null;

function initVitalsSection() {
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const statusText = document.getElementById('qr-status');
  const formContainer = document.getElementById('vitals-form-container');
  const vitalsForm = document.getElementById('vitals-form');

  if (!startBtn || !stopBtn) return;

  // Cleanup any previous scanner instance
  if (html5QrcodeScanner) {
    html5QrcodeScanner.clear().catch(console.error);
    html5QrcodeScanner = null;
  }

  startBtn.addEventListener('click', async () => {
    startBtn.classList.add('hidden');
    stopBtn.classList.remove('hidden');
    statusText.textContent = 'Scanning for QR code...';
    formContainer.classList.add('hidden');

    try {
      html5QrcodeScanner = new Html5Qrcode('reader');
      const config = { fps: 10, qrbox: { width: 250, height: 250 } };

      await html5QrcodeScanner.start(
        { facingMode: 'environment' },
        config,
        async (decodedText) => {
          // Success
          statusText.textContent = 'QR Code detected!';
          statusText.style.color = '#15803d';
          
          await stopScanner();
          handleQRDecoded(decodedText);
        },
        (errorMessage) => {
          // Ignore scanning errors as they happen constantly during seek
        }
      );
    } catch (err) {
      console.error('Scanner start error:', err);
      statusText.textContent = 'Error: Camera access denied or not found.';
      statusText.style.color = '#b91c1c';
      startBtn.classList.remove('hidden');
      stopBtn.classList.add('hidden');
    }
  });

  // Add Manual Entry Button
  if (!document.getElementById('manual-entry-btn')) {
    const manualBtn = document.createElement('button');
    manualBtn.id = 'manual-entry-btn';
    manualBtn.className = 'chip-btn';
    manualBtn.textContent = 'Manual Entry';
    manualBtn.style.marginLeft = '10px';
    startBtn.parentNode.appendChild(manualBtn);

    manualBtn.addEventListener('click', () => {
      stopScanner();
      statusText.textContent = 'Manual entry mode enabled.';
      statusText.style.color = '';
      formContainer.classList.remove('hidden');
      vitalsForm.reset();
      document.getElementById('vitals-citizen-id').value = '';
    });
  }

  // Select from Queue logic
  const selectQueueBtn = document.getElementById('vitals-select-queue-btn');
  if (selectQueueBtn) {
    selectQueueBtn.addEventListener('click', () => {
      stopScanner();
      openQueueSelectionModal();
    });
  }

  stopBtn.addEventListener('click', stopScanner);

  async function stopScanner() {
    if (html5QrcodeScanner) {
      try {
        await html5QrcodeScanner.stop();
        await html5QrcodeScanner.clear();
      } catch (e) {
        console.error('Error stopping scanner:', e);
      }
      html5QrcodeScanner = null;
    }
    startBtn.classList.remove('hidden');
    stopBtn.classList.add('hidden');
    statusText.textContent = 'Scanner ready.';
    statusText.style.color = '';
  }

  if (vitalsForm) {
    vitalsForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      await handleVitalsSubmission();
    });
  }

  const resetBtn = document.getElementById('vitals-reset-btn');
  if (resetBtn) {
    resetBtn.addEventListener('click', () => {
      vitalsForm.reset();
      formContainer.classList.add('hidden');
      statusText.textContent = 'Scanner ready.';
    });
  }
}

async function handleQRDecoded(decodedText) {
  const statusText = document.getElementById('qr-status');
  const formContainer = document.getElementById('vitals-form-container');
  const citizenIdInput = document.getElementById('vitals-citizen-id');
  
  const nameInput = document.getElementById('vitals-name');
  const ageInput = document.getElementById('vitals-age');
  const addressInput = document.getElementById('vitals-address');
  const contactInput = document.getElementById('vitals-contact');
  const complaintInput = document.getElementById('vitals-complaint');

  statusText.textContent = 'Processing QR data...';
  
  try {
    const { supabase } = await loadSupabaseModule();

    // Check if it's our new rich data format
    if (decodedText.includes('NAME:') && decodedText.includes('TICKET:')) {
      const data = {};
      decodedText.split('\n').forEach(line => {
        const parts = line.split(': ');
        if (parts.length >= 2) {
          const key = parts[0].trim().toUpperCase();
          const value = parts.slice(1).join(': ').trim();
          data[key] = value;
        }
      });

      nameInput.value = data.NAME || '';
      ageInput.value = data.AGE || '';
      addressInput.value = data.ADDRESS || '';
      contactInput.value = data.CONTACT || '';
      complaintInput.value = data.COMPLAINT || '';

      // Try to resolve citizen ID via ticket
      if (data.TICKET) {
        const { data: ticketData } = await supabase
          .from('queue_tickets')
          .select('citizen_id')
          .eq('ticket_code', data.TICKET)
          .maybeSingle();
        
        if (ticketData) {
          citizenIdInput.value = ticketData.citizen_id;
        }
      }
    } else {
      // Fallback to legacy format (ID or Username)
      statusText.textContent = 'Legacy QR detected. Looking up patient...';
      const { data: citizen, error } = await supabase
        .from('citizens')
        .select('id, username, firstname, surname, age, complete_address, contact_number')
        .or(`username.eq."${decodedText}",id.eq."${decodedText}"`)
        .maybeSingle();

      if (error) throw error;

      if (!citizen) {
        statusText.textContent = 'Patient not found. Invalid QR code.';
        statusText.style.color = '#b91c1c';
        return;
      }

      nameInput.value = `${citizen.firstname} ${citizen.surname}`.trim();
      ageInput.value = citizen.age || '';
      addressInput.value = citizen.complete_address || '';
      contactInput.value = citizen.contact_number || '';
      citizenIdInput.value = citizen.id;
    }

    formContainer.classList.remove('hidden');
    statusText.textContent = 'Patient data loaded successfully.';
    statusText.style.color = '#15803d';
    formContainer.scrollIntoView({ behavior: 'smooth' });
  } catch (err) {
    console.error('QR handle error:', err);
    statusText.textContent = 'Error processing patient data.';
    statusText.style.color = '#b91c1c';
  }
}

let currentSelectionQueue = [];

async function openQueueSelectionModal() {
  const modal = document.getElementById('queue-selection-modal');
  const closeBtn = document.getElementById('queue-selection-close');
  const cancelBtn = document.getElementById('queue-selection-cancel');
  const refreshBtn = document.getElementById('queue-selection-refresh');
  const searchInput = document.getElementById('queue-selection-search');

  modal.classList.remove('hidden');

  if (searchInput) {
    searchInput.value = '';
    searchInput.oninput = () => renderQueueSelectionList(searchInput.value.toLowerCase());
  }

  const closeModal = () => modal.classList.add('hidden');
  closeBtn.onclick = closeModal;
  cancelBtn.onclick = closeModal;
  refreshBtn.onclick = loadQueueForSelection;

  loadQueueForSelection();
}

async function loadQueueForSelection() {
  const listContainer = document.getElementById('queue-selection-list');
  listContainer.innerHTML = '<p class="note" style="text-align: center; padding: 20px;">Fetching active queue...</p>';

  try {
    const { supabase } = await loadSupabaseModule();
    // Get today's tickets in waiting or on_call status
    const { data: tickets, error } = await supabase
      .from('queue_tickets')
      .select(`
        id, 
        queue_number, 
        service_label, 
        status, 
        reason, 
        symptoms,
        citizen_id,
        citizens (
          firstname, 
          surname, 
          age, 
          complete_address, 
          contact_number
        )
      `)
      .eq('queue_date', new Date().toISOString().split('T')[0])
      .in('status', ['waiting', 'on_call'])
      .order('queue_number', { ascending: true });

    if (error) throw error;

    currentSelectionQueue = tickets || [];
    renderQueueSelectionList();
  } catch (err) {
    console.error('Error loading queue for selection:', err);
    listContainer.innerHTML = '<p class="note" style="text-align: center; padding: 20px; color: #ef4444;">Failed to load queue.</p>';
  }
}

function renderQueueSelectionList(query = '') {
  const listContainer = document.getElementById('queue-selection-list');
  if (!listContainer) return;

  const filtered = currentSelectionQueue.filter(t => {
    if (!query) return true;
    const citizen = t.citizens || {};
    const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.toLowerCase();
    const service = (t.service_label || '').toLowerCase();
    return fullName.includes(query) || service.includes(query);
  });

  if (filtered.length === 0) {
    listContainer.innerHTML = `
      <div class="empty-queue-state">
        <span class="empty-queue-icon">📋</span>
        <p class="empty-queue-text">${query ? 'No matching patients or services found.' : 'No patients currently in the queue for today.'}</p>
      </div>
    `;
    return;
  }

  listContainer.innerHTML = '';
  filtered.forEach(t => {
    const citizen = t.citizens || {};
    const fullName = `${citizen.firstname || 'Unknown'} ${citizen.surname || 'Patient'}`.trim();
    
    const item = document.createElement('div');
    item.className = 'queue-item';
    item.innerHTML = `
      <div class="queue-item-info">
        <strong class="queue-item-name">#${String(t.queue_number).padStart(3, '0')} — ${fullName}</strong>
        <div class="queue-item-meta">
          <span class="queue-item-badge badge-${t.status}">${t.status.replace('_', ' ').toUpperCase()}</span>
          <span>${t.service_label}</span>
        </div>
      </div>
      <button class="chip-btn" style="background: #3b82f6; color: #fff; border: none; padding: 6px 12px; font-weight: 600;">Select</button>
    `;

    item.onclick = () => {
      populateVitalsFormFromQueue(t);
      document.getElementById('queue-selection-modal').classList.add('hidden');
    };

    listContainer.appendChild(item);
  });
}

function populateVitalsFormFromQueue(ticket) {
  const formContainer = document.getElementById('vitals-form-container');
  const statusText = document.getElementById('qr-status');
  const vitalsForm = document.getElementById('vitals-form');
  
  const nameInput = document.getElementById('vitals-name');
  const ageInput = document.getElementById('vitals-age');
  const addressInput = document.getElementById('vitals-address');
  const contactInput = document.getElementById('vitals-contact');
  const complaintInput = document.getElementById('vitals-complaint');
  const citizenIdInput = document.getElementById('vitals-citizen-id');

  vitalsForm.reset();

  const citizen = ticket.citizens;
  nameInput.value = `${citizen.firstname} ${citizen.surname}`.trim();
  ageInput.value = citizen.age || '';
  addressInput.value = citizen.complete_address || '';
  contactInput.value = citizen.contact_number || '';
  citizenIdInput.value = ticket.citizen_id;
  complaintInput.value = `${ticket.reason}${ticket.symptoms ? ': ' + ticket.symptoms : ''}`;

  formContainer.classList.remove('hidden');
    const waitTime = (index * 15);
    const timeLabel = waitTime === 0 ? 'Next' : `~${waitTime}m`;

    card.innerHTML = `
      <div class="ticket-header">
        <span class="ticket-id">#${String(ticket.queue_number).padStart(3, '0')}</span>
        <span class="ticket-wait">${timeLabel}</span>
      </div>
atient: #${String(ticket.queue_number).padStart(3, '0')}`;
  statusText.style.color = '#3b82f6';
  formContainer.scrollIntoView({ behavior: 'smooth' });
}

async function handleVitalsSubmission() {
  const submitBtn = document.getElementById('vitals-submit-btn');
  const citizenId = document.getElementById('vitals-citizen-id').value;
  const name = document.getElementById('vitals-name').value;
  const complaint = document.getElementById('vitals-complaint').value;
  const bp = document.getElementById('vitals-bp').value;
  const rr = document.getElementById('vitals-rr').value;
  const temp = document.getElementById('vitals-temp').value;
  const spo2 = document.getElementById('vitals-spo2').value;
  const meds = document.getElementById('vitals-meds').value;

  if (!complaint || (!citizenId && !name)) {
    showToast('Patient name and chief complaint are required.', 'error');
    return;
  }

  setLoading(submitBtn, true);

  try {
    const user = await ensureAuthenticatedSession();
    const { supabase } = await loadSupabaseModule();

    let finalCitizenId = citizenId;

    // If no citizenId (manual entry), try to find or create citizen
    if (!finalCitizenId && name) {
      // Simple lookup by name
      const { data: existing } = await supabase
        .from('citizens')
        .select('id')
        .eq('firstname', name.split(' ')[0] || '')
        .eq('surname', name.split(' ').slice(1).join(' ') || '')
        .maybeSingle();
      
      if (existing) {
        finalCitizenId = existing.id;
      } else {
        // Create a walk-in record
        const { data: created, error: createError } = await supabase
          .from('citizens')
          .insert([{
            firstname: name.split(' ')[0] || 'Unknown',
            surname: name.split(' ').slice(1).join(' ') || 'Patient',
            contact_number: document.getElementById('vitals-contact').value || null,
            complete_address: document.getElementById('vitals-address').value || null,
            age: parseInt(document.getElementById('vitals-age').value) || null,
            email: `walkin_${Date.now()}@ukonek.local` // Temporary email for walk-ins
          }])
          .select()
          .single();
        
        if (createError) throw createError;
        finalCitizenId = created.id;
      }
    }

    if (!finalCitizenId) {
      throw new Error('Could not identify or create patient record.');
    }

    const hr = document.getElementById('vitals-hr')?.value;

    const payload = {
      citizen_id: finalCitizenId,
      nurse_id: user?.id || null,
      chief_complaint: complaint,
      blood_pressure: bp || null,
      heart_rate: hr ? parseInt(hr) : null,
      respiratory_rate: rr ? parseInt(rr) : null,
      temperature: temp ? parseFloat(temp) : null,
      oxygen_saturation: spo2 ? parseInt(spo2) : null,
      current_medications: meds || null
    };

    const { error } = await supabase
      .from('vital_signs')
      .insert([payload]);

    if (error) throw error;

    showToast('Vital signs recorded successfully.', 'success');
    document.getElementById('vitals-form').reset();
    document.getElementById('vitals-form-container').classList.add('hidden');
    document.getElementById('qr-status').textContent = 'Scanner ready.';
    document.getElementById('qr-status').style.color = '';
  } catch (err) {
    console.error('Vitals submission error:', err);
    showToast('Failed to record vital signs. Please check database table.', 'error');
  } finally {
    setLoading(submitBtn, false);
  }
}

async function listStaffFromSupabase() {
  const { supabase } = await loadSupabaseModule();

  const rpcResult = await supabase.rpc('list_staff_accounts');
  if (!rpcResult.error) {
    return Array.isArray(rpcResult.data) ? rpcResult.data : [];
  }

  const staffService = await loadStaffServiceModule();
  const staff = await staffService.listStaff();
  return Array.isArray(staff) ? staff : [];
}

async function loadStaffData() {
  let staffList = [];

  if (isDemoMode) {
    staffList = DEMO_REGISTERED_USERS;
  } else {
    try {
      if (isApiMode) {
        const response = await fetch(`${API_BASE}/api/staff`, { credentials: 'include' });
        if (response.ok) {
          const payload = await response.json();
          staffList = Array.isArray(payload) ? payload : [];
        }

        // Keep admin/staff views working even when API is unavailable or returns empty.
        if (!response.ok || staffList.length === 0) {
          staffList = await listStaffFromSupabase();
        }
      } else {
        staffList = await listStaffFromSupabase();
      }
    } catch (error) {
      console.error('Error loading staff:', error);
      try {
        staffList = await listStaffFromSupabase();
      } catch (_) {
        staffList = DEMO_REGISTERED_USERS;
      }
    }
  }

  latestStaffList = Array.isArray(staffList) ? [...staffList] : [];

  const accountsTbody = document.getElementById('accounts-tbody');
  if (accountsTbody) {
    accountsTbody.innerHTML = '';
    if (latestStaffList.length === 0) {
      accountsTbody.innerHTML = '<tr><td class="table-cell" colspan="4">No registered staff accounts found.</td></tr>';
    } else {
      latestStaffList.forEach(user => {
        const identifier = user.username || user.employee_id || makeDemoId();
        storedAccounts.set(identifier, user);

        const roleValue = user.role ? String(user.role) : '';
        const roleLabel = roleValue ? roleValue.charAt(0).toUpperCase() + roleValue.slice(1) : '—';
        const statusValue = getStaffPresenceStatus(user);
        const statusClass = getStaffPresenceBadgeClass(user);

        const row = document.createElement('tr');
        row.className = 'account-row';
        row.setAttribute('data-role', roleValue ? roleValue.toLowerCase() : '');
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">${user.username || '—'}</td>
          <td class="table-cell">${user.employee_id || '—'}</td>
          <td class="table-cell">${roleLabel}</td>
          <td class="table-cell"><span class="${statusClass}">${statusValue}</span></td>
        `;
        accountsTbody.appendChild(row);
        attachAccountRowListener(row);
      });
    }

    applyStaffFinder();
  }

  renderDashboardInsights();
}

// Initial load (after auth check)
let diagnosisChart = null;
let consultsChart = null;

async function renderClinicalStats() {
  const { supabase } = await loadSupabaseModule();
  
  // 1. Fetch Data
  const { data: consults } = await supabase.from('consultations').select('diagnosis, consulted_at');
  const { data: vitals } = await supabase.from('vital_signs').select('temperature, blood_pressure');

  if (!consults || !vitals) return;

  // 2. Aggregate Top Diagnoses
  const diagMap = {};
  consults.forEach(c => {
    const d = (c.diagnosis || 'Unknown').trim();
    diagMap[d] = (diagMap[d] || 0) + 1;
  });
  const sortedDiags = Object.entries(diagMap).sort((a,b) => b[1] - a[1]).slice(0, 5);

  // 3. Aggregate Daily Consults (Last 7 days)
  const dailyMap = {};
  const last7Days = [...Array(7)].map((_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - i);
    return d.toISOString().split('T')[0];
  }).reverse();

  last7Days.forEach(day => dailyMap[day] = 0);
  consults.forEach(c => {
    const day = c.consulted_at.split('T')[0];
    if (dailyMap.hasOwnProperty(day)) dailyMap[day]++;
  });

  // 4. Vitals Metrics
  const temps = vitals.map(v => v.temperature).filter(t => t > 0);
  const avgTemp = temps.length ? (temps.reduce((a,b) => a+b, 0) / temps.length).toFixed(1) : '—';
  
  let hypertensionCount = 0;
  vitals.forEach(v => {
    if (v.blood_pressure) {
      const parts = v.blood_pressure.split('/');
      if (parts.length === 2) {
        const sys = parseInt(parts[0]);
        const dia = parseInt(parts[1]);
        if (sys >= 140 || dia >= 90) hypertensionCount++;
      }
    }
  });

  document.getElementById('avg-temp').textContent = temps.length ? `${avgTemp}°C` : '—';
  document.getElementById('hypertension-count').textContent = hypertensionCount;

  // 5. Render Charts
  const ctxDiag = document.getElementById('diagnoses-chart');
  if (ctxDiag) {
    if (diagnosisChart) diagnosisChart.destroy();
    diagnosisChart = new Chart(ctxDiag, {
      type: 'doughnut',
      data: {
        labels: sortedDiags.map(d => d[0]),
        datasets: [{
          data: sortedDiags.map(d => d[1]),
          backgroundColor: ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6']
        }]
      },
      options: { responsive: true, plugins: { legend: { position: 'bottom' } } }
    });
  }

  const ctxCons = document.getElementById('consults-chart');
  if (ctxCons) {
    if (consultsChart) consultsChart.destroy();
    consultsChart = new Chart(ctxCons, {
      type: 'line',
      data: {
        labels: last7Days.map(d => d.split('-').slice(1).join('/')),
        datasets: [{
          label: 'Consultations',
          data: last7Days.map(d => dailyMap[d]),
          borderColor: '#3b82f6',
          tension: 0.3,
          fill: true,
          backgroundColor: 'rgba(59, 130, 246, 0.1)'
        }]
      },
      options: { responsive: true, scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } } }
    });
  }
}

async function initDashboardData() {
  try {
    const sessionUser = await ensureAuthenticatedSession();
    if (!sessionUser) return;

    // Pharmacists have a dedicated dashboard — redirect if they land here
    const sessionRole = String(sessionUser?.role || '').trim().toLowerCase();
    if (sessionRole === 'pharmacist') {
      window.location.replace('./dashboard-pharmacist.html');
      return;
    }

    startPresenceHeartbeat();
    applyRoleAccess(sessionUser);

    // Parallelize non-dependent data loads
    await Promise.all([
      loadPatientData().catch(e => console.error('Patient data failed:', e)),
      loadStaffData().catch(e => console.error('Staff data failed:', e))
    ]);

    if (!isAdminUser(sessionUser)) {
      stopAdminDashboardAutoRefresh();
      renderDashboardInsights();
      return;
    }

    startAdminDashboardAutoRefresh();
    renderDashboardInsights();
  } catch (error) {
    console.error('Dashboard data initialization failed:', error);
    showToast('Some data could not be loaded. Please refresh.', 'error');
  } finally {
    dismissPagePreloader();
  }
}

window.addEventListener('pagehide', () => {
  handleAutoLogoutOnClose();
});

window.addEventListener('beforeunload', () => {
  handleAutoLogoutOnClose();
});

if (dashRefreshBtn) {
  dashRefreshBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
    showToast('Dashboard data refreshed.', 'info');
  });
}

if (refreshAccountsBtn) {
  refreshAccountsBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
    showToast('Account tables refreshed.', 'info');
  });
}

if (staffRegisterBtn) {
  staffRegisterBtn.addEventListener('click', () => {
    navigateToSection('users-section', { pane: 'registration-pane' });
  });
}

// Utility validation functions
function validateEmail(email) {
  return /.+@.+\..+/.test(email);
}

// Modal state
let currentAccountData = null;
let currentAction = null; // 'edit' or 'delete'
let isAccountEditMode = false;

const modalViewFields = document.getElementById('modal-view-fields');
const modalEditForm = document.getElementById('modal-edit-form');
const modalEditActions = document.getElementById('modal-edit-actions');
const modalEditError = document.getElementById('modal-edit-error');

const modalEditFirstName = document.getElementById('modal-edit-first-name');
const modalEditMiddleName = document.getElementById('modal-edit-middle-name');
const modalEditLastName = document.getElementById('modal-edit-last-name');
const modalEditUsername = document.getElementById('modal-edit-username');
const modalEditEmail = document.getElementById('modal-edit-email');
const modalEditEmployeeId = document.getElementById('modal-edit-employee-id');
const modalEditRole = document.getElementById('modal-edit-role');
const modalEditBirthday = document.getElementById('modal-edit-birthday');

function normalizeDateInput(value) {
  if (!value) return '';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '';
  return parsed.toISOString().slice(0, 10);
}

function setModalEditError(message = '') {
  if (!modalEditError) return;
  const text = String(message || '').trim();
  modalEditError.textContent = text;
  modalEditError.classList.toggle('hidden', !text);
}

function setAccountEditMode(editMode) {
  isAccountEditMode = Boolean(editMode);
  if (modalViewFields) modalViewFields.classList.toggle('hidden', isAccountEditMode);
  if (modalEditForm) modalEditForm.classList.toggle('hidden', !isAccountEditMode);

  const modalActions = document.getElementById('modal-actions');
  if (modalActions) modalActions.classList.toggle('hidden', isAccountEditMode);
  if (modalEditActions) modalEditActions.classList.toggle('hidden', !isAccountEditMode);
  setModalEditError('');
}

function fillAccountEditForm(user) {
  if (!user) return;
  if (modalEditFirstName) modalEditFirstName.value = String(user.first_name || '').trim();
  if (modalEditMiddleName) modalEditMiddleName.value = String(user.middle_name || '').trim();
  if (modalEditLastName) modalEditLastName.value = String(user.last_name || '').trim();
  if (modalEditUsername) modalEditUsername.value = String(user.username || '').trim();
  if (modalEditEmail) modalEditEmail.value = String(user.email || '').trim();
  if (modalEditEmployeeId) modalEditEmployeeId.value = String(user.employee_id || '').trim();
  if (modalEditRole) {
    let roleValue = String(user.role || 'nurse').trim().toLowerCase();
    if (roleValue === 'staff') roleValue = 'nurse';
    const allowed = ['admin', 'doctor', 'nurse', 'pharmacist'];
    modalEditRole.value = allowed.includes(roleValue) ? roleValue : 'nurse';
  }
  if (modalEditBirthday) modalEditBirthday.value = normalizeDateInput(user.birthday);
}

function closeAccountModal() {
  const modal = document.getElementById('account-modal');
  if (modal) {
    modal.classList.add('hidden');
    modal.style.display = '';
  }
  currentAccountData = null;
  currentAction = null;
  setAccountEditMode(false);
}

async function updateStaffAccountById(staffId, payload) {
  if (isDemoMode) {
    const idx = DEMO_REGISTERED_USERS.findIndex((item) => String(item.id || '') === String(staffId));
    if (idx >= 0) {
      DEMO_REGISTERED_USERS[idx] = { ...DEMO_REGISTERED_USERS[idx], ...payload };
    }
    return DEMO_REGISTERED_USERS[idx] || null;
  }

  if (isApiMode) {
    const requestBody = JSON.stringify({ ...payload });
    let response = await fetch(`${API_BASE}/api/staff/${staffId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: requestBody
    });

    if (response.status === 404 || response.status === 405) {
      response = await fetch(`${API_BASE}/api/staff/${staffId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: requestBody
      });
    }

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(data.message || 'Failed to update account.');
    }
    return data;
  }

  const staffService = await loadStaffServiceModule();
  return staffService.updateStaffById(staffId, payload);
}

async function resetStaffPasswordById(staffId, newPassword) {
  const normalizedPassword = String(newPassword || '');
  if (normalizedPassword.length < 8) {
    throw new Error('Password must be at least 8 characters.');
  }

  if (isApiMode) {
    const endpoints = [
      `${API_BASE}/api/staff/${staffId}/reset-password`,
      `${API_BASE}/api/staff/reset-password`
    ];

    let lastError = null;
    for (const endpoint of endpoints) {
      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ staffId, password: normalizedPassword })
        });

        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
          throw new Error(data.message || `Request failed (${response.status})`);
        }

        return data;
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError || new Error('Unable to reset password in API mode.');
  }

  const staffService = await loadStaffServiceModule();
  return staffService.resetStaffPassword(staffId, normalizedPassword);
}

function openAccountModal(user) {
  if (!user) return;
  const modal = document.getElementById('account-modal');
  if (!modal) return;

  currentAccountData = { ...user };
  setAccountEditMode(false);
  fillAccountEditForm(user);

  const firstName = String(user.first_name || '').trim();
  const lastName = String(user.last_name || '').trim();
  const fullName = `${firstName} ${lastName}`.replace(/\s+/g, ' ').trim();
  const birthdayValue = user.birthday ? new Date(user.birthday) : null;
  const birthdayText = birthdayValue && !Number.isNaN(birthdayValue.getTime())
    ? birthdayValue.toLocaleDateString()
    : '—';

  const modalName = document.getElementById('modal-name');
  const modalEmail = document.getElementById('modal-email');
  const modalRole = document.getElementById('modal-role');
  const modalStatus = document.getElementById('modal-status');
  const modalContact = document.getElementById('modal-contact');
  const modalBday = document.getElementById('modal-bday');
  const confirmSection = document.getElementById('modal-confirm-section');
  const modalActions = document.getElementById('modal-actions');

  if (modalName) modalName.textContent = fullName || user.username || '—';
  if (modalEmail) modalEmail.textContent = user.email || '—';
  if (modalRole) {
    const roleLabel = user.role ? user.role.charAt(0).toUpperCase() + user.role.slice(1) : '—';
    modalRole.textContent = roleLabel;
  }
  if (modalStatus) modalStatus.textContent = getStaffPresenceStatus(user);
  if (modalContact) modalContact.textContent = user.employee_id || '—';
  if (modalBday) modalBday.textContent = birthdayText;

  ['address'].forEach(field => {
    const el = document.getElementById(`modal-${field}`);
    if (el) el.textContent = user[field] || '—';
  });

  if (confirmSection) confirmSection.style.display = 'none';
  if (modalActions) modalActions.style.display = 'flex';

  modal.classList.remove('hidden');
  modal.style.display = 'flex';
}

// Account row click handler -> shared detail modal
function attachAccountRowListener(row) {
  if (!dataDetailModal) {
    row.addEventListener('click', () => {
      const identifier = row.getAttribute('data-id');
      const user = storedAccounts.get(identifier);
      if (!user) return;
      openAccountModal(user);
    });
    return;
  }

  attachDetailRow(row, () => {
    const identifier = row.getAttribute('data-id');
    const user = storedAccounts.get(identifier);
    if (!user) return null;

    const firstName = String(user.first_name || '').trim();
    const lastName = String(user.last_name || '').trim();
    const fullName = `${firstName} ${lastName}`.replace(/\s+/g, ' ').trim();
    const statusValue = getStaffPresenceStatus(user);
    const roleLabel = user.role ? user.role.charAt(0).toUpperCase() + user.role.slice(1) : '—';

    const actions = document.getElementById('account-modal') ? [
      {
        label: 'Manage Account',
        className: 'btn',
        onClick: () => {
          closeDataDetail();
          openAccountModal(user);
        }
      }
    ] : [];

    return {
      tag: 'Staff Account',
      title: fullName || user.username || 'Staff Account',
      subtitle: user.email || '',
      items: [
        { label: 'Username', value: user.username || '—' },
        { label: 'Employee ID', value: user.employee_id || '—' },
        { label: 'Role', value: roleLabel },
        { label: 'Status', value: statusValue },
        { label: 'Email', value: user.email || '—' },
        { label: 'Birthday', value: user.birthday ? new Date(user.birthday) : '—' }
      ],
      actions
    };
  });
}

// Attach listeners to existing account rows
document.querySelectorAll('.account-row').forEach(attachAccountRowListener);

// Staff/Citizens are now handled as separate panes via users menu items.
// Modal close button
const closeModalBtn = document.getElementById('modal-close-btn');
if (closeModalBtn) {
  closeModalBtn.addEventListener('click', () => {
    closeAccountModal();
  });
}

// Edit button
const editBtn = document.getElementById('modal-edit-btn');
if (editBtn) {
  editBtn.addEventListener('click', () => {
    if (!currentAccountData) return;
    setAccountEditMode(true);
  });
}

// Delete button
const deleteBtn = document.getElementById('modal-delete-btn');
if (deleteBtn) {
  deleteBtn.addEventListener('click', () => {
    currentAction = 'delete';
    document.getElementById('modal-confirm-text').textContent = 'Are you sure you want to delete this account? This action cannot be undone.';
    document.getElementById('modal-actions').style.display = 'none';
    document.getElementById('modal-confirm-section').style.display = 'block';
  });
}

const resetPasswordBtn = document.getElementById('modal-reset-password-btn');
if (resetPasswordBtn) {
  resetPasswordBtn.addEventListener('click', async () => {
    if (!currentAccountData || !currentAccountData.id) {
      showToast('Unable to reset password: missing account id.', 'error');
      return;
    }

    const passwordDialog = await openDialogModal({
      title: 'Reset Password',
      message: 'Enter and confirm the new password (minimum 8 characters).',
      confirmText: 'Reset Password',
      cancelText: 'Cancel',
      inputs: [
        {
          label: 'New Password',
          type: 'password',
          placeholder: 'Minimum 8 characters'
        },
        {
          label: 'Confirm Password',
          type: 'password',
          placeholder: 'Re-enter new password'
        }
      ]
    });
    if (!passwordDialog.confirmed) return;

    const newPassword = String(passwordDialog.values?.[0] || '');
    const confirmPassword = String(passwordDialog.values?.[1] || '');

    if (newPassword !== confirmPassword) {
      showToast('Passwords do not match.', 'error');
      return;
    }

    try {
      resetPasswordBtn.disabled = true;
      await resetStaffPasswordById(currentAccountData.id, newPassword);
      showToast('Password reset successfully.', 'success');
    } catch (error) {
      console.error('Reset password error:', error);
      showToast(error?.message || 'Unable to reset password.', 'error');
    } finally {
      resetPasswordBtn.disabled = false;
    }
  });
}

// Confirm button
const confirmBtn = document.getElementById('modal-confirm-btn');
if (confirmBtn) {
  confirmBtn.addEventListener('click', async () => {
    if (currentAction === 'delete') {
      try {
        if (!currentAccountData || !currentAccountData.id) {
          showToast('Unable to delete: missing account id.', 'error');
          return;
        }

        if (isApiMode) {
          const response = await fetch(`${API_BASE}/api/staff/${currentAccountData.id}`, {
            method: 'DELETE',
            credentials: 'include'
          });

          const data = await response.json().catch(() => ({}));
          if (!response.ok) {
            showToast(data.message || 'Failed to delete account.', 'error');
            return;
          }
        } else {
          const staffService = await loadStaffServiceModule();
          await staffService.deleteStaffAccount(currentAccountData.id);
        }

        closeAccountModal();
        document.getElementById('modal-confirm-section').style.display = 'none';
        document.getElementById('modal-actions').style.display = 'flex';

        await loadStaffData();
        showToast('Account deleted successfully.', 'success');
      } catch (error) {
        console.error('Delete account error:', error);
        showToast('Server error during deletion.', 'error');
      }
    }
  });
}

// Cancel button
const cancelBtn = document.getElementById('modal-cancel-btn');
if (cancelBtn) {
  cancelBtn.addEventListener('click', () => {
    document.getElementById('modal-confirm-section').style.display = 'none';
    document.getElementById('modal-actions').style.display = 'flex';
    currentAction = null;
  });
}

const modalSaveBtn = document.getElementById('modal-save-btn');
if (modalSaveBtn) {
  modalSaveBtn.addEventListener('click', async (event) => {
    event.preventDefault();
    if (!currentAccountData || !currentAccountData.id) {
      setModalEditError('Missing account id.');
      return;
    }

    const username = String(modalEditUsername?.value || '').trim();
    const email = String(modalEditEmail?.value || '').trim().toLowerCase();
    const role = String(modalEditRole?.value || '').trim().toLowerCase();
    const firstName = String(modalEditFirstName?.value || '').trim();
    const lastName = String(modalEditLastName?.value || '').trim();

    if (!username) {
      setModalEditError('Username is required.');
      return;
    }

    if (!firstName || !lastName) {
      setModalEditError('First name and last name are required.');
      return;
    }

    if (!validateEmail(email)) {
      setModalEditError('Please enter a valid email address.');
      return;
    }

    if (!role) {
      setModalEditError('Role is required.');
      return;
    }

    const payload = {
      first_name: firstName,
      middle_name: String(modalEditMiddleName?.value || '').trim() || null,
      last_name: lastName,
      username,
      email,
      employee_id: String(modalEditEmployeeId?.value || '').trim() || null,
      role,
      birthday: String(modalEditBirthday?.value || '').trim() || null
    };

    try {
      modalSaveBtn.disabled = true;
      await updateStaffAccountById(currentAccountData.id, payload);
      showToast('Account updated successfully.', 'success');
      closeAccountModal();
      storedAccounts.clear();
      await loadStaffData();
    } catch (error) {
      console.error('Update account error:', error);
      setModalEditError(error?.message || 'Failed to update account.');
    } finally {
      modalSaveBtn.disabled = false;
    }
  });
}

const modalCancelEditBtn = document.getElementById('modal-cancel-edit-btn');
if (modalCancelEditBtn) {
  modalCancelEditBtn.addEventListener('click', (event) => {
    event.preventDefault();
    setAccountEditMode(false);
    fillAccountEditForm(currentAccountData);
  });
}

// --- Clickable stats to navigate to panes ---
const statAnnouncementsCard = document.getElementById('stat-announcements-card');
const statReportsCard = document.getElementById('stat-reports-card');
const statPatientsCard = document.getElementById('stat-citizens-card');

if (statAnnouncementsCard) {
  statAnnouncementsCard.addEventListener('click', () => {
    hideAllSections();
    if (reportsSection) reportsSection.classList.remove('hidden');
    if (tabAnnouncements) tabAnnouncements.click();
  });
}

if (statReportsCard) {
  statReportsCard.addEventListener('click', () => {
    hideAllSections();
    if (reportsSection) reportsSection.classList.remove('hidden');
    if (tabFeedback) tabFeedback.click();
  });
}

if (statPatientsCard) {
  statPatientsCard.addEventListener('click', async () => {
    navigateToSection('users-section', { pane: 'citizens-pane' });
    await loadPatientData();
  });
}

// --- Consultations, Prescriptions, Medicines (localStorage-backed demo) ---
const consultationSection = document.getElementById('consultation-section');
const consultationForm = document.getElementById('consultation-form');
const consultationsTbody = document.getElementById('consultations-tbody');
const consultSaveBtn = document.getElementById('consult-save-btn');
const consultReportBtn = document.getElementById('consult-report-btn');
const openConsultModalBtn = document.getElementById('open-consult-modal-btn');
const consultationModal = document.getElementById('consultation-modal');
const consultationCancelBtn = document.getElementById('consultation-cancel-btn');

const prescriptionModal = document.getElementById('prescription-modal');
const prescriptionForm = document.getElementById('prescription-form');
const prescriptionPatient = document.getElementById('prescription-patient');
const prescriptionLines = document.getElementById('prescription-lines');
const addPrescriptionLineBtn = document.getElementById('add-prescription-line');
const cancelPrescriptionBtn = document.getElementById('cancel-prescription');

const medicineSection = document.getElementById('medicine-section');
const medicineForm = document.getElementById('medicine-form');
const medicineTbody = document.getElementById('medicine-tbody');
const medicineReportBtn = document.getElementById('medicine-report-btn');
const medicineArchivedToggleBtn = document.getElementById('medicine-archived-toggle-btn');
const medicineArchivedPanel = document.getElementById('medicine-archived-panel');
const medicineArchivedTbody = document.getElementById('medicine-archived-tbody');
const medicineSearchInput = document.getElementById('medicine-search-input');

function openConsultationModal(prefill = {}) {
  if (!consultationModal) return;
  if (consultationForm) consultationForm.reset();

  // Reset tab to History
  consultationModal.querySelectorAll('.modal-tab').forEach(t => t.classList.remove('active'));
  consultationModal.querySelector('.modal-tab[data-tab="tab-history"]')?.classList.add('active');
  consultationModal.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  consultationModal.querySelector('#tab-history')?.classList.add('active');

  const patientInput = document.getElementById('consult-patient-id');
  const displayId = document.getElementById('consult-display-id');
  if (patientInput && prefill.patientId) patientInput.value = prefill.patientId;

  // Show patient name + service in modal header
  if (displayId) {
    const namePart = prefill.patientName ? `<strong>${prefill.patientName}</strong>` : '';
    const idPart = prefill.patientId ? `<span style="color:#64748b">(${prefill.patientId})</span>` : '—';
    const servicePart = prefill.serviceLabel ? ` &mdash; <em>${prefill.serviceLabel}</em>` : '';
    displayId.innerHTML = `${namePart} ${idPart}${servicePart}`.trim();
  }

  // Store queue ticket id on form for later use
  if (consultationForm) {
    consultationForm.dataset.queueTicketId = prefill.queueTicketId ? String(prefill.queueTicketId) : '';
    consultationForm.dataset.patientName = prefill.patientName || '';
  }

  // Pre-fill HPI from symptoms/reason
  const hpiInput = document.getElementById('consult-hpi');
  if (hpiInput && prefill.symptoms) hpiInput.value = prefill.symptoms;

  const notesInput = document.getElementById('consult-notes');
  if (notesInput && prefill.notes) notesInput.value = prefill.notes;

  // Hide vitals banner initially, then fetch if ticket linked
  const vitalsBanner = document.getElementById('consult-vitals-banner');
  if (vitalsBanner) vitalsBanner.style.display = 'none';
  if (prefill.queueTicketId) {
    loadVitalsForConsultation(Number(prefill.queueTicketId));
  }

  initConsultationTabs();
  consultationModal.classList.remove('hidden');
}

async function loadVitalsForConsultation(queueTicketId) {
  if (!queueTicketId) return;
  try {
    const { supabase } = await loadSupabaseModule();
    const { data, error } = await supabase.rpc('get_vitals_for_ticket', {
      p_queue_ticket_id: queueTicketId
    });
    if (error || !data) return;

    const banner      = document.getElementById('consult-vitals-banner');
    const grid        = document.getElementById('consult-vitals-grid');
    const complaintEl = document.getElementById('consult-vitals-complaint');
    const notesEl     = document.getElementById('consult-vitals-notes');
    if (!banner || !grid) return;

    const vitals = [
      { label: 'BP',   value: data.blood_pressure       ? `${data.blood_pressure} mmHg` : null },
      { label: 'HR',   value: data.heart_rate            ? `${data.heart_rate} bpm`       : null },
      { label: 'Temp', value: data.temperature           ? `${data.temperature} °C`       : null },
      { label: 'RR',   value: data.respiratory_rate      ? `${data.respiratory_rate} bpm` : null },
      { label: 'SpO₂', value: data.oxygen_saturation     ? `${data.oxygen_saturation}%`   : null },
    ].filter(v => v.value);

    if (vitals.length === 0 && !data.chief_complaint) return;

    grid.innerHTML = vitals.map(v => `
      <div style="background:#fff; border:1px solid #bbf7d0; border-radius:8px; padding:8px 10px; text-align:center;">
        <div style="font-size:11px; color:#6b7280; margin-bottom:2px;">${v.label}</div>
        <div style="font-size:14px; font-weight:700; color:#0f172a;">${v.value}</div>
      </div>
    `).join('');

    if (complaintEl) {
      complaintEl.innerHTML = data.chief_complaint
        ? `<strong>Chief Complaint:</strong> ${data.chief_complaint}`
        : '';
    }
    if (notesEl) {
      const nurseName = data.nurse_name ? ` (${data.nurse_name})` : '';
      notesEl.innerHTML = data.notes
        ? `<strong>Nurse Notes${nurseName}:</strong> ${data.notes}`
        : (nurseName ? `<span style="color:#6b7280;">Assessed by${nurseName}</span>` : '');
      if (data.current_medications) {
        notesEl.innerHTML += `<br><strong>Current Meds:</strong> ${data.current_medications}`;
      }
    }

    // Pre-fill HPI with chief complaint if HPI is empty
    const hpiInput = document.getElementById('consult-hpi');
    if (hpiInput && !hpiInput.value && data.chief_complaint) {
      hpiInput.value = data.chief_complaint;
    }

    banner.style.display = 'block';
  } catch (_) {
    // Non-critical — vitals banner just stays hidden
  }
}

function closeConsultationModal() {
  if (!consultationModal) return;
  consultationModal.classList.add('hidden');
  if (consultationForm) consultationForm.reset();
}

if (openConsultModalBtn) {
  openConsultModalBtn.addEventListener('click', () => {
    if (!canConsultPatients()) {
      showToast('Only doctors can create consultations.', 'warning');
      return;
    }
    const servingPatients = consultationQueueTickets.filter(t => t.rowType === 'queue-serving');
    if (servingPatients.length === 0) {
      showToast('No patients are currently being served. Move a patient to \'Now Serving\' in the Queue first.', 'warning');
      return;
    }
    if (servingPatients.length === 1) {
      openConsultationModal({
        patientId: servingPatients[0].patientId || '',
        patientName: servingPatients[0].patientName || '',
        serviceLabel: servingPatients[0].serviceLabel || '',
        queueTicketId: servingPatients[0].queueTicketId || null,
        symptoms: servingPatients[0].symptoms || '',
        notes: servingPatients[0].notes || ''
      });
    } else {
      showToast('Multiple patients are being served. Use the Consult button on the specific patient row.', 'info');
    }
  });
}

if (consultationCancelBtn) {
  consultationCancelBtn.addEventListener('click', () => closeConsultationModal());
}

if (consultationModal) {
  consultationModal.addEventListener('click', (event) => {
    if (event.target === consultationModal) closeConsultationModal();
  });
}

let consultations = [];
let consultationQueueTickets = [];
let medicines = [];
let filteredMedicines = [];
let archivedMedicines = [];
let prescriptions = [];
let isArchivedMedicinesVisible = false;

function loadFromStorage(key) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : [];
  } catch (err) {
    console.error('Storage parse error', key, err);
    return [];
  }
}

function saveToStorage(key, data) {
  try { localStorage.setItem(key, JSON.stringify(data)); } catch (err) { console.error('Storage save error', key, err); }
}

/**
 * Marks a queue ticket as completed in the database and updates local state.
 */
async function completeQueueTicket(qId) {
  if (!qId || isDemoMode || isApiMode) return;
  
  try {
    const { supabase } = await loadSupabaseModule();
    const { error: completeErr } = await supabase
      .from('queue_tickets')
      .update({ status: 'completed', completed_at: new Date().toISOString() })
      .eq('id', Number(qId));
    
    if (completeErr) {
      console.warn('Failure completing queue ticket:', completeErr);
    }
    
    // Remove locally immediately for better responsiveness
    if (typeof consultationQueueTickets !== 'undefined') {
      consultationQueueTickets = consultationQueueTickets.filter(t => 
        Number(t.queueTicketId || t.id?.replace('Q-','')) !== Number(qId)
      );
      renderServingQueue();
    }

    // Refresh queue and consultations to reflect completion in other areas
    await refreshConsultationData();
    if (typeof appointments !== 'undefined' && appointments.loadQueueTickets) {
      appointments.loadQueueTickets();
    }
  } catch (err) {
    console.error('Error in completeQueueTicket:', err);
  }
}

function renderServingQueue() {
  const tbody = document.getElementById('serving-queue-tbody');
  if (!tbody) return;
  const allowConsult = canConsultPatients();

  // Hard filter to ensure no completed/cancelled tickets ever show up in this active list
  const activeTickets = consultationQueueTickets.filter(c => {
    const status = String(c?.queueStatus || '').trim().toLowerCase();
    return status === 'serving' || status === 'on_call';
  });

  swapContainer(tbody, (fragment) => {
    if (!activeTickets.length) {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td class="table-cell" colspan="5" style="color:#64748b;">No patients currently being served.</td>';
      fragment.appendChild(tr);
      return;
    }
    activeTickets.forEach(c => {
      const displayName = c.patientName || c.patientId || '—';
      const tr = document.createElement('tr');
      tr.style.background = '#f0fdf4';
      tr.innerHTML = `
        <td class="table-cell"><strong>${displayName}</strong><br><span style="font-size:11px;color:#64748b">${c.patientId || ''}</span></td>
        <td class="table-cell">${c.serviceLabel || 'General Consultation'}</td>
        <td class="table-cell"><span style="font-weight:700;color:#0369a1">#${String(c.queueNumber || 0).padStart(3,'0')}</span></td>
        <td class="table-cell">${formatDateTime(c.created_at)}</td>
        <td class="table-cell">
          ${allowConsult
            ? `<button class="btn small" data-action="consult" data-id="${c.id}" style="background:#0369a1;color:#fff;border-color:#0369a1;">Consult</button>`
            : '<span style="color:#94a3b8;font-size:12px">View only</span>'}
        </td>
      `;
      fragment.appendChild(tr);
      attachDetailRow(tr, () => ({
        tag: 'Now Serving',
        title: displayName,
        subtitle: c.serviceLabel || 'General Consultation',
        items: [
          { label: 'Patient Name', value: c.patientName || '—' },
          { label: 'Patient ID', value: c.patientId },
          { label: 'Service', value: c.serviceLabel || '—' },
          { label: 'Queue Number', value: c.queueNumber > 0 ? `#${String(c.queueNumber).padStart(3,'0')}` : '—' },
          { label: 'Symptoms', value: c.symptoms || '—' },
          { label: 'Reason', value: c.notes || '—' },
          { label: 'Since', value: new Date(c.created_at) }
        ]
      }));
    });
  });
}

function renderConsultations() {
  if (!consultationsTbody) return;
  const sortSelect = document.getElementById('consult-sort-select');
  const sortBy = sortSelect ? sortSelect.value : 'date-desc';

  const dateFromInput = document.getElementById('consult-date-from');
  const dateToInput = document.getElementById('consult-date-to');
  const dateFrom = dateFromInput?.value ? new Date(dateFromInput.value + 'T00:00:00') : null;
  const dateTo = dateToInput?.value ? new Date(dateToInput.value + 'T23:59:59') : null;

  const allowPrescribe = canCreatePrescriptions();

  let rows = consultations.slice();

  // Apply date range filter
  if (dateFrom || dateTo) {
    rows = rows.filter(c => {
      const d = new Date(c.created_at);
      if (dateFrom && d < dateFrom) return false;
      if (dateTo && d > dateTo) return false;
      return true;
    });
  }

  if (sortBy === 'date-desc') {
    rows.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  } else if (sortBy === 'date-asc') {
    rows.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  } else if (sortBy === 'name-asc') {
    rows.sort((a, b) => (a.patientName || '').localeCompare(b.patientName || ''));
  }

  swapContainer(consultationsTbody, (fragment) => {
    if (!rows.length) {
      const msg = (dateFrom || dateTo) ? 'No consultations found for the selected date range.' : 'No consultation records yet.';
      const tr = document.createElement('tr');
      tr.innerHTML = `<td class="table-cell" colspan="5" style="color:#64748b;">${msg}</td>`;
      fragment.appendChild(tr);
      return;
    }
    rows.forEach(c => {
      const displayName = c.patientName || c.patientId || '—';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell"><strong>${displayName}</strong></td>
        <td class="table-cell" style="color:#64748b;font-size:13px;">${c.patientId || '—'}</td>
        <td class="table-cell">${(c.diagnosis || '').substring(0, 60)}</td>
        <td class="table-cell">${formatDateTime(c.created_at)}</td>
        <td class="table-cell" style="display:flex;gap:6px;flex-wrap:wrap;">
          <button class="btn small" data-action="view" data-id="${c.id}" style="background:#64748b;color:#fff;border-color:#64748b;">View</button>
          ${allowPrescribe ? `<button class="btn small" data-action="prescribe" data-id="${c.id}" style="background:#16a34a;color:#fff;border-color:#16a34a;">Prescribe</button>` : ''}
        </td>
      `;
      fragment.appendChild(tr);
      attachDetailRow(tr, () => ({
        tag: 'Consultation',
        title: displayName,
        subtitle: c.id,
        items: [
          { label: 'Consultation ID', value: c.id },
          { label: 'Patient Name', value: c.patientName || '—' },
          { label: 'Patient ID', value: c.patientId },
          { label: 'Symptoms', value: c.symptoms || '—' },
          { label: 'Diagnosis', value: c.diagnosis || '—' },
          { label: 'Notes', value: c.notes || '—' },
          { label: 'Recorded', value: new Date(c.created_at) }
        ]
      }));
    });
  });
}

function mapConsultationRow(item) {
  const consultationId = String(item?.id || '').trim();
  return {
    id: consultationId ? `C-${consultationId}` : `C-${Date.now()}`,
    dbId: Number(item?.id) || null,
    rowType: 'consultation',
    patientId: String(item?.patient_identifier || item?.patient_id || '').trim(),
    symptoms: String(item?.symptoms || '').trim(),
    diagnosis: String(item?.diagnosis || '').trim(),
    notes: String(item?.notes || '').trim(),
    patientName: item?.citizen ? `${item.citizen.firstname} ${item.citizen.surname}`.trim() : (item?.patientName || ''),
    created_at: item?.consulted_at || item?.created_at || new Date().toISOString(),
    doctor_staff_id: Number(item?.doctor_staff_id) || null
  };
}

function mapNowServingQueueRow(item) {
  const ticketId = Number(item?.id) || 0;
  const citizenId = Number(item?.citizen?.id || 0);
  const citizenFirstName = String(item?.citizen?.firstname || '').trim();
  const citizenSurname = String(item?.citizen?.surname || '').trim();
  const patientName = (citizenFirstName || citizenSurname)
    ? `${citizenFirstName} ${citizenSurname}`.trim()
    : '';
  const patientId = citizenId > 0
    ? `CIT-${citizenId}`
    : (String(item?.ticket_code || '').trim() || `QUEUE-${ticketId || Date.now()}`);
  const queueNumber = Number(item?.queue_number || 0);
  const serviceLabel = String(item?.service_label || '').trim() || 'General Consultation';
  const status = String(item?.status || '').trim().toLowerCase();

  return {
    id: ticketId > 0 ? `Q-${ticketId}` : `Q-${Date.now()}`,
    dbId: null,
    rowType: 'queue-serving',
    queueTicketId: ticketId > 0 ? ticketId : null,
    patientId,
    patientName,
    symptoms: String(item?.symptoms || '').trim(),
    diagnosis: '',
    notes: String(item?.reason || '').trim(),
    created_at: item?.served_at || item?.created_at || new Date().toISOString(),
    serviceLabel,
    queueNumber,
    queueStatus: status || 'serving'
  };
}

function resolveCitizenIdFromIdentifier(patientIdentifier) {
  const raw = String(patientIdentifier || '').trim();
  if (!raw) return null;

  // Pattern: CIT-123
  const directMatch = /^CIT-(\d+)$/i.exec(raw);
  if (directMatch) {
    const parsed = Number(directMatch[1]);
    return Number.isFinite(parsed) ? parsed : null;
  }

  // Pattern: 123
  const numeric = Number(raw);
  if (Number.isFinite(numeric) && numeric > 0) {
    return numeric;
  }

  // Fallback: Search latestPatientsList for username or name match
  if (typeof latestPatientsList !== 'undefined' && Array.isArray(latestPatientsList)) {
    const query = raw.toLowerCase();
    const citizen = latestPatientsList.find(c => 
      String(c.username || '').toLowerCase() === query || 
      String(c.name || '').toLowerCase() === query ||
      ([c.firstname, c.surname].filter(Boolean).join(' ').toLowerCase() === query)
    );
    if (citizen) return Number(citizen.id);
  }

  return null;
}

async function listConsultationData() {
  if (isDemoMode || isApiMode) {
    const fallback = loadFromStorage('ukonek_consultations');
    return Array.isArray(fallback) ? fallback : [];
  }

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('consultations')
    .select('id,patient_identifier,symptoms,diagnosis,notes,consulted_at,created_at,doctor_staff_id, citizen:citizens(firstname, surname)')
    .order('consulted_at', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load consultations.');
  }

  return (data || []).map(mapConsultationRow);
}

async function listNowServingQueueForConsultation() {
  if (isDemoMode || isApiMode) {
    return [];
  }

  const today = new Date();
  const queueDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

  const { supabase } = await loadSupabaseModule();
  
  const query = supabase
    .from('queue_tickets')
    .select('id,queue_number,ticket_code,service_label,status,reason,symptoms,created_at,served_at,citizen:citizens(id,firstname,surname,email)')
    .eq('status', 'serving')
    .order('queue_number', { ascending: true });

  let { data, error } = await query.eq('queue_date', queueDate);

  // Resilience Fallback: If no "serving" tickets for "today" (local), fetch only RECENT active serving tickets (last 24h).
  if (!error && (!data || data.length === 0)) {
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    console.log('No serving tickets for today, attempting fallback to recent serving tickets (last 24h)...');
    const fb = await supabase
      .from('queue_tickets')
      .select('id,queue_number,ticket_code,service_label,status,reason,symptoms,created_at,served_at,citizen:citizens(id,firstname,surname,email)')
      .eq('status', 'serving')
      .gt('created_at', twentyFourHoursAgo)
      .order('served_at', { ascending: false })
      .limit(50);
    
    if (!fb.error && fb.data && fb.data.length > 0) {
      data = fb.data;
    }
  }

  if (error) {
    throw new Error(error.message || 'Unable to load now serving queue tickets.');
  }

  return (data || []).map(mapNowServingQueueRow);
}

async function refreshConsultationData() {
  try {
    const [consultationRows, queueRows] = await Promise.all([
      listConsultationData().catch(() => []),
      listNowServingQueueForConsultation()
    ]);
    consultations = consultationRows;
    consultationQueueTickets = queueRows;
  } catch (error) {
    console.error('Failed to refresh consultations:', error);
    consultations = [];
    consultationQueueTickets = [];
  }
  renderServingQueue();
  renderConsultations();
}

function initConsultationTabs() {
  const tabs = document.querySelectorAll('.modal-tab');
  const nextBtn = document.getElementById('consult-next-btn');
  const prevBtn = document.getElementById('consult-prev-btn');
  const submitBtn = document.getElementById('consult-submit-btn');
  
  const updateButtons = (activeTabId) => {
    if (!nextBtn || !prevBtn || !submitBtn) return;
    
    if (activeTabId === 'tab-history') {
      prevBtn.classList.add('hidden');
      nextBtn.classList.remove('hidden');
      submitBtn.classList.add('hidden');
    } else if (activeTabId === 'tab-exam') {
      prevBtn.classList.remove('hidden');
      nextBtn.classList.remove('hidden');
      submitBtn.classList.add('hidden');
    } else if (activeTabId === 'tab-diagnosis') {
      prevBtn.classList.remove('hidden');
      nextBtn.classList.add('hidden');
      submitBtn.classList.remove('hidden');
    }
  };

  tabs.forEach(tab => {
    tab.addEventListener('click', (e) => {
      e.preventDefault();
      const targetId = tab.dataset.tab;
      
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      
      document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
      });
      document.getElementById(targetId)?.classList.add('active');
      
      updateButtons(targetId);
    });
  });

  if (nextBtn) {
    nextBtn.onclick = () => {
      const activeTab = document.querySelector('.modal-tab.active');
      if (activeTab?.dataset.tab === 'tab-history') {
        document.querySelector('[data-tab="tab-exam"]')?.click();
      } else if (activeTab?.dataset.tab === 'tab-exam') {
        document.querySelector('[data-tab="tab-diagnosis"]')?.click();
      }
    };
  }

  if (prevBtn) {
    prevBtn.onclick = () => {
      const activeTab = document.querySelector('.modal-tab.active');
      if (activeTab?.dataset.tab === 'tab-exam') {
        document.querySelector('[data-tab="tab-history"]')?.click();
      } else if (activeTab?.dataset.tab === 'tab-diagnosis') {
        document.querySelector('[data-tab="tab-exam"]')?.click();
      }
    };
  }
  
  // Initial button state
  updateButtons('tab-history');

  const allergyInput = document.getElementById('consult-allergies');
  const allergyBanner = document.getElementById('allergy-alert-banner');
  const allergySummary = document.getElementById('allergy-summary');

  if (allergyInput && allergyBanner && allergySummary) {
    allergyInput.addEventListener('input', () => {
      const val = allergyInput.value.trim();
      if (val) {
        allergyBanner.style.background = '#fff1f2';
        allergyBanner.style.borderColor = '#fecdd3';
        allergyBanner.style.color = '#9f1239';
        allergySummary.textContent = `CRITICAL: ${val}`;
      } else {
        allergyBanner.style.background = '#f8fafc';
        allergyBanner.style.borderColor = '#e2e8f0';
        allergyBanner.style.color = '#64748b';
        allergySummary.textContent = 'No known drug allergies reported yet.';
      }
    });
  }
}

// Global consultation form handler (saves and then opens prescription)
if (consultationForm) {
  consultationForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!canConsultPatients()) {
      showToast('Only doctors can create consultations.', 'warning');
      return;
    }
    
    const submitBtn = document.getElementById('consult-submit-btn');
    const patientId = document.getElementById('consult-patient-id')?.value || '';
    const patientName = consultationForm.dataset.patientName || '';
    const diagnosis = document.getElementById('consult-diagnosis')?.value || '';
    
    if (!diagnosis) {
      showToast('Diagnosis is required.', 'warning');
      // Jump to diagnosis tab if not there
      document.querySelector('[data-tab="tab-diagnosis"]')?.click();
      return;
    }

    try {
      setLoading(submitBtn, true);
      const payload = {
        patientId,
        queueTicketId: consultationForm.dataset.queueTicketId || null,
        symptoms: document.getElementById('consult-hpi')?.value || '',
        diagnosis,
        notes: document.getElementById('consult-notes')?.value || '',
        hpi: document.getElementById('consult-hpi')?.value || '',
        pmh: document.getElementById('consult-pmh')?.value || '',
        allergies: document.getElementById('consult-allergies')?.value || '',
        immunization: document.getElementById('consult-immunization')?.value || '',
        social: document.getElementById('consult-social')?.value || '',
        physical_exam: {
          heent: document.getElementById('consult-heent')?.value || '',
          chest: document.getElementById('consult-chest')?.value || '',
          heart: document.getElementById('consult-heart')?.value || '',
          abdomen: document.getElementById('consult-abdomen')?.value || '',
          extremities: document.getElementById('consult-extremities')?.value || '',
          neurological: document.getElementById('consult-neurological')?.value || ''
        },
        differential: document.getElementById('consult-differential')?.value || '',
        lab_orders: document.getElementById('consult-lab-orders')?.value || '',
        followup: document.getElementById('consult-followup')?.value || null
      };

      const result = await createConsultationEntry(payload);
      if (result && !result.patientName) result.patientName = patientName;
      
      showToast('Consultation saved successfully.', 'success');
      closeConsultationModal();
      await refreshConsultationData();
      
      // Automatically complete queue ticket
      if (payload.queueTicketId) {
        completeQueueTicket(payload.queueTicketId);
      }
      
      // Auto-open prescription modal for the next step, pass queueTicketId
      openPrescriptionModalForPatient(result.patientId, result.dbId, result.patientName, payload.queueTicketId);
      
    } catch (error) {
      console.error('Failed to save consultation:', error);
      showToast(error.message || 'Unable to save consultation.', 'error');
    } finally {
      setLoading(submitBtn, false);
    }
  });
}

async function createConsultationEntry(payload) {
  if (isDemoMode || isApiMode) {
    const entry = {
      id: `C-${Date.now()}`,
      patientId: payload.patientId,
      symptoms: payload.symptoms || '',
      diagnosis: payload.diagnosis,
      notes: payload.notes || '',
      hpi: payload.hpi,
      pmh: payload.pmh,
      allergies: payload.allergies,
      immunization_status: payload.immunization,
      social_history: payload.social,
      physical_exam: payload.physical_exam,
      differential_diagnosis: payload.differential,
      lab_orders: payload.lab_orders,
      follow_up_date: payload.followup,
      created_at: new Date().toISOString()
    };
    consultations.push(entry);
    saveToStorage('ukonek_consultations', consultations);
    return entry;
  }

  const doctorStaffId = Number(cachedSessionUser?.id) || null;
  if (!doctorStaffId) {
    throw new Error('Unable to resolve the logged-in doctor account.');
  }

  const dbPayload = {
    patient_identifier: String(payload.patientId || '').trim(),
    patient_citizen_id: resolveCitizenIdFromIdentifier(payload.patientId),
    doctor_staff_id: doctorStaffId,
    symptoms: String(payload.symptoms || '').trim() || null,
    diagnosis: String(payload.diagnosis || '').trim(),
    notes: String(payload.notes || '').trim() || null,
    hpi: String(payload.hpi || '').trim() || null,
    pmh: String(payload.pmh || '').trim() || null,
    allergies: String(payload.allergies || '').trim() || null,
    immunization_status: String(payload.immunization || '').trim() || null,
    social_history: String(payload.social || '').trim() || null,
    physical_exam: payload.physical_exam || {},
    differential_diagnosis: String(payload.differential || '').trim() || null,
    lab_orders: String(payload.lab_orders || '').trim() || null,
    follow_up_date: payload.followup || null,
    consulted_at: new Date().toISOString()
  };

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('consultations')
    .insert(dbPayload)
    .select('*')
    .single();

  if (error) {
    throw new Error(error.message || 'Unable to save consultation.');
  }

  // Create Lab Orders if specified
  if (payload.lab_orders) {
    const tests = payload.lab_orders.split(',').map(t => t.trim()).filter(t => t);
    if (tests.length > 0) {
      const orderRows = tests.map(test => ({
        consultation_id: data.id,
        patient_citizen_id: dbPayload.patient_citizen_id,
        doctor_staff_id: doctorStaffId,
        test_name: test,
        status: 'Pending'
      }));
      await supabase.from('lab_orders').insert(orderRows);
    }
  }

  return mapConsultationRow(data);
}

async function initLabSection() {
  const tbody = document.getElementById('lab-orders-tbody');
  if (!tbody) return;

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('lab_orders')
    .select('*, doctor:staff(firstname, surname), patient:citizens(firstname, surname)')
    .order('created_at', { ascending: false });

  if (error) {
    tbody.innerHTML = '<tr><td colspan="6" class="table-cell">Error loading orders.</td></tr>';
    return;
  }

  tbody.innerHTML = '';
  if (data.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="table-cell">No lab orders found.</td></tr>';
    return;
  }

  data.forEach(order => {
    const tr = document.createElement('tr');
    tr.className = 'account-row';
    const drName = order.doctor ? `Dr. ${order.doctor.first_name} ${order.doctor.last_name}` : '—';
    const ptName = order.patient ? `${order.patient.firstname} ${order.patient.surname}` : '—';
    const statusClass = order.status === 'Completed' ? 'badge success' : 'badge warning';
    
    tr.innerHTML = `
      <td class="table-cell">${ptName}</td>
      <td class="table-cell"><strong>${order.test_name}</strong></td>
      <td class="table-cell">${drName}</td>
      <td class="table-cell"><span class="${statusClass}">${order.status}</span></td>
      <td class="table-cell">${new Date(order.created_at).toLocaleDateString()}</td>
      <td class="table-cell">
        ${order.status === 'Pending' ? `<button class="btn small" onclick="updateLabOrderStatus('${order.id}', 'Completed')">Mark Done</button>` : '—'}
      </td>
    `;
    tbody.appendChild(tr);
  });
}

window.updateLabOrderStatus = async function(orderId, status) {
  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('lab_orders')
    .update({ status, completed_at: new Date().toISOString() })
    .eq('id', orderId);

  if (error) {
    showToast('Failed to update lab order.', 'error');
  } else {
    showToast('Lab order updated.', 'success');
    initLabSection();
  }
}

async function createPrescriptionEntry({ patientId, consultationDbId, items }) {
  const cleanPatientId = String(patientId || '').trim();
  if (!cleanPatientId) {
    throw new Error('Patient ID required.');
  }

  const normalizedItems = Array.isArray(items)
    ? items
        .map((it) => ({
          name: String(it?.name || '').trim(),
          qty: Number(it?.qty) || 0,
          unit: String(it?.unit || '').trim(),
          dosage: String(it?.dosage || '').trim(),
          frequency: String(it?.frequency || '').trim(),
          duration: String(it?.duration || '').trim(),
          instructions: String(it?.instructions || '').trim(),
          additionalInfo: String(it?.additionalInfo || '').trim()
        }))
        .filter((it) => it.name && it.qty > 0)
    : [];

  if (!normalizedItems.length) {
    throw new Error('Add at least one medicine.');
  }

  if (isDemoMode || isApiMode) {
    const pres = {
      id: `P-${Date.now()}`,
      patient: cleanPatientId,
      items: normalizedItems,
      created_at: new Date().toISOString()
    };
    prescriptions.push(pres);
    saveToStorage('ukonek_prescriptions', prescriptions);
    return pres;
  }

  const doctorStaffId = Number(cachedSessionUser?.id) || null;
  if (!doctorStaffId) {
    throw new Error('Unable to resolve the logged-in doctor account.');
  }

  const { supabase } = await loadSupabaseModule();
  const headerPayload = {
    consultation_id: Number.isFinite(Number(consultationDbId)) ? Number(consultationDbId) : null,
    patient_identifier: cleanPatientId,
    doctor_staff_id: doctorStaffId,
    issued_at: new Date().toISOString()
  };

  const { data: header, error: headerError } = await supabase
    .from('prescription_headers')
    .insert(headerPayload)
    .select('id')
    .single();

  if (headerError) {
    throw new Error(headerError.message || 'Unable to create prescription header.');
  }

  const headerId = Number(header?.id) || null;
  if (!headerId) {
    throw new Error('Invalid prescription header ID.');
  }

  const itemRows = normalizedItems.map((it) => ({
    prescription_id: headerId,
    medicine_name: it.name,
    quantity: it.qty,
    unit: it.unit || null,
    dosage: it.dosage || null,
    frequency: it.frequency || null,
    duration: it.duration || null,
    instructions: it.instructions || null,
    additional_info: it.additionalInfo || null
  }));

  const { error: itemsError } = await supabase
    .from('prescription_items')
    .insert(itemRows);

  if (itemsError) {
    throw new Error(itemsError.message || 'Unable to save prescription items.');
  }

  return { id: `P-${headerId}`, patient: cleanPatientId, items: normalizedItems };
}

function renderMedicines() {
  if (!medicineTbody) return;

  // Update searchable datalist for prescriptions
  const medicineList = document.getElementById('medicine-list');
  if (medicineList) {
    medicineList.innerHTML = medicines.map(m => `<option value="${m.name}">${m.name} (${m.unit || ''})</option>`).join('');
  }

  const searchQuery = (medicineSearchInput?.value || '').toLowerCase().trim();
  const sortSelect = document.getElementById('medicine-sort-select');
  const sortBy = sortSelect ? sortSelect.value : 'name-asc';

  let filtered = medicines.filter(m => 
    m.name.toLowerCase().includes(searchQuery) || 
    (m.description || '').toLowerCase().includes(searchQuery)
  );

  // Apply Sorting
  if (sortBy === 'name-asc') {
    filtered.sort((a, b) => a.name.localeCompare(b.name));
  } else if (sortBy === 'name-desc') {
    filtered.sort((a, b) => b.name.localeCompare(a.name));
  } else if (sortBy === 'expiry-asc') {
    filtered.sort((a, b) => {
      const dateA = a.expiry_date ? new Date(a.expiry_date).getTime() : Infinity;
      const dateB = b.expiry_date ? new Date(b.expiry_date).getTime() : Infinity;
      return dateA - dateB;
    });
  } else if (sortBy === 'expiry-desc') {
    filtered.sort((a, b) => {
      const dateA = a.expiry_date ? new Date(a.expiry_date).getTime() : -1;
      const dateB = b.expiry_date ? new Date(b.expiry_date).getTime() : -1;
      return dateB - dateA;
    });
  } else if (sortBy === 'stock-desc') {
    filtered.sort((a, b) => (b.qty || 0) - (a.qty || 0));
  } else if (sortBy === 'stock-asc') {
    filtered.sort((a, b) => (a.qty || 0) - (b.qty || 0));
  }

  filteredMedicines = filtered;

  const role = getSessionRole();
  const allowAdjust = canAdjustMedicineInventory(role);
  const allowAddNew = canAddNewMedicine(role);
  const allowRemove = canAddNewMedicine(role);
  // Doctors and nurses see a simplified read-only view — no expiry date, no actions column
  const showExpiryAndActions = allowAdjust || allowAddNew || !['doctor','nurse'].includes((role || '').toLowerCase());

  // Toggle header cells
  const thExpiry = document.getElementById('medicine-th-expiry');
  const thActions = document.getElementById('medicine-th-actions');
  if (thExpiry) thExpiry.style.display = showExpiryAndActions ? '' : 'none';
  if (thActions) thActions.style.display = showExpiryAndActions ? '' : 'none';

  const colCount = showExpiryAndActions ? 7 : 5;

  const medicineFormEl = document.getElementById('medicine-form');
  if (medicineFormEl) {
    const formPanel = medicineFormEl.closest('.panel');
    if (formPanel) formPanel.classList.toggle('hidden', !allowAddNew);
    medicineFormEl.querySelectorAll('input, select, textarea, button').forEach((el) => {
      el.disabled = !allowAddNew;
    });
  }

  swapContainer(medicineTbody, (fragment) => {
    if (!Array.isArray(filtered) || filtered.length === 0) {
      const msg = searchQuery ? 'No medicines match your search.' : 'No medicine inventory yet.';
      const tr = document.createElement('tr');
      tr.innerHTML = `<td class="table-cell" colspan="${colCount}">${msg}</td>`;
      fragment.appendChild(tr);
      return;
    }
    filtered.forEach(m => {
      const tr = document.createElement('tr');

      // Status logic
      const isLowStock = m.qty <= 5 && m.qty > 0;
      const isOutOfStock = m.qty <= 0;
      const isExpired = m.expiry_date && new Date(m.expiry_date) < new Date();

      let statusHtml = '<span class="badge badge-success">In Stock</span>';
      if (isExpired) statusHtml = '<span class="badge badge-error">Expired</span>';
      else if (isOutOfStock) statusHtml = '<span class="badge badge-error">Out of Stock</span>';
      else if (isLowStock) statusHtml = '<span class="badge badge-warning">Low Stock</span>';

      const expiryText = m.expiry_date ? new Date(m.expiry_date).toLocaleDateString() : '—';
      const descriptionText = m.description || '—';

      tr.innerHTML = `
        <td class="table-cell"><strong>${m.name}</strong></td>
        <td class="table-cell">${descriptionText}</td>
        <td class="table-cell">${m.qty}</td>
        <td class="table-cell">${m.unit || ''}</td>
        ${showExpiryAndActions ? `<td class="table-cell">${expiryText}</td>` : ''}
        <td class="table-cell">${statusHtml}</td>
        ${showExpiryAndActions ? `<td class="table-cell"></td>` : ''}
      `;

      if (showExpiryAndActions) {
        const actionsTd = tr.querySelector('td:last-child');
        if (allowAdjust) {
          const addBtn = document.createElement('button');
          addBtn.className = 'btn small';
          addBtn.dataset.action = 'add';
          addBtn.dataset.name = m.name;
          addBtn.textContent = '+ Add';

          const subBtn = document.createElement('button');
          subBtn.className = 'btn small outline';
          subBtn.dataset.action = 'sub';
          subBtn.dataset.name = m.name;
          subBtn.textContent = '- Subtract';

          actionsTd.appendChild(addBtn);
          actionsTd.appendChild(subBtn);
          if (allowRemove) {
            const removeBtn = document.createElement('button');
            removeBtn.className = 'btn small outline';
            removeBtn.dataset.action = 'remove';
            removeBtn.dataset.name = m.name;
            removeBtn.textContent = 'Remove';
            actionsTd.appendChild(removeBtn);
          }
        } else {
          actionsTd.textContent = '—';
        }
      }

      fragment.appendChild(tr);
      attachDetailRow(tr, () => ({
        tag: 'Inventory',
        title: m.name,
        subtitle: 'Medicine Stock Detail',
        items: [
          { label: 'Name', value: m.name },
          { label: 'Quantity', value: m.qty },
          { label: 'Unit', value: m.unit || '—' }
        ]
      }));
    });
  });
}

function mapMedicineRow(item) {
  return {
    id: Number(item?.id) || null,
    name: String(item?.name || '').trim(),
    qty: Math.max(0, Number(item?.qty) || 0),
    unit: String(item?.unit || '').trim(),
    archived_at: item?.archived_at || null,
    created_at: item?.created_at || null,
    updated_at: item?.updated_at || null
  };
}

async function listMedicineData() {
  if (isDemoMode || isApiMode) {
    return [];
  }

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('medicines')
    .select('id,name,qty,unit,archived_at,created_at,updated_at')
    .is('archived_at', null)
    .order('name', { ascending: true });

  if (error) {
    throw new Error(error.message || 'Unable to load medicines.');
  }

  return (data || []).map(mapMedicineRow);
}

async function listArchivedMedicineData() {
  if (isDemoMode || isApiMode) {
    return [];
  }

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('medicines')
    .select('id,name,qty,unit,archived_at,created_at,updated_at')
    .not('archived_at', 'is', null)
    .order('archived_at', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load archived medicines.');
  }

  return (data || []).map(mapMedicineRow);
}

function renderArchivedMedicines() {
  if (!medicineArchivedPanel || !medicineArchivedTbody || !medicineArchivedToggleBtn) return;

  medicineArchivedPanel.classList.toggle('hidden', !isArchivedMedicinesVisible);
  medicineArchivedToggleBtn.textContent = isArchivedMedicinesVisible ? 'Hide Archived' : 'Show Archived';

  if (!isArchivedMedicinesVisible) {
    return;
  }

  const canRestore = canAddNewMedicine(getSessionRole());
  const canHardDelete = isAdminUser(cachedSessionUser);

  swapContainer(medicineArchivedTbody, (fragment) => {
    if (!Array.isArray(archivedMedicines) || archivedMedicines.length === 0) {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td class="table-cell" colspan="5">No archived medicines.</td>';
      fragment.appendChild(tr);
      return;
    }
    archivedMedicines.forEach((m) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell">${m.name}</td>
        <td class="table-cell">${m.qty}</td>
        <td class="table-cell">${m.unit || ''}</td>
        <td class="table-cell">${formatDateTime(m.archived_at)}</td>
        <td class="table-cell"></td>
      `;

      const actionCell = tr.querySelector('td:last-child');
      if (canRestore) {
        const restoreBtn = document.createElement('button');
        restoreBtn.className = 'btn small';
        restoreBtn.dataset.action = 'restore';
        restoreBtn.dataset.id = String(m.id || '');
        restoreBtn.textContent = 'Restore';
        actionCell.appendChild(restoreBtn);
      }
      if (canHardDelete) {
        const deleteBtn = document.createElement('button');
        deleteBtn.className = 'btn small outline';
        deleteBtn.dataset.action = 'hard-delete';
        deleteBtn.dataset.id = String(m.id || '');
        deleteBtn.textContent = 'Delete Permanently';
        actionCell.appendChild(deleteBtn);
      }
      if (!canRestore && !canHardDelete) {
        actionCell.textContent = 'View only';
      }

      fragment.appendChild(tr);
    });
  });
}

async function refreshArchivedMedicineData() {
  try {
    archivedMedicines = await listArchivedMedicineData();
  } catch (error) {
    console.error('Failed to refresh archived medicines:', error);
    archivedMedicines = [];
  }
  renderArchivedMedicines();
}

async function refreshMedicineData() {
  try {
    medicines = await listMedicineData();
  } catch (error) {
    console.error('Failed to refresh medicines:', error);
    medicines = [];
  }
  renderMedicines();
}

async function upsertMedicineEntry({ name, qty, unit }) {
  const cleanName = String(name || '').trim();
  const cleanUnit = String(unit || '').trim();
  const quantity = Math.max(0, Number(qty) || 0);
  if (!cleanName) {
    throw new Error('Medicine name required.');
  }

  if (isDemoMode || isApiMode) {
    const idx = medicines.findIndex((m) => String(m.name || '').toLowerCase() === cleanName.toLowerCase());
    if (idx >= 0) {
      medicines[idx].qty = Number(medicines[idx].qty) + quantity;
      medicines[idx].unit = cleanUnit || medicines[idx].unit;
    } else {
      medicines.push({ id: null, name: cleanName, qty: quantity, unit: cleanUnit });
    }
    return;
  }

  const { supabase } = await loadSupabaseModule();
  const existing = medicines.find((m) => String(m.name || '').toLowerCase() === cleanName.toLowerCase()) || null;

  if (existing?.id) {
    const payload = {
      qty: Math.max(0, Number(existing.qty || 0) + quantity),
      unit: cleanUnit || existing.unit || null
    };
    const { error } = await supabase
      .from('medicines')
      .update(payload)
      .eq('id', Number(existing.id));
    if (error) {
      throw new Error(error.message || 'Unable to update medicine.');
    }
    return;
  }

  const payload = {
    name: cleanName,
    qty: quantity,
    unit: cleanUnit || null,
    created_by_staff_id: Number(cachedSessionUser?.id) || null
  };
  const { error } = await supabase.from('medicines').insert(payload);
  if (error) {
    throw new Error(error.message || 'Unable to add medicine.');
  }
}

async function adjustMedicineQuantityByName(name, delta) {
  const target = medicines.find((m) => String(m.name || '') === String(name || ''));
  if (!target?.id) return;

  const nextQty = Math.max(0, Number(target.qty || 0) + Number(delta || 0));

  if (isDemoMode || isApiMode) {
    target.qty = nextQty;
    return;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('medicines')
    .update({ qty: nextQty })
    .eq('id', Number(target.id));

  if (error) {
    throw new Error(error.message || 'Unable to update medicine quantity.');
  }
}

async function addMedicineStockByName(name, amount) {
  const qty = Number(amount) || 0;
  if (qty <= 0) {
    throw new Error('Add quantity must be greater than zero.');
  }
  await adjustMedicineQuantityByName(name, qty);
}

async function reduceMedicineStockByName(name, amount) {
  const qty = Number(amount) || 0;
  if (qty <= 0) {
    throw new Error('Subtract quantity must be greater than zero.');
  }
  await adjustMedicineQuantityByName(name, -qty);
}

async function removeMedicineEntryByName(name) {
  const target = medicines.find((m) => String(m.name || '') === String(name || ''));
  if (!target) return;

  if (isDemoMode || isApiMode) {
    medicines = medicines.filter((m) => String(m.name || '') !== String(name || ''));
    return;
  }

  if (!target.id) {
    return;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('medicines')
    .update({ archived_at: new Date().toISOString() })
    .eq('id', Number(target.id));

  if (error) {
    throw new Error(error.message || 'Unable to archive medicine.');
  }
}

async function restoreMedicineEntryById(id) {
  const targetId = Number(id);
  if (!targetId) return;

  if (isDemoMode || isApiMode) {
    const target = archivedMedicines.find((m) => Number(m.id) === targetId);
    if (!target) return;
    archivedMedicines = archivedMedicines.filter((m) => Number(m.id) !== targetId);
    medicines.push({ ...target, archived_at: null });
    return;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('medicines')
    .update({ archived_at: null })
    .eq('id', targetId);

  if (error) {
    throw new Error(error.message || 'Unable to restore medicine.');
  }
}

async function permanentlyDeleteArchivedMedicineById(id) {
  const targetId = Number(id);
  if (!targetId) return;

  if (isDemoMode || isApiMode) {
    archivedMedicines = archivedMedicines.filter((m) => Number(m.id) !== targetId);
    return;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('medicines')
    .delete()
    .eq('id', targetId)
    .not('archived_at', 'is', null);

  if (error) {
    throw new Error(error.message || 'Unable to permanently delete medicine.');
  }
}

function getClinicalMigrationStorageKey() {
  const userId = Number(cachedSessionUser?.id) || 0;
  return `ukonek_clinical_migrated_v1_${userId}`;
}

function parseIsoOrNow(value) {
  const parsed = new Date(String(value || '').trim());
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString();
  }
  return parsed.toISOString();
}

async function migrateLegacyClinicalStorageIfNeeded() {
  if (isDemoMode || isApiMode) return;

  const doctorStaffId = Number(cachedSessionUser?.id) || 0;
  if (!doctorStaffId || !canConsultPatients()) return;

  const migrationKey = getClinicalMigrationStorageKey();
  try {
    const rawMigrationState = localStorage.getItem(migrationKey);
    if (rawMigrationState) {
      const parsedState = JSON.parse(rawMigrationState);
      if (parsedState && parsedState.hadFailure === false) {
        return;
      }
    }
  } catch (_) {
    // Ignore parse issues and attempt migration again.
  }

  const legacyConsultations = loadFromStorage('ukonek_consultations');
  const legacyPrescriptions = loadFromStorage('ukonek_prescriptions');
  const consultList = Array.isArray(legacyConsultations) ? legacyConsultations : [];
  const prescriptionList = Array.isArray(legacyPrescriptions) ? legacyPrescriptions : [];

  const { supabase } = await loadSupabaseModule();
  let hadFailure = false;

  // Dedupe against existing records for this doctor to avoid duplicate migrations.
  const { data: existingConsultations } = await supabase
    .from('consultations')
    .select('patient_identifier,diagnosis,consulted_at,doctor_staff_id')
    .eq('doctor_staff_id', doctorStaffId);
  const existingConsultationSet = new Set(
    (existingConsultations || []).map((row) => {
      const patientIdentifier = String(row?.patient_identifier || '').trim();
      const diagnosis = String(row?.diagnosis || '').trim().toLowerCase();
      const consultedAt = parseIsoOrNow(row?.consulted_at);
      return `${patientIdentifier}::${diagnosis}::${consultedAt}`;
    })
  );

  for (const entry of consultList) {
    const patientIdentifier = String(entry?.patientId || '').trim();
    const diagnosis = String(entry?.diagnosis || '').trim();
    if (!patientIdentifier || !diagnosis) continue;

    const consultedAt = parseIsoOrNow(entry?.created_at);
    const dedupeKey = `${patientIdentifier}::${diagnosis.toLowerCase()}::${consultedAt}`;
    if (existingConsultationSet.has(dedupeKey)) continue;

    const payload = {
      patient_identifier: patientIdentifier,
      patient_citizen_id: resolveCitizenIdFromIdentifier(patientIdentifier),
      doctor_staff_id: doctorStaffId,
      symptoms: String(entry?.symptoms || '').trim() || null,
      diagnosis,
      notes: String(entry?.notes || '').trim() || null,
      consulted_at: consultedAt
    };

    const { error } = await supabase.from('consultations').insert(payload);
    if (error) {
      hadFailure = true;
      console.error('Legacy consultation migration failed:', error);
      continue;
    }

    existingConsultationSet.add(dedupeKey);
  }

  for (const entry of prescriptionList) {
    const patientIdentifier = String(entry?.patient || entry?.patientId || '').trim();
    const items = Array.isArray(entry?.items) ? entry.items : [];
    if (!patientIdentifier || !items.length) continue;

    const issuedAt = parseIsoOrNow(entry?.created_at);
    const { data: header, error: headerError } = await supabase
      .from('prescription_headers')
      .insert({
        consultation_id: null,
        patient_identifier: patientIdentifier,
        doctor_staff_id: doctorStaffId,
        issued_at: issuedAt
      })
      .select('id')
      .single();

    if (headerError) {
      hadFailure = true;
      console.error('Legacy prescription header migration failed:', headerError);
      continue;
    }

    const prescriptionId = Number(header?.id) || 0;
    if (!prescriptionId) {
      hadFailure = true;
      continue;
    }

    const itemRows = items
      .map((it) => ({
        prescription_id: prescriptionId,
        medicine_name: String(it?.name || '').trim(),
        quantity: Number(it?.qty) || 0,
        unit: String(it?.unit || '').trim() || null
      }))
      .filter((it) => it.medicine_name && it.quantity > 0);

    if (!itemRows.length) continue;

    const { error: itemsError } = await supabase
      .from('prescription_items')
      .insert(itemRows);

    if (itemsError) {
      hadFailure = true;
      console.error('Legacy prescription item migration failed:', itemsError);
    }
  }

  if (!hadFailure) {
    localStorage.removeItem('ukonek_consultations');
    localStorage.removeItem('ukonek_prescriptions');
  }

  localStorage.setItem(
    migrationKey,
    JSON.stringify({
      completedAt: new Date().toISOString(),
      hadFailure
    })
  );
}

async function initClinicalData() {
  await ensureAuthenticatedSession().catch(() => null);
  await migrateLegacyClinicalStorageIfNeeded();
  await refreshConsultationData();
  renderServingQueue();
  renderConsultations();

  await Promise.all([refreshMedicineData(), refreshArchivedMedicineData()]);

  if (isDemoMode || isApiMode) {
    prescriptions = loadFromStorage('ukonek_prescriptions') || [];
  } else {
    prescriptions = [];
  }
  renderServingQueue();
  renderConsultations();
}

// ...

// Consultation table sort handler
const consultSortSelect = document.getElementById('consult-sort-select');
if (consultSortSelect) {
  consultSortSelect.addEventListener('change', () => {
    renderConsultations();
  });
}

// Consultation date range filter handlers
const consultDateFrom = document.getElementById('consult-date-from');
const consultDateTo = document.getElementById('consult-date-to');
const consultDateClear = document.getElementById('consult-date-clear');

if (consultDateFrom) consultDateFrom.addEventListener('change', () => renderConsultations());
if (consultDateTo) consultDateTo.addEventListener('change', () => renderConsultations());
if (consultDateClear) {
  consultDateClear.addEventListener('click', () => {
    if (consultDateFrom) consultDateFrom.value = '';
    if (consultDateTo) consultDateTo.value = '';
    renderConsultations();
  });
}

const medicineSortSelect = document.getElementById('medicine-sort-select');
if (medicineSortSelect) {
  medicineSortSelect.addEventListener('change', () => {
    renderMedicines();
  });
}

if (consultationsTbody) {
  consultationsTbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (!btn) return;
    const action = btn.getAttribute('data-action');
    const id = btn.getAttribute('data-id');
    const entry = [...consultationQueueTickets, ...consultations].find(c => c.id === id);
    if (!action || !entry) return;
    if (action === 'consult') {
      if (!canConsultPatients()) {
        showToast('Only doctors can create consultations.', 'warning');
        return;
      }
      openConsultationModal({
        patientId: entry.patientId || '',
        patientName: entry.patientName || '',
        serviceLabel: entry.serviceLabel || '',
        queueTicketId: entry.queueTicketId || null,
        symptoms: entry.symptoms || '',
        notes: entry.notes || ''
      });
    } else if (action === 'view') {
      openDataDetail({
        tag: 'Consultation',
        title: entry.patientName || entry.patientId || 'Consultation Detail',
        subtitle: entry.id,
        items: [
          { label: 'Consultation ID', value: entry.id },
          { label: 'Patient ID', value: entry.patientId },
          { label: 'Symptoms', value: entry.symptoms || '—' },
          { label: 'Diagnosis', value: entry.diagnosis || '—' },
          { label: 'Notes', value: entry.notes || '—' },
          { label: 'Recorded', value: new Date(entry.created_at) }
        ]
      });
    } else if (action === 'prescribe') {
      if (!canCreatePrescriptions()) {
        showToast('Only doctors can create prescriptions.', 'warning');
        return;
      }
      openPrescriptionModalForPatient(entry.patientId || '', entry.dbId || null, entry.patientName || '');
    }
  });
}

// Serving queue table click handler (consult button)
const servingQueueTbody = document.getElementById('serving-queue-tbody');
if (servingQueueTbody) {
  servingQueueTbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (!btn) return;
    const action = btn.getAttribute('data-action');
    const id = btn.getAttribute('data-id');
    const entry = consultationQueueTickets.find(c => c.id === id);
    if (!action || !entry) return;
    if (action === 'consult') {
      if (!canConsultPatients()) {
        showToast('Only doctors can create consultations.', 'warning');
        return;
      }
      openConsultationModal({
        patientId: entry.patientId || '',
        patientName: entry.patientName || '',
        serviceLabel: entry.serviceLabel || '',
        queueTicketId: entry.queueTicketId || null,
        symptoms: entry.symptoms || '',
        notes: entry.notes || ''
      });
    }
  });
}

// Simple printable report generator (user can Save as PDF via print dialog)
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
  // give the browser a moment to render then call print
  setTimeout(() => { win.print(); }, 500);
}

// report buttons
if (consultReportBtn) {
  consultReportBtn.addEventListener('click', () => {
    const headers = ['Patient Name', 'Patient ID', 'Diagnosis', 'Date'];
    const rows = consultations.map(c => [c.patientName || c.patientId || '—', c.patientId || '—', c.diagnosis || '—', formatDateTime(c.created_at)]);
    generateReport('Consultations Report', headers, rows);
  });
}

if (medicineReportBtn) {
  medicineReportBtn.addEventListener('click', () => {
    const listToExport = filteredMedicines.length > 0 ? filteredMedicines : medicines;
    const headers = ['Medicine', 'Description', 'Quantity', 'Unit', 'Expiry Date', 'Status'];
    const rows = listToExport.map(m => {
      const isLowStock = m.qty <= 5 && m.qty > 0;
      const isOutOfStock = m.qty <= 0;
      const isExpired = m.expiry_date && new Date(m.expiry_date) < new Date();
      let status = 'In Stock';
      if (isExpired) status = 'Expired';
      else if (isOutOfStock) status = 'Out of Stock';
      else if (isLowStock) status = 'Low Stock';

      return [
        m.name,
        m.description || '—',
        m.qty,
        m.unit || '—',
        m.expiry_date ? new Date(m.expiry_date).toLocaleDateString() : '—',
        status
      ];
    });
    generateReport('Medicine Inventory Report', headers, rows);
  });
}

const medicineCSVExportBtn = document.getElementById('medicine-csv-export-btn');
if (medicineCSVExportBtn) {
  medicineCSVExportBtn.addEventListener('click', () => {
    const listToExport = filteredMedicines.length > 0 ? filteredMedicines : medicines;
    const headers = ['Medicine', 'Description', 'Quantity', 'Unit', 'Expiry Date', 'Status'];
    
    let csvContent = headers.join(',') + '\n';
    
    listToExport.forEach(m => {
      const isLowStock = m.qty <= 5 && m.qty > 0;
      const isOutOfStock = m.qty <= 0;
      const isExpired = m.expiry_date && new Date(m.expiry_date) < new Date();
      let status = 'In Stock';
      if (isExpired) status = 'Expired';
      else if (isOutOfStock) status = 'Out of Stock';
      else if (isLowStock) status = 'Low Stock';

      const row = [
        `"${m.name}"`,
        `"${m.description || ''}"`,
        m.qty,
        `"${m.unit || ''}"`,
        `"${m.expiry_date || ''}"`,
        `"${status}"`
      ];
      csvContent += row.join(',') + '\n';
    });

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `medicine_inventory_${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  });
}

// Expose report generation for other entities
function generateUsersReport() {
  const rows = latestStaffList.map(u => [u.username || '', u.employee_id || '', u.role || '', u.status || '']);
  generateReport('Users Report', ['Username', 'Employee ID', 'Role', 'Status'], rows);
}

function generateCitizensReport() {
  const rows = latestPatientsList.map(c => [
    c.username || c.name || '—',
    c.email || '—',
    c.contact_number || '—',
    formatDateTime(c.created_at)
  ]);
  generateReport('Citizens Report', ['Username', 'Email', 'Contact Number', 'Registered'], rows);
}

// wire up simple global report triggers (if buttons exist elsewhere)
const usersReportBtn = document.getElementById('users-report-btn');
if (usersReportBtn) usersReportBtn.addEventListener('click', generateUsersReport);

const citizensReportBtn = document.getElementById('citizens-report-btn');
if (citizensReportBtn) citizensReportBtn.addEventListener('click', generateCitizensReport);

// --- Prescription modal ---

function openPrescriptionModalForPatient(patientId = '', consultationDbId = null, patientName = '', queueTicketId = null) {
  if (!prescriptionModal) return;
  prescriptionModal.classList.remove('hidden');
  if (prescriptionPatient) prescriptionPatient.value = patientId || '';
  const displayEl = document.getElementById('prescription-patient-display');
  if (displayEl) {
    displayEl.textContent = patientName || patientId || '—';
  }
  if (prescriptionForm) {
    prescriptionForm.dataset.consultationDbId = consultationDbId ? String(consultationDbId) : '';
    prescriptionForm.dataset.patientName = patientName || '';
    prescriptionForm.dataset.queueTicketId = queueTicketId ? String(queueTicketId) : '';
  }
  if (prescriptionLines) {
    prescriptionLines.innerHTML = '';
    addPrescriptionLine();
  }
}

function calculatePrescriptionQty(freq, duration) {
  let dosesPerDay = 1;
  const f = freq.toLowerCase().trim();
  if (f.includes('bid') || f.includes('twice') || f.includes('q12h')) dosesPerDay = 2;
  else if (f.includes('tid') || f.includes('three') || f.includes('q8h')) dosesPerDay = 3;
  else if (f.includes('qid') || f.includes('four') || f.includes('q6h')) dosesPerDay = 4;
  else if (f.includes('q4h')) dosesPerDay = 6;
  else if (f.includes('q2h')) dosesPerDay = 12;
  else if (f.includes('stat')) dosesPerDay = 1;
  // OD / OM / ON are already 1

  let days = 0;
  const d = duration.toLowerCase().trim();
  const numMatch = d.match(/(\d+)/);
  if (numMatch) {
    days = parseInt(numMatch[1]);
    if (d.includes('week')) days *= 7;
    else if (d.includes('month')) days *= 30;
  } else if (d.includes('maintenance')) {
    days = 30; // Default to 30 days for maintenance if not specified
  }
  
  return dosesPerDay * (days || 1);
}

function addPrescriptionLine() {
  if (!prescriptionLines) return;
  const line = document.createElement('div');
  line.className = 'field prescription-line-item';
  line.style.padding = '16px';
  line.style.background = '#f8fafc';
  line.style.borderRadius = '12px';
  line.style.marginBottom = '16px';
  line.style.border = '1px solid #e2e8f0';
  line.style.boxShadow = '0 1px 2px rgba(0,0,0,0.05)';
  line.innerHTML = `
    <div style="display: grid; grid-template-columns: 2fr 0.6fr 1fr 1fr 1fr auto; gap: 10px; align-items: end;">
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Medicine Name</label>
        <input type="text" class="pres-med" list="medicine-list" placeholder="Search medicine..." style="width: 100%; height: 38px; padding: 0 10px; border: 1px solid #cbd5e1; border-radius: 8px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Qty</label>
        <input type="number" class="pres-qty" value="1" min="1" style="width: 100%; height: 38px; padding: 0 10px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Dosage</label>
        <input type="text" class="pres-dosage" list="dosage-list" placeholder="e.g. 500 mg" style="width: 100%; height: 38px; padding: 0 10px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Frequency</label>
        <input type="text" class="pres-freq" list="frequency-list" placeholder="e.g. BID" style="width: 100%; height: 38px; padding: 0 10px;" required />
      </div>
      <div class="field" style="margin: 0;">
        <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Duration</label>
        <input type="text" class="pres-duration" list="duration-list" placeholder="e.g. 7 days" style="width: 100%; height: 38px; padding: 0 10px;" required />
      </div>
      <button type="button" class="btn small btn-delete" data-action="remove-line" style="height: 38px; width: 38px; min-width: 38px; display: flex; align-items: center; justify-content: center; font-size: 18px; line-height: 1; padding: 0; background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; margin: 0;">×</button>
    </div>
    <div style="margin-top: 14px; padding-top: 14px; border-top: 1px dashed #e2e8f0;">
      <label class="inputLabel" style="font-size: 11px; margin-bottom: 4px;">Special Instructions / Remarks</label>
      <textarea class="pres-instructions" placeholder="Enter specific intake instructions or notes for the patient..." rows="2" style="width: 100%; max-width: 100%; box-sizing: border-box; resize: vertical; font-size: 13px; padding: 10px; border-radius: 8px; border: 1px solid #e2e8f0; background: white; display: block;"></textarea>
    </div>
  `;
  prescriptionLines.appendChild(line);

  const qtyInput = line.querySelector('.pres-qty');
  const freqInput = line.querySelector('.pres-freq');
  const durInput = line.querySelector('.pres-duration');

  const updateQty = () => {
    const freq = freqInput.value;
    const dur = durInput.value;
    if (freq || dur) {
      const calculated = calculatePrescriptionQty(freq, dur);
      if (calculated > 0) qtyInput.value = calculated;
    }
  };

  freqInput.addEventListener('input', updateQty);
  durInput.addEventListener('input', updateQty);
  freqInput.addEventListener('change', updateQty);
  durInput.addEventListener('change', updateQty);

  line.querySelector('[data-action="remove-line"]').addEventListener('click', () => line.remove());
}

if (addPrescriptionLineBtn) {
  addPrescriptionLineBtn.addEventListener('click', addPrescriptionLine);
}

if (cancelPrescriptionBtn) {
  cancelPrescriptionBtn.addEventListener('click', () => {
    if (prescriptionModal) prescriptionModal.classList.add('hidden');
    if (prescriptionForm) prescriptionForm.dataset.consultationDbId = '';
  });
}

if (prescriptionModal) {
  prescriptionModal.addEventListener('click', (e) => {
    if (e.target === prescriptionModal) {
      prescriptionModal.classList.add('hidden');
      if (prescriptionForm) prescriptionForm.dataset.consultationDbId = '';
    }
  });
}

if (prescriptionForm) {
  prescriptionForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!canCreatePrescriptions()) {
      showToast('Only doctors can create prescriptions.', 'warning');
      return;
    }
    const patient = prescriptionPatient ? prescriptionPatient.value.trim() : '';
    if (!patient) { showToast('Patient ID required.', 'warning'); return; }

    const selects  = prescriptionForm.querySelectorAll('.pres-med');
    const qtys     = prescriptionForm.querySelectorAll('.pres-qty');
    const dosages  = prescriptionForm.querySelectorAll('.pres-dosage');
    const freqs    = prescriptionForm.querySelectorAll('.pres-freq');
    const notes    = prescriptionForm.querySelectorAll('.pres-instructions');
    const durations = prescriptionForm.querySelectorAll('.pres-duration');
    const items = [];
    for (let i = 0; i < selects.length; i++) {
      const name = selects[i].value;
      const qty  = Number(qtys[i].value) || 0;
      if (name && qty > 0) {
        items.push({
          name,
          qty,
          dosage:       dosages[i]?.value   || '',
          frequency:    freqs[i]?.value     || '',
          duration:     durations[i]?.value || '',
          instructions: notes[i]?.value     || ''
        });
      }
    }
    if (!items.length) { showToast('Add at least one medicine.', 'warning'); return; }

    const submitBtn = prescriptionForm.querySelector('button[type="submit"]');
    try {
      setLoading(submitBtn, true);
      await createPrescriptionEntry({
        patientId: patient,
        consultationDbId: Number(prescriptionForm.dataset.consultationDbId || '0') || null,
        items: items.map((it) => {
          const med = medicines.find((m) => String(m.name || '') === String(it.name || ''));
          return { 
            name: it.name, 
            qty: it.qty, 
            unit: med?.unit || '', 
            dosage: it.dosage, 
            frequency: it.frequency,
            duration: it.duration,
            instructions: it.instructions
          };
        })
      });

      showToast('Prescription created successfully!', 'success');

      if (prescriptionModal) prescriptionModal.classList.add('hidden');
      
      // Automatically complete queue ticket if applicable
      const qId = prescriptionForm.dataset.queueTicketId;
      if (qId) {
        completeQueueTicket(qId);
      }

      if (prescriptionForm) {
        prescriptionForm.dataset.consultationDbId = '';
        prescriptionForm.dataset.queueTicketId = '';
      }
    } catch (error) {
      console.error('Failed to save prescription:', error);
      showToast(error.message || 'Unable to create prescription.', 'error');
    } finally {
      setLoading(submitBtn, false);
    }
  });
}

// Open prescription from inside consultation modal (consult-add-prescription)
const consultAddPrescBtn = document.getElementById('consult-add-prescription');
if (consultAddPrescBtn && prescriptionModal) {
  consultAddPrescBtn.addEventListener('click', () => {
    if (!canCreatePrescriptions()) {
      showToast('Only doctors can create prescriptions.', 'warning');
      return;
    }
    const pid  = document.getElementById('consult-patient-id')?.value || '';
    const name = consultationForm?.dataset?.patientName || '';
    openPrescriptionModalForPatient(pid, null, name);
  });
}


// ═══════════════════════════════════════════════════════════════════════════
// PHARMACY DISPENSING MODULE
// ═══════════════════════════════════════════════════════════════════════════

let currentPrescriptionData = null;
let currentMedicineItems = [];

// Initialize pharmacy module
function initPharmacyModule() {
  const searchBtn = document.getElementById('pharmacy-search-btn');
  const clearBtn = document.getElementById('pharmacy-clear-btn');
  const searchInput = document.getElementById('pharmacy-prescription-search');
  const dispenseSelectedBtn = document.getElementById('pharmacy-dispense-selected-btn');
  const dispenseAllBtn = document.getElementById('pharmacy-dispense-all-btn');
  const cancelBtn = document.getElementById('pharmacy-cancel-prescription-btn');
  const selectAllCheckbox = document.getElementById('pharmacy-select-all');

  if (searchBtn) {
    searchBtn.addEventListener('click', searchPrescription);
  }

  if (clearBtn) {
    clearBtn.addEventListener('click', clearPharmacySearch);
  }

  if (searchInput) {
    searchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        searchPrescription();
      }
    });
  }

  if (dispenseSelectedBtn) {
    dispenseSelectedBtn.addEventListener('click', dispenseSelectedMedicines);
  }

  if (dispenseAllBtn) {
    dispenseAllBtn.addEventListener('click', dispenseAllMedicines);
  }

  if (cancelBtn) {
    cancelBtn.addEventListener('click', cancelPrescription);
  }

  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', (e) => {
      const checkboxes = document.querySelectorAll('.pharmacy-medicine-checkbox');
      checkboxes.forEach(cb => {
        if (!cb.disabled) {
          cb.checked = e.target.checked;
        }
      });
    });
  }

  const tbody = document.getElementById('pharmacy-medicines-tbody');
  if (tbody) {
    tbody.addEventListener('change', async (e) => {
      if (e.target.classList.contains('pharmacy-available-checkbox') || 
          e.target.classList.contains('pharmacy-given-checkbox')) {
        const index = parseInt(e.target.dataset.index);
        const item = currentMedicineItems[index];
        const isAvailable = e.target.classList.contains('pharmacy-available-checkbox') 
          ? e.target.checked 
          : (item.is_available !== false);
        const isDispensed = e.target.classList.contains('pharmacy-given-checkbox') 
          ? e.target.checked 
          : item.is_dispensed;
        
        await updatePrescriptionItemStatus(item.id, isAvailable, isDispensed);
        item.is_available = isAvailable;
        item.is_dispensed = isDispensed;
      }
    });
  }
}

async function updatePrescriptionItemStatus(itemId, isAvailable, isDispensed) {
  try {
    const { supabase } = await loadSupabaseModule();
    const { error } = await supabase
      .from('prescription_items')
      .update({ is_available: isAvailable, is_dispensed: isDispensed })
      .eq('id', itemId);

    if (error) {
      console.error('Error updating item status:', error);
      showToast('Error updating medication status', 'error');
    }
  } catch (error) {
    console.error('Error updating item status:', error);
  }
}

async function searchPrescription() {
  const searchInput = document.getElementById('pharmacy-prescription-search');
  const prescriptionCode = searchInput.value.trim();

  if (!prescriptionCode) {
    showToast('Please enter a prescription code', 'error');
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();

    // Search for prescription header
    const { data: prescriptionData, error: prescriptionError } = await supabase
      .from('prescription_headers')
      .select(`
        id,
        prescription_code,
        dispensing_status,
        issued_at,
        dispensed_at,
        consultation_id,
        patient_identifier,
        doctor_staff_id,
        doctor:staff(firstname, surname)
      `)
      .eq('prescription_code', prescriptionCode)
      .single();

    if (prescriptionError || !prescriptionData) {
      showToast('Prescription not found', 'error');
      return;
    }

    // Get patient information
    let patientName = 'Unknown Patient';
    let patientId = prescriptionData.patient_identifier || '-';

    if (prescriptionData.consultation_id) {
      const { data: consultationData } = await supabase
        .from('consultations')
        .select('patient_citizen_id, patient:citizens(firstname, surname)')
        .eq('id', prescriptionData.consultation_id)
        .single();

      if (consultationData && consultationData.patient) {
        patientName = `${consultationData.patient.firstname} ${consultationData.patient.surname}`;
        patientId = consultationData.patient_citizen_id;
      }
    } else if (prescriptionData.patient_identifier) {
      // Try to get patient by ID
      const { data: citizenData } = await supabase
        .from('citizens')
        .select('firstname, surname')
        .eq('id', prescriptionData.patient_identifier)
        .single();

      if (citizenData) {
        patientName = `${citizenData.firstname} ${citizenData.surname}`;
      }
    }

    // Get prescription items
    const { data: itemsData, error: itemsError } = await supabase
      .from('prescription_items')
      .select('*')
      .eq('prescription_id', prescriptionData.id);

    if (itemsError) {
      showToast('Error loading prescription items', 'error');
      return;
    }

    // Get current stock for each medicine
    const medicineNames = itemsData.map(item => item.medicine_name);
    const { data: stockData } = await supabase
      .from('medicines')
      .select('medicine_name, stock_quantity')
      .in('medicine_name', medicineNames);

    const stockMap = {};
    if (stockData) {
      stockData.forEach(item => {
        stockMap[item.medicine_name] = item.stock_quantity;
      });
    }

    // Store current prescription data
    currentPrescriptionData = {
      ...prescriptionData,
      patientName,
      patientId,
      doctorName: prescriptionData.doctor 
        ? `Dr. ${prescriptionData.doctor.first_name} ${prescriptionData.doctor.last_name}`
        : 'Unknown Doctor'
    };

    currentMedicineItems = itemsData.map(item => ({
      ...item,
      currentStock: stockMap[item.medicine_name] || 0
    }));

    // Display the prescription
    displayPrescriptionData();

  } catch (error) {
    console.error('Error searching prescription:', error);
    showToast('Error searching prescription', 'error');
  }
}

function displayPrescriptionData() {
  // Show results container, hide empty state
  document.getElementById('pharmacy-results-container').classList.remove('hidden');
  document.getElementById('pharmacy-empty-state').classList.add('hidden');

  // Populate patient card
  document.getElementById('pharmacy-patient-name').textContent = currentPrescriptionData.patientName;
  document.getElementById('pharmacy-patient-id').textContent = currentPrescriptionData.patientId;
  document.getElementById('pharmacy-prescription-code').textContent = currentPrescriptionData.prescription_code;
  document.getElementById('pharmacy-doctor-name').textContent = currentPrescriptionData.doctorName;

  const issuedDate = new Date(currentPrescriptionData.issued_at).toLocaleDateString();
  const expiryDate = new Date(new Date(currentPrescriptionData.issued_at).getTime() + 30 * 24 * 60 * 60 * 1000).toLocaleDateString();
  document.getElementById('pharmacy-issued-date').textContent = issuedDate;
  document.getElementById('pharmacy-expiry-date').textContent = expiryDate;

  // Update status badge
  const statusBadge = document.getElementById('pharmacy-status-badge');
  const status = currentPrescriptionData.dispensing_status;
  
  if (status === 'dispensed') {
    statusBadge.textContent = 'Dispensed';
    statusBadge.style.background = '#dcfce7';
    statusBadge.style.color = '#166534';
  } else if (status === 'cancelled') {
    statusBadge.textContent = 'Cancelled';
    statusBadge.style.background = '#fee2e2';
    statusBadge.style.color = '#991b1b';
  } else {
    statusBadge.textContent = 'Pending';
    statusBadge.style.background = '#fef3c7';
    statusBadge.style.color = '#92400e';
  }

  // Populate medicines table
  const tbody = document.getElementById('pharmacy-medicines-tbody');
  tbody.innerHTML = '';

  let hasInsufficientStock = false;

  currentMedicineItems.forEach((item, index) => {
    const hasStock = item.currentStock >= item.quantity;
    if (!hasStock) hasInsufficientStock = true;

    const isDispensed = status === 'dispensed';
    const isCancelled = status === 'cancelled';
    const canSelect = !isDispensed && !isCancelled && hasStock;

    const row = document.createElement('tr');
    row.innerHTML = `
      <td>
        <input 
          type="checkbox" 
          class="pharmacy-medicine-checkbox" 
          data-index="${index}"
          ${canSelect ? '' : 'disabled'}
          style="width: 18px; height: 18px; cursor: ${canSelect ? 'pointer' : 'not-allowed'};">
      </td>
      <td><strong>${escapeHtml(item.medicine_name)}</strong></td>
      <td>${escapeHtml(item.dosage || '-')}</td>
      <td>${item.quantity} ${escapeHtml(item.unit || '')}</td>
      <td>
        <span style="color: ${hasStock ? '#16a34a' : '#dc2626'}; font-weight: 600;">
          ${item.currentStock}
        </span>
      </td>
      <td style="text-align: center;">
        <input 
          type="checkbox" 
          class="pharmacy-available-checkbox" 
          data-index="${index}"
          ${item.is_available !== false ? 'checked' : ''}
          ${isDispensed || isCancelled ? 'disabled' : ''}
          style="width: 18px; height: 18px; cursor: pointer;">
      </td>
      <td style="text-align: center;">
        <input 
          type="checkbox" 
          class="pharmacy-given-checkbox" 
          data-index="${index}"
          ${item.is_dispensed ? 'checked' : ''}
          ${isDispensed || isCancelled ? 'disabled' : ''}
          style="width: 18px; height: 18px; cursor: pointer;">
      </td>
      <td>
        ${item.is_available === false
          ? '<span style="color: #64748b; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg> Out of Stock</span>'
          : (item.is_dispensed 
              ? '<span style="color: #16a34a; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Given</span>'
              : (hasStock 
                  ? '<span style="color: #0891b2; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> Pending</span>' 
                  : '<span style="color: #dc2626; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg> Insufficient</span>'))}
      </td>
    `;
    tbody.appendChild(row);
  });

  // Show/hide warning message
  const warningDiv = document.getElementById('pharmacy-warning-message');
  if (hasInsufficientStock && status === 'pending') {
    warningDiv.classList.remove('hidden');
  } else {
    warningDiv.classList.add('hidden');
  }

  // Disable buttons if already dispensed or cancelled
  const dispenseSelectedBtn = document.getElementById('pharmacy-dispense-selected-btn');
  const dispenseAllBtn = document.getElementById('pharmacy-dispense-all-btn');
  const cancelBtn = document.getElementById('pharmacy-cancel-prescription-btn');

  if (isDispensed || isCancelled) {
    dispenseSelectedBtn.disabled = true;
    dispenseAllBtn.disabled = true;
    cancelBtn.disabled = true;
    dispenseSelectedBtn.style.opacity = '0.5';
    dispenseAllBtn.style.opacity = '0.5';
    cancelBtn.style.opacity = '0.5';
  } else {
    dispenseSelectedBtn.disabled = false;
    dispenseAllBtn.disabled = false;
    cancelBtn.disabled = false;
    dispenseSelectedBtn.style.opacity = '1';
    dispenseAllBtn.style.opacity = '1';
    cancelBtn.style.opacity = '1';
  }
}

async function dispenseSelectedMedicines() {
  const checkboxes = document.querySelectorAll('.pharmacy-medicine-checkbox:checked:not([disabled])');
  
  if (checkboxes.length === 0) {
    showToast('Please select at least one medicine to dispense', 'warning');
    return;
  }

  const selectedItems = Array.from(checkboxes).map(cb => {
    const index = parseInt(cb.dataset.index);
    return currentMedicineItems[index];
  });

  await dispenseMedicines(selectedItems, false);
}

async function dispenseAllMedicines() {
  const availableItems = currentMedicineItems.filter(item => item.currentStock >= item.quantity);
  
  if (availableItems.length === 0) {
    showToast('No medicines available to dispense', 'error');
    return;
  }

  await dispenseMedicines(availableItems, true);
}

async function dispenseMedicines(items, isFullDispense) {
  if (!confirm(`Are you sure you want to dispense ${items.length} medicine(s)?`)) {
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();

    // Update medicine stock
    for (const item of items) {
      const newStock = item.currentStock - item.quantity;
      
      const { error: stockError } = await supabase
        .from('medicines')
        .update({ stock_quantity: newStock })
        .eq('medicine_name', item.medicine_name);

      if (stockError) {
        console.error('Error updating stock:', stockError);
        showToast(`Error updating stock for ${item.medicine_name}`, 'error');
        return;
      }
    }

    // Update prescription status if all items dispensed
    if (isFullDispense || items.length === currentMedicineItems.length) {
      const { error: prescriptionError } = await supabase
        .from('prescription_headers')
        .update({ 
          dispensing_status: 'dispensed',
          dispensed_at: new Date().toISOString()
        })
        .eq('id', currentPrescriptionData.id);

      if (prescriptionError) {
        console.error('Error updating prescription:', prescriptionError);
      }

      currentPrescriptionData.dispensing_status = 'dispensed';
      currentPrescriptionData.dispensed_at = new Date().toISOString();
    }

    showToast(`Successfully dispensed ${items.length} medicine(s)`, 'success');
    
    // Refresh the display
    await searchPrescription();

  } catch (error) {
    console.error('Error dispensing medicines:', error);
    showToast('Error dispensing medicines', 'error');
  }
}

async function cancelPrescription() {
  if (!confirm('Are you sure you want to cancel this prescription? This action cannot be undone.')) {
    return;
  }

  try {
    const { supabase } = await loadSupabaseModule();

    const { error } = await supabase
      .from('prescription_headers')
      .update({ dispensing_status: 'cancelled' })
      .eq('id', currentPrescriptionData.id);

    if (error) {
      console.error('Error cancelling prescription:', error);
      showToast('Error cancelling prescription', 'error');
      return;
    }

    showToast('Prescription cancelled successfully', 'success');
    currentPrescriptionData.dispensing_status = 'cancelled';
    displayPrescriptionData();

  } catch (error) {
    console.error('Error cancelling prescription:', error);
    showToast('Error cancelling prescription', 'error');
  }
}

function clearPharmacySearch() {
  document.getElementById('pharmacy-prescription-search').value = '';
  document.getElementById('pharmacy-results-container').classList.add('hidden');
  document.getElementById('pharmacy-empty-state').classList.remove('hidden');
  document.getElementById('pharmacy-select-all').checked = false;
  currentPrescriptionData = null;
  currentMedicineItems = [];
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initPharmacyModule);
} else {
  initPharmacyModule();
}

// --- Vital Signs Assessment Modal ---
const vaModal = document.getElementById('vital-assessment-modal');
const vaForm = document.getElementById('vital-assessment-form');

async function openVitalAssessmentModal(ticket) {
  if (!vaModal || !ticket) return;
  if (vaForm) vaForm.reset();
  const ticketIdInput = document.getElementById('va-queue-ticket-id');
  const citizenIdInput = document.getElementById('va-citizen-id');
  if (ticketIdInput) ticketIdInput.value = ticket.id;
  if (citizenIdInput) citizenIdInput.value = ticket.citizen?.id || '';
  const bannerEl = document.getElementById('vital-modal-patient-banner');
  const nameEl = document.getElementById('vital-modal-patient-name');
  const metaEl = document.getElementById('vital-modal-patient-meta');
  const badgeEl = document.getElementById('vital-modal-existing-badge');
  if (bannerEl) bannerEl.style.display = 'block';
  if (nameEl) nameEl.textContent = `${ticket.citizen?.firstname || ''} ${ticket.citizen?.surname || ''}`.trim() || 'Guest Patient';
  if (metaEl) {
    const age = ticket.citizen?.age ? `${ticket.citizen.age} yrs` : 'Age N/A';
    const gender = ticket.citizen?.sex || 'Sex N/A';
    metaEl.textContent = `${ticket.service_label} | ${age} | ${gender}`;
  }
  if (badgeEl) badgeEl.style.display = 'none';
  try {
    const { supabase } = await loadSupabaseModule();
    const { data: existing } = await supabase
      .from('vital_signs')
      .select('*')
      .eq('queue_ticket_id', ticket.id)
      .maybeSingle();
    if (existing) {
      if (badgeEl) badgeEl.style.display = 'inline-flex';
      if (document.getElementById('va-chief-complaint')) document.getElementById('va-chief-complaint').value = existing.chief_complaint || '';
      if (document.getElementById('va-bp')) document.getElementById('va-bp').value = existing.blood_pressure || '';
      if (document.getElementById('va-hr')) document.getElementById('va-hr').value = existing.heart_rate || '';
      if (document.getElementById('va-rr')) document.getElementById('va-rr').value = existing.respiratory_rate || '';
      if (document.getElementById('va-temp')) document.getElementById('va-temp').value = existing.temperature || '';
      if (document.getElementById('va-spo2')) document.getElementById('va-spo2').value = existing.oxygen_saturation || '';
      if (document.getElementById('va-meds')) document.getElementById('va-meds').value = existing.current_medications || '';
      if (document.getElementById('va-notes')) document.getElementById('va-notes').value = existing.notes || '';
    } else {
      // New assessment: pre-fill chief complaint with citizen's reason for visit
      if (document.getElementById('va-chief-complaint')) {
        document.getElementById('va-chief-complaint').value = ticket.reason || '';
      }
    }
  } catch (err) { console.warn('Error checking existing vitals:', err); }
  vaModal.classList.remove('hidden');
  vaModal.style.display = 'flex';
}

function closeVitalAssessmentModal() {
  if (vaModal) { vaModal.classList.add('hidden'); vaModal.style.display = 'none'; }
}

if (vaForm) {
  vaForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const submitBtn = vaForm.querySelector('button[type="submit"]');
    const ticketId = document.getElementById('va-queue-ticket-id')?.value;
    const citizenId = document.getElementById('va-citizen-id')?.value;
    const complaint = document.getElementById('va-chief-complaint')?.value;
    if (!ticketId) { showToast('Missing queue ticket reference.', 'error'); return; }
    // Validation removed as per user request to allow saving without required values
    setLoading(submitBtn, true);
    try {
      const user = await ensureAuthenticatedSession();
      const { supabase } = await loadSupabaseModule();
      const rpcPayload = {
        p_queue_ticket_id: Number(ticketId),
        p_citizen_id: citizenId ? Number(citizenId) : null,
        p_chief_complaint: complaint || 'General Checkup',
        p_blood_pressure: document.getElementById('va-bp')?.value || null,
        p_heart_rate: parseInt(document.getElementById('va-hr')?.value) || null,
        p_temperature: parseFloat(document.getElementById('va-temp')?.value) || null,
        p_respiratory_rate: parseInt(document.getElementById('va-rr')?.value) || null,
        p_oxygen_saturation: parseInt(document.getElementById('va-spo2')?.value) || null,
        p_current_medications: document.getElementById('va-meds')?.value || null,
        p_notes: document.getElementById('va-notes')?.value || null
      };

      const { data: rpcRes, error: rpcError } = await supabase.rpc('upsert_vital_assessment', rpcPayload);
      if (rpcError) throw rpcError;
      if (rpcRes && rpcRes.error) throw new Error(rpcRes.error);
      showToast('Vital signs saved successfully.', 'success');
      closeVitalAssessmentModal();
      if (typeof appointments !== 'undefined' && appointments.loadQueueTickets) {
        await appointments.loadQueueTickets();
      }
    } catch (err) {
      console.error('Vitals assessment submission error:', err);
      showToast(err.message || 'Failed to save vital signs.', 'error');
    } finally { setLoading(submitBtn, false); }
  });
}

const vaCancelBtn = document.getElementById('va-cancel-btn');
if (vaCancelBtn) { vaCancelBtn.addEventListener('click', closeVitalAssessmentModal); }
if (vaModal) {
  vaModal.addEventListener('click', (e) => {
    if (e.target === vaModal) closeVitalAssessmentModal();
  });
}

/**
 * UNIFIED QUEUE MODULE (Rebuilt & Embedded)
 */
const appointments = (() => {
  const state = { tickets: [], loading: false };

  const init = async () => {
    console.log('[Queue] Module init...');
    setupUI();
    setupRealtime();
    await refresh();
    // Auto-refresh every 5 seconds to ensure sync even if realtime drops
    setInterval(refresh, 5000);
  };

  const setupRealtime = async () => {
    if (isDemoMode) return;
    try {
      const { supabase } = await loadSupabaseModule();
      supabase
        .channel('queue-board-updates')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_tickets' }, (payload) => {
          console.log('[Queue] Realtime update:', payload.eventType);
          refresh();
        })
        .subscribe((status) => {
          console.log('[Queue] Realtime status:', status);
        });
    } catch (err) {
      console.error('[Queue] Failed to setup realtime:', err);
    }
  };

  const setupUI = () => {
    const refreshBtn = document.getElementById('queue-refresh-btn');
    if (refreshBtn && !refreshBtn.dataset.bound) {
      refreshBtn.addEventListener('click', refresh);
      refreshBtn.dataset.bound = 'true';
    }
    const tvBtn = document.getElementById('open-tv-view-btn');
    if (tvBtn && !tvBtn.dataset.bound) {
      tvBtn.addEventListener('click', () => {
        window.open('tv-view.html', '_blank', 'noopener,noreferrer');
      });
      tvBtn.dataset.bound = 'true';
    }
    const board = document.querySelector('.queue-board');
    if (board && !board.dataset.bound) {
      board.addEventListener('click', handleAction);
      board.addEventListener('dragstart', handleDragStart);
      board.addEventListener('dragover', handleDragOver);
      board.addEventListener('dragleave', handleDragLeave);
      board.addEventListener('drop', handleDrop);
      board.dataset.bound = 'true';
    }
  };

  const refresh = async () => {
    if (state.loading) return;
    // Don't refresh if user is currently dragging a ticket to avoid breaking the interaction
    if (document.querySelector('.queue-ticket-card.dragging')) return;
    state.loading = true;
    try {
      const { supabase } = await loadSupabaseModule();
      const { data, error } = await supabase
        .from('queue_tickets')
        .select('*, citizen:citizens(*), vitals:vital_signs(id)')
        .in('status', ['waiting', 'on_call', 'serving'])
        .order('queue_number', { ascending: true });

      if (error) throw error;
      state.tickets = data || [];
      console.log('[Queue] Synced tickets:', state.tickets.length);
      render();
    } catch (err) {
      console.error('[Queue] Sync error:', err);
    } finally {
      state.loading = false;
    }
  };

  const render = () => {
    const getStatus = (t) => String(t.status || '').trim().toLowerCase();
    const lanes = {
      waiting: state.tickets.filter(t => getStatus(t) === 'waiting'),
      on_call: state.tickets.filter(t => getStatus(t) === 'on_call'),
      serving: state.tickets.filter(t => getStatus(t) === 'serving')
    };

    renderLane('queue-waiting-list', lanes.waiting);
    renderLane('queue-oncall-list', lanes.on_call);
    renderLane('queue-serving-list', lanes.serving);

    const updateText = (id, val) => {
      const el = document.getElementById(id);
      if (el) el.textContent = val;
    };

    updateText('queue-waiting-count', lanes.waiting.length);
    updateText('queue-oncall-count', lanes.on_call.length);
    updateText('queue-serving-count', lanes.serving.length);
    updateText('queue-summary-badge', `Waiting: ${lanes.waiting.length} | On Call: ${lanes.on_call.length} | Serving: ${lanes.serving.length}`);
    
    // Support multiple serving tickets in the status badge
    const servingNumbers = lanes.serving.map(t => `#${String(t.queue_number).padStart(3, '0')}`);
    const servingBadge = document.getElementById('queue-current-serving-badge');
    if (servingBadge) {
      if (servingNumbers.length > 0) {
        servingBadge.innerHTML = `
          <span style="color:#0369a1; font-weight:800;">Currently Serving:</span> 
          <span style="background:#0ea5e9; color:white; padding:1px 8px; border-radius:6px; font-family:monospace;">${servingNumbers.join(', ')}</span>
        `;
        servingBadge.style.display = 'inline-flex';
      } else {
        servingBadge.textContent = 'Current serving: none';
      }
    }
  };

  const renderLane = (id, list) => {
    const container = document.getElementById(id);
    if (!container) return;
    if (list.length === 0) {
      container.innerHTML = '<div class="queue-ticket-empty">No tickets.</div>';
      return;
    }
    container.innerHTML = list.map(t => `
      <div class="queue-ticket-card" data-id="${t.id}" draggable="true">
        <div class="queue-ticket-top">
          <span class="queue-ticket-queue">#${String(t.queue_number).padStart(3, '0')}</span>
          ${(t.vitals && t.vitals.length > 0) ? '<span class="vitals-badge" title="Vital assessment completed">✓ Vitals</span>' : ''}
          <span class="queue-ticket-code">${t.ticket_code}</span>
        </div>
        <div class="queue-ticket-name">${t.citizen?.firstname || ''} ${t.citizen?.surname || ''}</div>
        <div class="queue-ticket-meta">${t.service_label}</div>
        <div class="queue-ticket-actions">
          ${getStatus(t) === 'waiting' ? '<button class="queue-ticket-btn" data-action="move" data-lane="on_call">On Call</button>' : ''}
          ${getStatus(t) === 'on_call' ? ((t.vitals && t.vitals.length > 0) ? '<button class="queue-ticket-btn" data-action="move" data-lane="serving">Serve</button>' : '') + '<button class="queue-ticket-btn btn-vital" data-action="vital">Vitals</button>' : ''}
        </div>
      </div>`).join('');
  };

  const getStatus = (t) => String(t.status || '').trim().toLowerCase();

  const handleAction = async (e) => {
    const btn = e.target.closest('button');
    const card = e.target.closest('.queue-ticket-card');
    if (!card) return;

    const id = card.dataset.id;

    if (btn) {
      const action = btn.dataset.action;
      const lane = btn.dataset.lane;

      try {
        const { supabase } = await loadSupabaseModule();
        if (action === 'move') {
          await supabase.from('queue_tickets').update({ status: lane }).eq('id', id);
        } else if (action === 'complete') {
          await supabase.from('queue_tickets').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('id', id);
        } else if (action === 'vital') {
          const ticket = state.tickets.find(t => String(t.id) === String(id));
          if (ticket) {
            if (typeof openVitalAssessmentModal === 'function') {
              await openVitalAssessmentModal(ticket);
            }
          }
          return;
        }
        await refresh();
      } catch (err) {
        console.error('[Queue] Action error:', err);
      }
    } else {
      // Clicked the card itself
      openQueueTicketDetail(id);
    }
  };

  const openQueueTicketDetail = (id) => {
    const ticket = state.tickets.find(t => String(t.id) === String(id));
    if (!ticket) return;

    const modal = document.getElementById('queue-ticket-detail-modal');
    const body = document.getElementById('queue-ticket-detail-body');
    if (!modal || !body) return;

    const citizen = ticket.citizen || {};
    const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || 'Guest Patient';
    const age = citizen.age ? `${citizen.age} yrs` : 'Age N/A';
    const gender = citizen.sex || 'Sex N/A';
    const phone = citizen.contact_number || 'No phone';

    body.innerHTML = `
      <div style="background:#f8fafc; border-radius:12px; padding:16px; margin-bottom:16px; border:1px solid #e2e8f0;">
        <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Patient Info</div>
        <div style="font-size:18px; font-weight:800; color:#0f172a; margin-bottom:2px;">${fullName}</div>
        <div style="font-size:13px; color:#475569; font-weight:500;">${age} | ${gender} | ${phone}</div>
      </div>
      
      <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;">
        <div style="background:#fff; border:1px solid #e2e8f0; border-radius:10px; padding:12px;">
          <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Queue Info</div>
          <div style="font-size:16px; font-weight:700; color:#2563eb;">#${String(ticket.queue_number).padStart(3, '0')}</div>
          <div style="font-size:12px; font-weight:600; color:#475569;">${ticket.ticket_code}</div>
        </div>
        <div style="background:#fff; border:1px solid #e2e8f0; border-radius:10px; padding:12px;">
          <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Service</div>
          <div style="font-size:14px; font-weight:700; color:#0f172a;">${ticket.service_label}</div>
          <div style="font-size:12px; color:#64748b;">${new Date(ticket.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
        </div>
      </div>

      <div style="margin-top:16px; padding:12px; background:#f0f9ff; border:1px solid #bae6fd; border-radius:10px;">
        <div style="font-size:11px; color:#0369a1; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Status</div>
        <div style="font-size:14px; font-weight:700; color:#0c4a6e; text-transform:capitalize;">${ticket.status?.replace('_', ' ') || 'Pending'}</div>
      </div>
    `;

    modal.classList.remove('hidden');

    const closeBtn = document.getElementById('queue-ticket-detail-close');
    if (closeBtn) {
      closeBtn.onclick = () => modal.classList.add('hidden');
    }
    
    // Also handle delete if needed
    const deleteBtn = document.getElementById('queue-ticket-delete-btn');
    if (deleteBtn) {
      deleteBtn.onclick = async () => {
        if (!confirm('Are you sure you want to delete this queue ticket?')) return;
        try {
          const { supabase } = await loadSupabaseModule();
          const { error } = await supabase.from('queue_tickets').delete().eq('id', id);
          if (error) throw error;
          showToast('Ticket deleted successfully.', 'success');
          modal.classList.add('hidden');
          refresh();
        } catch (err) {
          console.error('[Queue] Delete error:', err);
          showToast('Failed to delete ticket.', 'error');
        }
      };
    }

    modal.onclick = (e) => {
      if (e.target === modal) modal.classList.add('hidden');
    };
  };

  const handleDragStart = (e) => {
    const card = e.target.closest('.queue-ticket-card');
    if (!card) return;
    card.classList.add('dragging');
    e.dataTransfer.setData('text/plain', card.dataset.id);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleDragOver = (e) => {
    e.preventDefault();
    const lane = e.target.closest('.queue-card-list');
    if (lane) lane.classList.add('drag-over');
  };

  const handleDragLeave = (e) => {
    const lane = e.target.closest('.queue-card-list');
    if (lane) lane.classList.remove('drag-over');
  };

  const handleDrop = async (e) => {
    e.preventDefault();
    const lane = e.target.closest('.queue-card-list');
    const ticketId = e.dataTransfer.getData('text/plain');
    document.querySelectorAll('.queue-card-list').forEach(l => l.classList.remove('drag-over'));
    document.querySelectorAll('.queue-ticket-card').forEach(c => c.classList.remove('dragging'));
    if (!lane || !ticketId) return;
    const targetStatus = lane.dataset.lane;
    if (!targetStatus) return;
    try {
      const { supabase } = await loadSupabaseModule();
      const { error } = await supabase.from('queue_tickets').update({ status: targetStatus }).eq('id', ticketId);
      if (error) throw error;
      await refresh();
    } catch (err) {
      console.error('[Queue] Drop error:', err);
      showToast('Failed to update ticket status.', 'error');
    }
  };

  return { init, loadQueueTickets: refresh };
})();

if (typeof appointments !== 'undefined') {
  appointments.init().catch(console.error);
}
