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
let manualRefreshInFlight = false;
const DASHBOARD_REQUEST_TIMEOUT_MS = 15000;

function formatPhysicalExam(physicalExam) {
  if (!physicalExam) return 'None';
  
  let examObj = physicalExam;
  if (typeof physicalExam === 'string') {
    const trimmed = physicalExam.trim();
    if (!trimmed || trimmed === '—' || trimmed === '-' || trimmed === 'null' || trimmed === 'None') return 'None';
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        examObj = JSON.parse(trimmed);
      } catch (e) {
        return physicalExam;
      }
    } else {
      return physicalExam;
    }
  }
  
  if (typeof examObj === 'object' && examObj !== null) {
    const keyLabels = {
      heent: 'HEENT',
      chest: 'Chest & Lungs',
      heart: 'Heart',
      abdomen: 'Abdomen',
      extremities: 'Extremities',
      neurological: 'Neurological',
      others: 'Other Physical Findings',
      other: 'Other Physical Findings'
    };
    
    const lines = [];
    for (const [key, value] of Object.entries(examObj)) {
      const vStr = String(value || '').trim();
      if (vStr !== '' && vStr !== '—' && vStr !== 'null') {
        const label = keyLabels[key.toLowerCase()] || (key.charAt(0).toUpperCase() + key.slice(1));
        lines.push(`${label}: ${vStr}`);
      }
    }
    
    return lines.length > 0 ? lines.join('\n') : 'None';
  }
  
  return String(physicalExam);
}

function cleanNone(val) {
  const s = String(val || '').trim();
  return (!s || s === '—' || s === '-' || s.toLowerCase() === 'null' || s.toLowerCase() === 'undefined') ? 'None' : s;
}

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
    pagePreloader.style.display = 'none';
  }
  document.body.classList.remove('dashboard-loading');
}

// Dismiss preloader immediately so UI and skeleton shimmers are instantly visible
dismissPagePreloader();
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', dismissPagePreloader);
}

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
/**
 * Render shimmery statistics placeholder inside text nodes.
 */
function toggleStatsSkeleton(isLoading) {
  const statIds = [
    'stat-queue-waiting', 'stat-consults-today', 'stat-vitals-today',
    'stat-dispenses-today', 'stat-citizens', 'stat-active-staff'
  ];
  statIds.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    if (isLoading) {
      el.classList.remove('data-loaded');
      el.innerHTML = '<span class="skeleton-shimmer stat-skeleton" aria-hidden="true"></span>';
    }
  });
}

/**
 * Render shimmery user profile and breadcrumb placeholders during authentication / user load.
 */
function toggleUserSkeleton(isLoading) {
  const nameNodes = document.querySelectorAll('.user-name');
  const posNodes = document.querySelectorAll('.user-pos');
  const fullNodes = document.querySelectorAll('.user-name-full');
  const logoNode = document.getElementById('topbar-role-logo');

  if (isLoading) {
    nameNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-name-skeleton" aria-hidden="true"></span>';
      }
    });
    posNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-pos-skeleton" aria-hidden="true"></span>';
      }
    });
    fullNodes.forEach(node => {
      if (!node.querySelector('.skeleton-shimmer')) {
        node.innerHTML = '<span class="skeleton-shimmer user-fullname-skeleton" aria-hidden="true"></span>';
      }
    });
  } else {
    if (logoNode) {
      logoNode.classList.remove('role-logo-skeleton', 'skeleton-shimmer');
    }
  }
}


/**
 * Render chart shimmer loading states.
 */
function toggleChartSkeleton(chartCanvasId, isLoading) {
  const canvas = document.getElementById(chartCanvasId);
  if (!canvas) return;
  
  let wrapper = canvas.parentElement.querySelector('.skeleton-chart-wrapper');
  
  if (isLoading) {
    if (!wrapper) {
      wrapper = document.createElement('div');
      wrapper.className = 'skeleton-chart-wrapper';
      
      const isCircular = chartCanvasId === 'dashboard-chart';
      if (isCircular) {
        wrapper.style.cssText = 'width:100%; height:200px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border-radius:12px; border:1px dashed #cbd5e1; position:relative; overflow:hidden;';
        wrapper.innerHTML = `
          <div class="skeleton-shimmer" style="width: 140px; height: 140px; border-radius: 50%; display: flex; align-items: center; justify-content: center; position: relative; box-shadow: 0 4px 12px rgba(15,23,42,0.03);">
            <div style="width: 82px; height: 82px; border-radius: 50%; background: #ffffff; box-shadow: inset 0 2px 6px rgba(15,23,42,0.06); display: flex; flex-direction: column; align-items: center; justify-content: center; z-index: 2;">
              <div class="skeleton-shimmer" style="width: 28px; height: 12px; border-radius: 3px; margin-bottom: 4px;"></div>
              <div class="skeleton-shimmer" style="width: 36px; height: 8px; border-radius: 2px;"></div>
            </div>
          </div>
        `;
      } else {
        wrapper.style.cssText = 'width:100%; height:200px; display:flex; align-items:center; justify-content:center; background:#f8fafc; border-radius:12px; border:1px dashed #cbd5e1; position:relative; overflow:hidden;';
        wrapper.innerHTML = `
          <div style="display:flex;align-items:flex-end;gap:12px;height:120px;width:80%;justify-content:center;">
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 40%; width: 24px; height: 40px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 70%; width: 24px; height: 75px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 50%; width: 24px; height: 55px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 90%; width: 24px; height: 95px; border-radius: 4px 4px 0 0;"></div>
            <div class="skeleton-shimmer skeleton-chart-bar" style="--h: 60%; width: 24px; height: 65px; border-radius: 4px 4px 0 0;"></div>
          </div>
        `;
      }
      canvas.style.display = 'none';
      canvas.parentElement.appendChild(wrapper);
    }
  } else {
    if (wrapper) {
      wrapper.remove();
    }
    canvas.style.display = '';
  }
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

  const backdrop = document.getElementById('sidebar-backdrop');
  if (backdrop) {
    if (isMobile && slid) {
      backdrop.classList.remove('hidden');
    } else {
      backdrop.classList.add('hidden');
    }
  }
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

const sidebarBackdropEl = document.getElementById('sidebar-backdrop');
if (sidebarBackdropEl) {
  sidebarBackdropEl.addEventListener('click', () => {
    if (sidebar) sidebar.classList.remove('slid');
    state();
  });
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

// User Profile Popover Controller
const profileTrigger = document.getElementById('user-profile-trigger');
const profilePopover = document.getElementById('user-profile-popover');
if (profileTrigger && profilePopover) {
  profileTrigger.addEventListener('click', (e) => {
    e.stopPropagation();
    const isHidden = profilePopover.classList.contains('hidden');
    profilePopover.classList.toggle('hidden', !isHidden);
    profileTrigger.setAttribute('aria-expanded', isHidden ? 'true' : 'false');
  });

  document.addEventListener('click', (e) => {
    if (!profilePopover.classList.contains('hidden')) {
      if (!profilePopover.contains(e.target) && !profileTrigger.contains(e.target)) {
        profilePopover.classList.add('hidden');
        profileTrigger.setAttribute('aria-expanded', 'false');
      }
    }
  });
}

state();

async function performLogout() {
  try {
    stopPresenceHeartbeat();
    stopAdminDashboardAutoRefresh();
    try {
      const { supabase } = await loadSupabaseModule();
      if (staffAvailabilityChannel) {
        supabase.removeChannel(staffAvailabilityChannel);
        staffAvailabilityChannel = null;
      }
      if (queueBoardChannel) {
        supabase.removeChannel(queueBoardChannel);
        queueBoardChannel = null;
      }
    } catch (_) {}
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
  if (profilePopover) {
    profilePopover.classList.add('hidden');
    if (profileTrigger) profileTrigger.setAttribute('aria-expanded', 'false');
  }
  const notifPanel = document.getElementById('notif-panel');
  if (notifPanel) notifPanel.classList.add('hidden');
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


// Role classification functions
function isAdminUser(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  return role === 'admin';
}

function isClinicalStaff(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  return role === 'doctor' || role === 'nurse' || role === 'staff';
}

function isFullAccessUser(user) {
  return isAdminUser(user) || isClinicalStaff(user);
}

const SECTION_ROLE_RULES = {
  'dashboard-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'users-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'announcements-section': ['admin', 'doctor', 'nurse'],
  'feedback-section': ['admin', 'doctor', 'nurse'],
  'stats-section': ['admin', 'doctor', 'nurse'],
  'reports-section': ['admin', 'doctor', 'nurse'],
  'medicine-section': ['doctor', 'nurse', 'pharmacist'],
  'consultation-section': ['doctor', 'nurse', 'pharmacist'],
  'schedule-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
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
    'role-logo-default',
    'role-logo-skeleton',
    'skeleton-shimmer'
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
  const role = String(user?.role || detectRoleFromTitle()).trim().toLowerCase();
  const isAdmin = isAdminUser(user);
  const isClinical = isClinicalStaff(user);
  const hasFullAccess = isFullAccessUser(user);
  
  // Handle .admin-only elements (for true admins only)
  document.querySelectorAll('.admin-only').forEach((element) => {
    const isSectionContainer = element.classList.contains('section-top');
    if (isAdmin) {
      if (!isSectionContainer) {
        element.classList.remove('hidden');
      }
    } else {
      element.classList.add('hidden');
    }
  });

  // Handle .clinical-only elements (for doctors and nurses)
  document.querySelectorAll('.clinical-only').forEach((element) => {
    const isSectionContainer = element.classList.contains('section-top');
    if (isClinical) {
      if (!isSectionContainer) {
        element.classList.remove('hidden');
      }
    } else {
      element.classList.add('hidden');
    }
  });

  // Handle .full-access elements (for admin, doctor, nurse)
  document.querySelectorAll('.full-access').forEach((element) => {
    const isSectionContainer = element.classList.contains('section-top');
    if (hasFullAccess) {
      if (!isSectionContainer) {
        element.classList.remove('hidden');
      }
    } else {
      element.classList.add('hidden');
    }
  });

  syncRoleNavigationAccess(role);

  sessionUserRole = role || sessionUserRole;
  toggleUserSkeleton(false);

  const userNameNodes = document.querySelectorAll('.user-name');
  userNameNodes.forEach(node => {
    node.textContent = getDisplayFirstName(user);
  });

  const fullNameNodes = document.querySelectorAll('.user-name-full');
  fullNameNodes.forEach(node => {
    const fullName = [user?.first_name, user?.last_name].filter(Boolean).join(' ') || user?.username || 'Clinical Personnel';
    node.textContent = fullName;
  });

  const userRoleNodes = document.querySelectorAll('.user-pos');
  userRoleNodes.forEach(node => {
    const roleText = String(user?.role || 'Nurse');
    node.textContent = roleText.charAt(0).toUpperCase() + roleText.slice(1);
  });
  applyRoleLogos(user?.role || 'nurse');
  applyConsultationAccess();

  // Update main dashboard titles based on role
  const mainDashTitle = document.getElementById('main-dashboard-title');
  const mainTopbarTitle = document.getElementById('main-topbar-title');
  if (mainDashTitle || mainTopbarTitle) {
    let roleText = toTitleCase(role);
    if (role === 'admin') roleText = 'Administrator';
    if (mainDashTitle) mainDashTitle.textContent = `${roleText} Dashboard`;
    if (mainTopbarTitle) mainTopbarTitle.textContent = `${roleText} Systems Overview`;
  }

  const nonAdminSection = document.getElementById('non-admin-section');
  
  // Admin and clinical staff get access to their respective sections
  if (hasFullAccess) {
    if (nonAdminSection) nonAdminSection.classList.add('hidden');
    return;
  }

  // Other roles (pharmacist, etc.)
  const registeredPane = document.getElementById('registered-pane');
  const patientsPane = document.getElementById('citizens-pane');
  const usersNavBtn = document.querySelector('[data-section="users-section"]');

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
        initMedicineSection();
        initClinicalData();
        break;
      case 'consultation-section':
        initClinicalData();
        break;
      case 'dashboard-section':
        if (isAdminUser(user) && latestStaffList.length === 0) {
          await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
        }
        renderDashboardInsights();
        break;
      case 'announcements-section':
        initReportsSection();
        refreshAnnouncementsData();
        break;
      case 'feedback-section':
        initReportsSection();
        refreshFeedbackData();
        break;
      case 'stats-section':
        renderClinicalStats();
        break;
      case 'reports-section':
        initReportsSection();
        const subTab = options.tab || '';
        if (subTab === 'tab-stats') {
          navigateToSection('stats-section');
          return;
        } else if (subTab === 'tab-feedback') {
          navigateToSection('feedback-section');
          return;
        } else if (subTab === 'tab-announcements') {
          navigateToSection('announcements-section');
          return;
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
        initConsultationToolbar();
        break;
      // Add more as needed
    }
    const { tab, pane } = options;

    if (sectionId === 'users-section') {
      initUsersSectionTabs();
      updateUsersSectionTelemetry();
      const defaultPane = isAdminUser(user) ? 'registered-pane' : 'citizens-pane';
      const targetPane = pane || defaultPane;

      if (latestStaffList.length === 0) {
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
      updateUsersSectionTelemetry();
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
      throw new Error('Network error communicating with Supabase (Failed to fetch).\n- Ensure you are serving the frontend over HTTP (not file://).\n- Confirm `SUPABASE_URL` and `SUPABASE_ANON_KEY` in web/src/js/runtime-config.js are correct.\n- Add your app origin to the Supabase project allowed origins (CORS).\n- Ensure the `create_staff_account_admin` function/migration is applied to the database.\nCheck the browser DevTools Network tab for the failing request for more details.');
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
let queueBoardChannel = null;

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

function getStaffInitials(name) {
  if (!name) return 'MD';
  const clean = name.replace(/^Dr\.\s*/i, '').trim();
  const parts = clean.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'MD';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function updateRosterSummaryCounters(staffList = cachedScheduleStaff) {
  if (!Array.isArray(staffList)) return;
  const doctors = staffList.filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'doctor' || r === 'specialist';
  });
  const nurses = staffList.filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'nurse' || r === 'staff';
  });

  const getStatus = (s) => normalizeAvailabilityStatus(s?.availability_status || s?.availabilityStatus);

  const availCount = staffList.filter((s) => getStatus(s) === 'available').length;
  const breakCount = staffList.filter((s) => getStatus(s) === 'on_break').length;
  const offCount = staffList.filter((s) => getStatus(s) === 'unavailable').length;
  const docAvail = doctors.filter((d) => getStatus(d) === 'available').length;
  const nurseAvail = nurses.filter((n) => getStatus(n) === 'available').length;

  const setEl = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = String(val);
  };

  setEl('summary-avail-count', availCount);
  setEl('summary-break-count', breakCount);
  setEl('summary-off-count', offCount);
  setEl('summary-total-count', staffList.length);

  const docBadge = document.getElementById('doctors-count-badge');
  if (docBadge) {
    docBadge.textContent = `${docAvail} of ${doctors.length} on duty`;
    docBadge.className = `dept-count-badge ${docAvail > 0 ? 'has-active' : ''}`;
  }

  const nurseBadge = document.getElementById('nurses-count-badge');
  if (nurseBadge) {
    nurseBadge.textContent = `${nurseAvail} of ${nurses.length} on duty`;
    nurseBadge.className = `dept-count-badge ${nurseAvail > 0 ? 'has-active' : ''}`;
  }
}

function renderCardsSkeleton(container, count = 2) {
  if (!container) return;
  container.innerHTML = Array.from({ length: count }).map(() => `
    <div class="staff-station-card skeleton-row" style="min-height:130px; pointer-events:none;">
      <div style="display:flex; justify-content:space-between; align-items:flex-start;">
        <div style="display:flex; align-items:center; gap:12px;">
          <div class="skeleton-shimmer" style="width:44px; height:44px; border-radius:50%;"></div>
          <div>
            <div class="skeleton-shimmer" style="width:130px; height:15px; border-radius:4px; margin-bottom:6px;"></div>
            <div class="skeleton-shimmer" style="width:170px; height:12px; border-radius:4px;"></div>
          </div>
        </div>
        <div class="skeleton-shimmer" style="width:80px; height:24px; border-radius:9999px;"></div>
      </div>
      <div class="skeleton-shimmer" style="width:100%; height:34px; border-radius:10px; margin-top:10px;"></div>
    </div>
  `).join('');
}

function renderScheduleDoctors(staffList, user) {
  const doctorGrid = document.getElementById('schedule-doctors-grid') || document.getElementById('schedule-doctors-tbody');
  const nurseGrid = document.getElementById('schedule-nurses-grid') || document.getElementById('schedule-nurses-tbody');
  if (!doctorGrid || !nurseGrid) return;

  const doctors = (staffList || []).filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'doctor' || r === 'specialist';
  });
  const nurses = (staffList || []).filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'nurse' || r === 'staff';
  });

  updateRosterSummaryCounters(staffList);

  const buildCards = (list, isDoctor, emptyMsg) => (fragment) => {
    if (!list.length) {
      const emptyDiv = document.createElement('div');
      emptyDiv.style.cssText = 'grid-column: 1 / -1; padding: 28px; text-align: center; color: #94a3b8; font-size: 13.5px; background: #f8fafc; border-radius: 12px; border: 1px dashed #cbd5e1;';
      emptyDiv.textContent = emptyMsg;
      fragment.appendChild(emptyDiv);
      return;
    }

    list.forEach((staff) => {
      const displayName = getDoctorDisplayName(staff);
      const email = staff.email || '—';
      const availabilityStatus = normalizeAvailabilityStatus(
        staff?.availability_status || staff?.availabilityStatus
      );
      const isSelf = user && (
        String(staff.id) === String(user.id) ||
        (staff.email && user.email && String(staff.email).toLowerCase() === String(user.email).toLowerCase())
      );
      const canEditAvailability = isSelf || isAdminUser(user);

      const card = document.createElement('div');
      card.className = `staff-station-card card-${availabilityStatus} ${isSelf ? 'card-is-self' : ''}`;
      card.dataset.staffId = String(staff.id || '');

      const avatarClass = isDoctor ? 'doctor-avatar' : 'nurse-avatar';
      const initials = getStaffInitials(displayName);
      const statusLabel = AVAILABILITY_LABELS[availabilityStatus] || (availabilityStatus === 'on_break' ? 'On Break' : 'Off Duty');

      let actionsHtml = '';
      if (canEditAvailability) {
        actionsHtml = `
          <div class="staff-card-actions">
            <span class="staff-card-actions-label">${isSelf ? 'Your Shift Control' : 'Shift Control (Admin)'}</span>
            <div class="availability-segmented-control" data-staff-id="${staff.id}">
              <button type="button" class="availability-segmented-btn btn-available ${availabilityStatus === 'available' ? 'is-active' : ''}" data-status="available">
                <span class="pill-dot" style="width:7px;height:7px;border-radius:50%;background:currentColor;display:inline-block;"></span> Available
              </button>
              <button type="button" class="availability-segmented-btn btn-break ${availabilityStatus === 'on_break' ? 'is-active' : ''}" data-status="on_break">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M10 2v2m4-2v2m4-2v2"/><path d="M2 8h16v8a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z"/><path d="M18 10h2a2 2 0 0 1 2 2v1a2 2 0 0 1-2 2h-2"/></svg> Break
              </button>
              <button type="button" class="availability-segmented-btn btn-unavailable ${availabilityStatus === 'unavailable' ? 'is-active' : ''}" data-status="unavailable">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg> Off Duty
              </button>
            </div>
          </div>
        `;
      } else {
        actionsHtml = `
          <div class="staff-card-actions">
            <div class="staff-card-footer-info">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> Status updated by staff member
            </div>
          </div>
        `;
      }

      card.innerHTML = `
        <div class="staff-card-header">
          <div class="staff-card-profile">
            <div class="staff-card-avatar ${avatarClass}">
              ${initials}
              <span class="staff-avatar-dot"></span>
            </div>
            <div class="staff-card-meta">
              <div class="staff-card-name-row">
                <span class="staff-card-name">${displayName}</span>
                ${isSelf ? '<span class="self-badge">You</span>' : ''}
              </div>
              <div class="staff-card-email" title="${email}">${email}</div>
            </div>
          </div>
          <span class="station-status-pill status-${availabilityStatus}">
            <span class="pill-dot"></span>
            ${statusLabel}
          </span>
        </div>
        ${actionsHtml}
      `;

      const segmentedControl = card.querySelector('.availability-segmented-control');
      if (segmentedControl) {
        segmentedControl.querySelectorAll('.availability-segmented-btn').forEach((btn) => {
          btn.addEventListener('click', (e) => {
            e.preventDefault();
            handleAvailabilityToggle(staff, btn.dataset.status, segmentedControl);
          });
        });
      }

      fragment.appendChild(card);
    });
  };

  swapContainer(doctorGrid, buildCards(doctors, true, 'No registered doctor accounts found.'));
  swapContainer(nurseGrid, buildCards(nurses, false, 'No registered nurse accounts found.'));
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
  updateRosterSummaryCounters();
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

  // Update parent card styling if present
  const card = toggleGroup.closest('.staff-station-card');
  if (card) {
    card.classList.remove('card-available', 'card-break', 'card-unavailable');
    card.classList.add(`card-${normalized}`);

    const pill = card.querySelector('.station-status-pill');
    if (pill) {
      pill.className = `station-status-pill status-${normalized}`;
      const label = AVAILABILITY_LABELS[normalized] || (normalized === 'on_break' ? 'On Break' : 'Off Duty');
      pill.innerHTML = `<span class="pill-dot"></span> ${label}`;
    }
  }

  updateRosterSummaryCounters();
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
  if (!isFullAccessUser(cachedSessionUser)) return;

  const staffId = staff.id;
  const isSelf = cachedSessionUser && (
    String(staffId) === String(cachedSessionUser.id) || 
    (staff.email && cachedSessionUser.email && String(staff.email).toLowerCase() === String(cachedSessionUser.email).toLowerCase())
  );
  if (!isSelf && !isAdminUser(cachedSessionUser)) {
    showToast('You can only update your own availability.', 'error');
    return;
  }
  const prevStatus = normalizeAvailabilityStatus(staff?.availability_status);
  const normalizedNext = normalizeAvailabilityStatus(nextStatus);
  if (prevStatus === normalizedNext) return;

  applyAvailabilityToggleState(toggleGroup, normalizedNext);
  updateAvailabilityInCaches(staffId, normalizedNext);
  setAvailabilityButtonsLoading(toggleGroup, true);

  try {
    await updateStaffAvailabilityById(staffId, normalizedNext);
    const statusNode = toggleGroup.closest('tr')?.querySelector('td:nth-child(3) span') ||
                       toggleGroup.closest('.staff-station-card')?.querySelector('.station-status-pill');
    if (statusNode) {
      statusNode.className = `station-status-pill status-${normalizedNext}`;
      const label = AVAILABILITY_LABELS[normalizedNext] || (normalizedNext === 'on_break' ? 'On Break' : 'Off Duty');
      statusNode.innerHTML = `<span class="pill-dot"></span> ${label}`;
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
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'staff',
        filter: 'role=in.(doctor,nurse)'
      }, (payload) => {
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
  const doctors = Array.isArray(cachedScheduleDoctors) ? cachedScheduleDoctors : [];

  select.innerHTML = '';
  const defaultOption = document.createElement('option');
  defaultOption.value = '';
  defaultOption.textContent = 'Select Doctor';
  select.appendChild(defaultOption);

  doctors.forEach((doctor) => {
    const option = document.createElement('option');
    option.value = String(doctor.id);
    option.textContent = getDoctorDisplayName(doctor);
    if (selected && String(doctor.id) === selected) {
      option.selected = true;
    }
    select.appendChild(option);
  });
}

async function loadSchedules(user) {
  const doctorGrid = document.getElementById('schedule-doctors-grid') || document.getElementById('schedule-doctors-tbody');
  const nurseGrid = document.getElementById('schedule-nurses-grid') || document.getElementById('schedule-nurses-tbody');
  if (doctorGrid) renderCardsSkeleton(doctorGrid, 2);
  if (nurseGrid) renderCardsSkeleton(nurseGrid, 2);
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
    // Show immediate skeleton animations across the dashboard while data is being fetched
    toggleStatsSkeleton(true);
    toggleUserSkeleton(true);
    toggleChartSkeleton('dashboard-chart', true);

    // Fast-path: authenticate session first
    const sessionUser = await ensureAuthenticatedSession();
    dismissPagePreloader();

    if (!sessionUser) return;

    // Pharmacists have a dedicated dashboard — redirect if they land here
    const sessionRole = String(sessionUser?.role || '').trim().toLowerCase();
    if (sessionRole === 'pharmacist') {
      window.location.replace('./dashboard-pharmacist.html');
      return;
    }

    startPresenceHeartbeat();
    applyRoleAccess(sessionUser);
    populateProfile(sessionUser);

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
        if (!latestAnnouncementsList || latestAnnouncementsList.length === 0) {
          refreshAnnouncementsData();
        }
      };
      tabFeedback.onclick = () => {
        tabAnnouncements.classList.remove('active');
        tabFeedback.classList.add('active');
        tabStats.classList.remove('active');
        announcementsPane.classList.add('hidden');
        feedbackPane.classList.remove('hidden');
        statsPane.classList.add('hidden');
        if (!latestFeedbackList || latestFeedbackList.length === 0 || (Date.now() - lastFeedbackRefreshTime > 60000)) {
          refreshFeedbackData();
        } else {
          renderFeedbackTable();
        }
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

    // Critical dashboard data in parallel (FAST)
    await Promise.all([
      loadClinicalOperationsMetrics(),
      loadPatientData().catch(e => console.warn('Patient data load:', e)),
      loadStaffData().catch(e => console.warn('Staff data load:', e))
    ]);

    if (isAdminUser(sessionUser)) {
      startAdminDashboardAutoRefresh();
    } else {
      stopAdminDashboardAutoRefresh();
    }

    renderDashboardInsights();

    // Defer non-critical background data until after dashboard is already responsive
    setTimeout(() => {
      refreshAnnouncementsData().catch(() => null);
      refreshFeedbackData().catch(() => null);
      subscribeToStaffAvailability();
    }, 1500);

  } catch (error) {
    console.error('Dashboard initialization failed:', error);
  } finally {
    toggleStatsSkeleton(false);
    toggleChartSkeleton('dashboard-chart', false);
    dismissPagePreloader();
  }
}

// Initialize on DOM ready
const startDashboard = async () => {
  dismissPagePreloader();
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

const statActiveStaff = document.getElementById('stat-active-staff');
const statPatients = document.getElementById('stat-citizens');
const statQueueWaiting = document.getElementById('stat-queue-waiting');
const statConsultsToday = document.getElementById('stat-consults-today');
const statVitalsToday = document.getElementById('stat-vitals-today');
const statDispensesToday = document.getElementById('stat-dispenses-today');
const statQueueFoot = document.getElementById('stat-queue-foot');
const clinicalStatsGrid = document.getElementById('clinical-stats-grid');
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
  return `
    <div style="padding: 16px 0; display: flex; flex-direction: column; gap: 12px;">
      <div class="skeleton-shimmer skeleton-title" style="width: 45%; height: 16px; border-radius: 4px;"></div>
      <div class="skeleton-shimmer skeleton-text long" style="height: 12px; border-radius: 4px; width: 100%;"></div>
      <div class="skeleton-shimmer skeleton-text medium" style="height: 12px; border-radius: 4px; width: 85%;"></div>
      <div class="skeleton-shimmer skeleton-text short" style="height: 12px; border-radius: 4px; width: 60%;"></div>
      <div style="margin-top: 12px; display: flex; gap: 12px;">
        <div class="skeleton-shimmer skeleton-rect" style="width: 100px; height: 32px; border-radius: 6px;"></div>
        <div class="skeleton-shimmer skeleton-rect" style="width: 120px; height: 32px; border-radius: 6px;"></div>
      </div>
    </div>
  `;
}

function buildStaffLookup(staffRows) {
  const lookup = new Map();
  if (!Array.isArray(staffRows)) return lookup;
  staffRows.forEach((row) => {
    const id = row?.id;
    if (id !== null && id !== undefined) {
      lookup.set(String(id), row);
    }
  });
  return lookup;
}

function resolveStaffName({ staff, staffId, lookup, fallback = '—' }) {
  if (staff?.first_name || staff?.last_name) {
    return `Dr. ${staff.first_name || ''} ${staff.last_name || ''}`.trim();
  }
  if (lookup && staffId !== null && staffId !== undefined) {
    const match = lookup.get(String(staffId));
    if (match?.first_name || match?.last_name) {
      return `Dr. ${match.first_name || ''} ${match.last_name || ''}`.trim();
    }
  }
  return fallback;
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

    const [consultRes, vitalsRes, rxRes, labRes, staffRes] = await Promise.all([
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
        .select('id,issued_at,patient_identifier,doctor_staff_id,doctor:staff!doctor_staff_id(first_name,last_name),items:prescription_items(*)')
        .or(`patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('issued_at', { ascending: false })
        .limit(50),
      supabase.from('lab_orders')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .or(`patient_citizen_id.eq.${citizenId},patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId},patient_identifier.eq.${citizen.username || ''}`)
        .order('created_at', { ascending: false })
        .limit(50),
      supabase.rpc('list_staff_accounts')
    ]);

    const staffLookup = buildStaffLookup(staffRes?.data || []);

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
            <td class="table-cell" style="white-space:nowrap;">${resolveStaffName({
              staff: r.doctor,
              staffId: r.doctor_staff_id,
              lookup: staffLookup,
              fallback: '—'
            })}</td>
          `;
          tr.addEventListener('click', () => {
            showDataDetail('Consultation Record', {
              'Consultation Date': r.consulted_at ? new Date(r.consulted_at).toLocaleString() : 'None',
              'Attending Doctor': resolveStaffName({
                staff: r.doctor,
                staffId: r.doctor_staff_id,
                lookup: staffLookup,
                fallback: 'None'
              }),
              'Chief Complaint / Symptoms': cleanNone(r.chief_complaint || r.symptoms),
              'Diagnosis': cleanNone(r.diagnosis),
              'History of Present Illness (HPI)': cleanNone(r.hpi),
              'Past Medical History (PMH)': cleanNone(r.pmh),
              'Allergies': cleanNone(r.allergies),
              'Physical Examination': formatPhysicalExam(r.physical_exam),
              'Clinical Notes / Plan': cleanNone(r.notes),
              'Follow-up Checkup Date': r.follow_up_date ? new Date(r.follow_up_date).toLocaleDateString() : 'None'
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
            <td class="table-cell" style="white-space:nowrap;">${(() => {
              if (r.nurse?.first_name || r.nurse?.last_name) {
                return `${r.nurse.first_name || ''} ${r.nurse.last_name || ''}`.trim();
              }
              if (staffLookup && r.nurse_id) {
                const fallbackNurse = staffLookup.get(String(r.nurse_id));
                if (fallbackNurse?.first_name || fallbackNurse?.last_name) {
                  return `${fallbackNurse.first_name || ''} ${fallbackNurse.last_name || ''}`.trim();
                }
              }
              return '—';
            })()}</td>
          `;
          tr.addEventListener('click', () => {
            showDataDetail('Vital Assessment', {
              'Date': r.created_at ? new Date(r.created_at).toLocaleString() : '—',
              'Assessed By': (() => {
                if (r.nurse?.first_name || r.nurse?.last_name) {
                  return `${r.nurse.first_name || ''} ${r.nurse.last_name || ''}`.trim();
                }
                if (staffLookup && r.nurse_id) {
                  const fallbackNurse = staffLookup.get(String(r.nurse_id));
                  if (fallbackNurse?.first_name || fallbackNurse?.last_name) {
                    return `${fallbackNurse.first_name || ''} ${fallbackNurse.last_name || ''}`.trim();
                  }
                }
                return '—';
              })(),
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
          const doctor = resolveStaffName({
            staff: rx.doctor,
            staffId: rx.doctor_staff_id,
            lookup: staffLookup,
            fallback: '—'
          });
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
                <td class="table-cell" style="white-space:nowrap;">${resolveStaffName({
                  staff: r.doctor,
                  staffId: r.doctor_staff_id,
                  lookup: staffLookup,
                  fallback: '—'
                })}</td>
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


const citizenDetailCache = new Map();

async function fetchCitizenFullProfile(userId, fallbackUser = null) {
  const numericId = Number(userId);
  if (!numericId) return fallbackUser;
  if (citizenDetailCache.has(numericId)) {
    return citizenDetailCache.get(numericId);
  }
  try {
    const { supabase } = await loadSupabaseModule();
    const { data } = await supabase
      .from('citizens')
      .select('id,firstname,surname,username,email,contact_number,sex,age,date_of_birth,complete_address,emergency_contact_complete_name,emergency_contact_contact_number,relation,created_at')
      .eq('id', numericId)
      .single();
    const result = data || fallbackUser;
    if (result) citizenDetailCache.set(numericId, result);
    return result;
  } catch (_) {
    return fallbackUser;
  }
}

let citizenActiveFilter = 'all';

function updateUsersSectionTelemetry() {
  const staffCount = latestStaffList.length;
  const onDutyCount = latestStaffList.filter(u => {
    const status = getStaffPresenceStatus(u).toLowerCase();
    return status.includes('duty') || status.includes('active');
  }).length;
  const citizenCount = latestPatientsList.length;
  const consultedCount = (consultations || []).length || Math.min(citizenCount, 28);

  const staffEl = document.getElementById('users-stat-staff');
  const dutyEl = document.getElementById('users-stat-onduty');
  const citizenEl = document.getElementById('users-stat-citizens');
  const consultEl = document.getElementById('users-stat-consulted');
  const tabStaffCount = document.getElementById('tab-count-staff');
  const tabCitizenCount = document.getElementById('tab-count-citizens');

  if (staffEl) staffEl.textContent = String(staffCount);
  if (dutyEl) dutyEl.textContent = String(onDutyCount);
  if (citizenEl) citizenEl.textContent = String(citizenCount);
  if (consultEl) consultEl.textContent = String(consultedCount);
  if (tabStaffCount) tabStaffCount.textContent = String(staffCount);
  if (tabCitizenCount) tabCitizenCount.textContent = String(citizenCount);
}

function initUsersSectionTabs() {
  const tabStaff = document.getElementById('tab-btn-staff');
  const tabCitizens = document.getElementById('tab-btn-citizens');
  const registeredPane = document.getElementById('registered-pane');
  const citizensPane = document.getElementById('citizens-pane');
  const mgmtTitle = document.getElementById('user-mgmt-title');

  if (tabStaff && !tabStaff.dataset.bound) {
    tabStaff.dataset.bound = 'true';
    tabStaff.addEventListener('click', () => {
      tabStaff.classList.add('is-active');
      if (tabCitizens) tabCitizens.classList.remove('is-active');
      if (registeredPane) registeredPane.classList.remove('hidden');
      if (citizensPane) citizensPane.classList.add('hidden');
      if (mgmtTitle) mgmtTitle.textContent = 'Medical Personnel Registry';
    });
  }

  if (tabCitizens && !tabCitizens.dataset.bound) {
    tabCitizens.dataset.bound = 'true';
    tabCitizens.addEventListener('click', async () => {
      tabCitizens.classList.add('is-active');
      if (tabStaff) tabStaff.classList.remove('is-active');
      if (citizensPane) citizensPane.classList.remove('hidden');
      if (registeredPane) registeredPane.classList.add('hidden');
      if (mgmtTitle) mgmtTitle.textContent = 'Citizen Directory';
      if (latestPatientsList.length === 0) {
        await loadPatientData();
      }
    });
  }

  // Staff role filter chips
  const roleChips = document.querySelectorAll('#staff-role-chips .ph-filter-chip');
  roleChips.forEach(chip => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        roleChips.forEach(c => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        const role = chip.dataset.role || '';
        const select = document.getElementById('role-filter');
        if (select) {
          select.value = role;
        }
        applyStaffFinder();
      });
    }
  });

  // Citizen filter chips
  const citizenChips = document.querySelectorAll('#citizen-filter-chips .ph-filter-chip');
  citizenChips.forEach(chip => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        citizenChips.forEach(c => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        citizenActiveFilter = chip.dataset.filter || 'all';
        applyCitizensFinder();
      });
    }
  });
}

function renderCitizensTable(filteredList) {
  if (!patientsTbody) return;
  initUsersSectionTabs();
  updateUsersSectionTelemetry();

  swapContainer(patientsTbody, (fragment) => {
    if (!filteredList.length) {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell" colspan="5" style="text-align:center; padding:36px 16px; color:#94a3b8;">
          <div style="display:flex; justify-content:center; margin-bottom:8px;">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>
            </svg>
          </div>
          <strong style="color:#475569;">No Citizen Records Found</strong><br>
          <span style="font-size:12px; color:#94a3b8;">Try clearing search keywords or selecting another filter.</span>
        </td>
      `;
      fragment.appendChild(tr);
      return;
    }
    filteredList.forEach(user => {
      const row = document.createElement('tr');
      row.className = 'citizen-row';
      row.style.cursor = 'pointer';
      const fullName = [user.firstname, user.surname].filter(Boolean).join(' ') || user.username || 'Citizen Resident';
      const initials = (user.firstname?.[0] || user.username?.[0] || 'C').toUpperCase();
      row.innerHTML = `
        <td class="table-cell">
          <div class="user-avatar-cell">
            <div class="avatar-circle citizen">${initials}</div>
            <div>
              <strong style="font-size:13.5px; color:#0f172a;">${escapeHtml(fullName)}</strong>
              <div style="font-size:11.5px; color:#64748b;">@${escapeHtml(user.username || 'resident')}</div>
            </div>
          </div>
        </td>
        <td class="table-cell" style="font-size:12.5px; color:#475569;">${escapeHtml(user.email || '—')}</td>
        <td class="table-cell">
          <span style="display:inline-flex; align-items:center; gap:5px; font-size:12.5px; color:#475569;">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
            ${escapeHtml(user.contact_number || '—')}
          </span>
        </td>
        <td class="table-cell" style="font-size:12px; color:#64748b;">${formatDateTime(user.created_at)}</td>
        <td class="table-cell" style="text-align:right;">
          <button type="button" class="chip-btn" style="margin:0; padding:5px 14px; font-size:12px; font-weight:700; background:#f0f9ff; color:#0369a1; border:1.5px solid #bae6fd; display:inline-flex; align-items:center; gap:6px; border-radius:9999px;">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
            View Health Dossier
          </button>
        </td>
      `;

      let hoverPrefetchTimer = null;
      row.addEventListener('mouseenter', () => {
        if (!citizenDetailCache.has(Number(user.id))) {
          hoverPrefetchTimer = setTimeout(() => {
            fetchCitizenFullProfile(user.id, user);
          }, 200);
        }
      });
      row.addEventListener('mouseleave', () => {
        if (hoverPrefetchTimer) clearTimeout(hoverPrefetchTimer);
      });

      row.addEventListener('click', async () => {
        const profile = await fetchCitizenFullProfile(user.id, user);
        openCitizenHealthModal(profile || user);
      });
      fragment.appendChild(row);
    });
  });
}

function applyCitizensFinder() {
  const query = String(citizensFinderInput?.value || '').trim().toLowerCase();
  let filtered = latestPatientsList.filter((citizen) => {
    if (!query) return true;
    const fullName = [citizen.firstname, citizen.surname].filter(Boolean).join(' ').toLowerCase();
    const username = String(citizen?.username || '').toLowerCase();
    const email = String(citizen?.email || '').toLowerCase();
    const contact = String(citizen?.contact_number || '').toLowerCase();
    return fullName.includes(query) || username.includes(query) || email.includes(query) || contact.includes(query);
  });

  if (citizenActiveFilter === 'recent') {
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
    filtered = filtered.filter(c => c.created_at && new Date(c.created_at) >= thirtyDaysAgo);
  }

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

  // Update Users Section Title and Tabs if applicable
  const mgmtTitle = document.getElementById('user-mgmt-title');
  const tabStaff = document.getElementById('tab-btn-staff');
  const tabCitizens = document.getElementById('tab-btn-citizens');
  if (paneId === 'registered-pane') {
    if (mgmtTitle) mgmtTitle.textContent = 'Medical Personnel Registry';
    if (tabStaff) tabStaff.classList.add('is-active');
    if (tabCitizens) tabCitizens.classList.remove('is-active');
  } else if (paneId === 'citizens-pane') {
    if (mgmtTitle) mgmtTitle.textContent = 'Citizen Directory';
    if (tabCitizens) tabCitizens.classList.add('is-active');
    if (tabStaff) tabStaff.classList.remove('is-active');
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

const SECTION_BREADCRUMBS = {
  'dashboard-section': 'Doctor Dashboard Overview',
  'schedule-section': 'Availability Schedule',
  'queue-section': 'Live Patient Queue',
  'vitals-section': 'Vitals Triage & Assessment',
  'consultation-section': 'Consultation & Clinical Notes',
  'medicine-section': 'Pharmacy Inventory & Stock',
  'users-section': 'Personnel & Citizen Directory',
  'announcements-section': 'Clinic Announcements',
  'feedback-section': 'Patient & Citizen Feedback',
  'stats-section': 'Clinical Statistics & Analytics',
  'reports-section': 'System Reports & CSV Exports',
  'profile-section': 'Profile & Account Security'
};

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
  if (navMatch) {
    navMatch.classList.add('is-active');
    const parentDropdown = navMatch.closest('.nav-item.dropdown');
    if (parentDropdown) {
      parentDropdown.classList.add('open');
      const menu = parentDropdown.querySelector('.dropdown-menu');
      if (menu) menu.classList.remove('hidden');
      const parentBtn = parentDropdown.querySelector('.nav-btn');
      if (parentBtn) parentBtn.classList.add('is-active');
    }
  }
  setSectionHash(allowedTarget);

  const topbarTitleNode = document.getElementById('main-topbar-title');
  if (topbarTitleNode && SECTION_BREADCRUMBS[allowedTarget]) {
    topbarTitleNode.textContent = SECTION_BREADCRUMBS[allowedTarget];
  }
}





// Reports tabs switching
const tabFeedback = document.getElementById('tab-feedback');
const tabAnnouncements = document.getElementById('tab-announcements');
const tabStats = document.getElementById('tab-stats');
const tabExports = document.getElementById('tab-exports');
const feedbackPane = document.getElementById('feedback-pane');
const announcementsPane = document.getElementById('announcements-pane');
const statsPane = document.getElementById('stats-pane');
const exportsPane = document.getElementById('exports-pane');

if (tabFeedback && tabAnnouncements && feedbackPane && announcementsPane) {
  tabFeedback.addEventListener('click', () => {
    tabFeedback.classList.add('active');
    tabAnnouncements.classList.remove('active');
    if (tabStats) tabStats.classList.remove('active');
    if (tabExports) tabExports.classList.remove('active');
    feedbackPane.classList.remove('hidden');
    announcementsPane.classList.add('hidden');
    if (statsPane) statsPane.classList.add('hidden');
    if (exportsPane) exportsPane.classList.add('hidden');
  });
  
  tabAnnouncements.addEventListener('click', () => {
    tabAnnouncements.classList.add('active');
    tabFeedback.classList.remove('active');
    if (tabStats) tabStats.classList.remove('active');
    if (tabExports) tabExports.classList.remove('active');
    announcementsPane.classList.remove('hidden');
    feedbackPane.classList.add('hidden');
    if (statsPane) statsPane.classList.add('hidden');
    if (exportsPane) exportsPane.classList.add('hidden');
  });
  
  if (tabStats && statsPane) {
    tabStats.addEventListener('click', () => {
      tabStats.classList.add('active');
      tabAnnouncements.classList.remove('active');
      tabFeedback.classList.remove('active');
      if (tabExports) tabExports.classList.remove('active');
      statsPane.classList.remove('hidden');
      announcementsPane.classList.add('hidden');
      feedbackPane.classList.add('hidden');
      if (exportsPane) exportsPane.classList.add('hidden');
    });
  }
  
  if (tabExports && exportsPane) {
    tabExports.addEventListener('click', () => {
      tabExports.classList.add('active');
      tabAnnouncements.classList.remove('active');
      tabFeedback.classList.remove('active');
      if (tabStats) tabStats.classList.remove('active');
      exportsPane.classList.remove('hidden');
      announcementsPane.classList.add('hidden');
      feedbackPane.classList.add('hidden');
      if (statsPane) statsPane.classList.add('hidden');
    });
  }
}

// Section refresh buttons
document.getElementById('announcements-refresh-btn')?.addEventListener('click', async () => {
  await refreshAnnouncementsData();
  showToast('Announcements refreshed.', 'info');
});

document.getElementById('feedback-refresh-btn')?.addEventListener('click', async () => {
  await refreshFeedbackData();
  showToast('Feedback data refreshed.', 'info');
});

document.getElementById('stats-refresh-btn')?.addEventListener('click', async () => {
  await renderClinicalStats();
  showToast('Clinical stats refreshed.', 'info');
});

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
const dataDetailCloseBtn = document.getElementById('data-detail-close-btn');
const dataDetailActions = document.getElementById('data-detail-actions');
const dataDetailTitle = document.getElementById('data-detail-title');
const dataDetailSubtitle = document.getElementById('data-detail-subtitle');
const dataDetailList = document.getElementById('data-detail-list');
const dataDetailCards = document.getElementById('data-detail-cards');
const dataDetailTag = document.getElementById('data-detail-tag');
const dataDetailAvatar = document.getElementById('data-detail-avatar');
const dataDetailStatusPill = document.getElementById('data-detail-status-pill');

function sanitizeText(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function getDetailInitials(name) {
  if (!name) return 'UK';
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function formatDetailValue(value) {
  if (value === null || value === undefined) return '—';
  if (Array.isArray(value)) return value.length ? value.join(', ') : '—';
  if (value instanceof Date) {
    return Number.isNaN(value.getTime())
      ? '—'
      : value.toLocaleString([], {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
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
    dataDetailTag.textContent = tag || 'Detail';
    dataDetailTag.style.display = tag ? 'inline-block' : 'none';
  }

  // Set avatar initials / icon & gradient theme
  if (dataDetailAvatar) {
    const titleLower = (title || '').toLowerCase();
    const tagLower = (tag || '').toLowerCase();

    if (titleLower.includes('consultation') || tagLower.includes('consultation')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #0284c7 0%, #0369a1 100%)';
      dataDetailAvatar.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3v6a6 6 0 0 0 12 0V3"/><path d="M9 17v2a3 3 0 0 0 6 0v-2"/><circle cx="15" cy="17" r="1.5"/></svg>';
    } else if (titleLower.includes('vital') || tagLower.includes('vital')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #e11d48 0%, #be123c 100%)';
      dataDetailAvatar.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>';
    } else if (tagLower.includes('staff') || tagLower.includes('admin') || tagLower.includes('doctor')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #0284c7 0%, #0369a1 100%)';
      dataDetailAvatar.textContent = getDetailInitials(title);
    } else if (tagLower.includes('citizen') || tagLower.includes('patient')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #059669 0%, #047857 100%)';
      dataDetailAvatar.textContent = getDetailInitials(title);
    } else if (tagLower.includes('schedule')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #7c3aed 0%, #6d28d9 100%)';
      dataDetailAvatar.textContent = getDetailInitials(title);
    } else {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #334155 0%, #1e293b 100%)';
      dataDetailAvatar.textContent = getDetailInitials(title);
    }
  }

  // Status pill is hidden per design preference
  if (dataDetailStatusPill) {
    dataDetailStatusPill.style.display = 'none';
  }

  // Filter out any status items
  const displayItems = items.filter(it => (it.label || '').toLowerCase() !== 'status');

  // Populate cards grid
  if (dataDetailCards) {
    dataDetailCards.innerHTML = '';
    if (!displayItems.length) {
      dataDetailCards.innerHTML = '<div class="data-detail-card full-span" style="text-align:center; color:#94a3b8; padding:24px;">No additional information recorded.</div>';
    } else {
      displayItems.forEach(({ label = '', value }) => {
        const formattedVal = formatDetailValue(value);
        const lLower = label.toLowerCase();
        const card = document.createElement('div');
        const isFullSpan = lLower.includes('notes') || lLower.includes('description') || lLower.includes('address') || lLower.includes('symptoms') || String(formattedVal).length > 35;
        card.className = `data-detail-card ${isFullSpan ? 'full-span' : ''}`;

        const isCopyable = (lLower.includes('employee id') || lLower.includes('email') || lLower.includes('username') || lLower.includes('code') || lLower.includes('ticket')) && formattedVal !== '—';
        const isRole = lLower === 'role';
        const isStatus = lLower === 'status';

        let valueContent = '';
        if (isRole) {
          const roleLower = String(formattedVal).toLowerCase();
          let roleColor = 'background:#e0f2fe; color:#0369a1; border:1px solid #bae6fd;';
          if (roleLower.includes('admin')) roleColor = 'background:#fee2e2; color:#b91c1c; border:1px solid #fecaca;';
          else if (roleLower.includes('nurse')) roleColor = 'background:#dcfce7; color:#15803d; border:1px solid #bbf7d0;';
          else if (roleLower.includes('pharmacist')) roleColor = 'background:#f3e8ff; color:#7e22ce; border:1px solid #e9d5ff;';
          valueContent = `<span style="display:inline-block; font-size:12px; font-weight:700; padding:2px 10px; border-radius:6px; ${roleColor}">${sanitizeText(formattedVal)}</span>`;
        } else if (isStatus) {
          const sVal = String(formattedVal).toLowerCase();
          const isOnline = sVal.includes('online') || sVal.includes('active') || sVal.includes('approved') || sVal.includes('serving');
          valueContent = `<span class="badge ${isOnline ? 'badge-success' : 'badge-neutral'}"><span class="status-pulse-dot ${isOnline ? '' : 'offline'}"></span> ${sanitizeText(formattedVal)}</span>`;
        } else {
          valueContent = `<span class="data-detail-value">${sanitizeText(formattedVal)}</span>`;
        }

        const copyBtnHtml = isCopyable
          ? `<button type="button" class="data-detail-copy-btn" title="Copy to clipboard" data-copy="${sanitizeText(formattedVal)}">
               <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
               <span>Copy</span>
             </button>`
          : '';

        card.innerHTML = `
          <div class="data-detail-label">${sanitizeText(label)}</div>
          <div class="data-detail-value-wrapper">
            ${valueContent}
            ${copyBtnHtml}
          </div>
        `;

        const copyBtn = card.querySelector('.data-detail-copy-btn');
        if (copyBtn) {
          copyBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            const copyText = copyBtn.getAttribute('data-copy');
            if (copyText && navigator.clipboard) {
              navigator.clipboard.writeText(copyText).then(() => {
                copyBtn.classList.add('copied');
                copyBtn.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> <span>Copied!</span>`;
                setTimeout(() => {
                  copyBtn.classList.remove('copied');
                  copyBtn.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg> <span>Copy</span>`;
                }, 1800);
              });
            }
          });
        }

        dataDetailCards.appendChild(card);
      });
    }
  }

  // Populate dynamic action buttons in footer
  if (dataDetailActions) {
    dataDetailActions.querySelectorAll('button[data-detail-dynamic="true"]').forEach(btn => btn.remove());
    if (Array.isArray(actions) && actions.length) {
      actions.forEach(action => {
        if (!action || typeof action.onClick !== 'function') return;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.dataset.detailDynamic = 'true';
        btn.className = 'btn-primary-action';
        btn.innerHTML = `
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
          <span>${sanitizeText(action.label || 'Action')}</span>
        `;
        btn.addEventListener('click', (event) => {
          event.preventDefault();
          action.onClick(event);
        });
        dataDetailActions.appendChild(btn);
      });
    }
  }

  dataDetailModal.classList.remove('hidden');
}

function closeDataDetail() {
  if (dataDetailModal) dataDetailModal.classList.add('hidden');
}

if (typeof window !== 'undefined') {
  window.openDataDetail = openDataDetail;
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
if (dataDetailCloseBtn) dataDetailCloseBtn.addEventListener('click', closeDataDetail);
if (dataDetailModal) {
  dataDetailModal.addEventListener('click', (event) => {
    if (event.target === dataDetailModal) closeDataDetail();
  });
}
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (dataDetailModal && !dataDetailModal.classList.contains('hidden')) {
    closeDataDetail();
    return;
  }
  if (notificationPanel && !notificationPanel.classList.contains('hidden')) {
    hideNotificationPanel();
    return;
  }
  if (dialogModal && !dialogModal.classList.contains('hidden')) {
    closeDialogModal({ confirmed: false, values: [] });
    return;
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
let lastFeedbackRefreshTime = 0;

// ═══════════════════════════════════════════════════════════════════════════
// FEEDBACK DATA LOADING AND RENDERING
// ═══════════════════════════════════════════════════════════════════════════

async function refreshFeedbackData() {
  const feedbackTbody = document.getElementById('feedback-tbody');
  if (feedbackTbody && (!latestFeedbackList || latestFeedbackList.length === 0)) {
    renderTableSkeleton(feedbackTbody, 4, 3);
  }
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
    lastFeedbackRefreshTime = Date.now();
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

    lastFeedbackRefreshTime = Date.now();
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
    const rating = feedback.rating ? `<span style="color:#d97706; font-weight:700; font-size:12px; background:#fef3c7; border:1px solid #fde68a; padding:2px 8px; border-radius:9999px;">${feedback.rating}/5</span>` : '—';
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
  if (ratingEl) ratingEl.innerHTML = feedback.rating ? `<span style="color:#d97706; font-weight:700; font-size:13px; background:#fef3c7; border:1px solid #fde68a; padding:3px 10px; border-radius:9999px;">${feedback.rating} out of 5</span>` : '—';
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
  const announcementsTbody = document.getElementById('announcements-tbody');
  if (announcementsTbody) renderTableSkeleton(announcementsTbody, 4, 3);
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

let staffRealtimeChannel = null;

async function setupStaffRealtimeSubscription() {
  if (isDemoMode || staffRealtimeChannel) return;
  try {
    const { supabase } = await loadSupabaseModule();
    staffRealtimeChannel = supabase
      .channel('staff-account-updates')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'staff'
      }, () => {
        if (document.visibilityState === 'visible') {
          loadStaffData().catch(() => {});
        }
      })
      .subscribe();
  } catch (err) {
    console.warn('Staff realtime setup error:', err);
  }
}

function stopAdminDashboardAutoRefresh() {
  if (adminDashboardRefreshTimer) {
    clearInterval(adminDashboardRefreshTimer);
    adminDashboardRefreshTimer = null;
  }
  if (staffRealtimeChannel) {
    try {
      loadSupabaseModule().then(({ supabase }) => supabase.removeChannel(staffRealtimeChannel));
    } catch (_) {}
    staffRealtimeChannel = null;
  }
}

function startAdminDashboardAutoRefresh() {
  setupStaffRealtimeSubscription();
  if (adminDashboardRefreshTimer) return;

  const runRefresh = async () => {
    // Only poll if tab is actively visible to prevent background battery/network drain
    if (document.visibilityState !== 'visible') return;
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
  try {
    if (staffAvailabilityChannel) {
      staffAvailabilityChannel.unsubscribe();
      staffAvailabilityChannel = null;
    }
    if (queueBoardChannel) {
      queueBoardChannel.unsubscribe();
      queueBoardChannel = null;
    }
  } catch (_) {}
  sendOfflinePresenceOnUnload();
  markStaffOfflineBestEffort();
}

let clinicalMetricsCache = {
  waiting: 0,
  serving: 0,
  consultsToday: 0,
  vitalsToday: 0,
  dispensesToday: 0
};

async function loadClinicalOperationsMetrics() {
  try {
    const sb = await getSupabase();
    if (!sb) return;

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayIso = todayStart.toISOString();

    const [waitingRes, servingRes, consultsRes, vitalsRes, rxRes, otcRes] = await Promise.all([
      sb.from('queue_tickets').select('id', { count: 'exact', head: true }).in('status', ['waiting', 'on_call']),
      sb.from('queue_tickets').select('id', { count: 'exact', head: true }).eq('status', 'serving'),
      sb.from('consultations').select('id', { count: 'exact', head: true }).gte('created_at', todayIso),
      sb.from('vital_signs').select('id', { count: 'exact', head: true }).gte('created_at', todayIso),
      sb.from('prescription_item_dispenses').select('id', { count: 'exact', head: true }).gte('dispensed_at', todayIso),
      sb.from('otc_dispenses').select('id', { count: 'exact', head: true }).gte('dispensed_at', todayIso)
    ]);

    const rxCount = (rxRes && typeof rxRes.count === 'number') ? rxRes.count : 0;
    const otcCount = (otcRes && typeof otcRes.count === 'number') ? otcRes.count : 0;

    clinicalMetricsCache = {
      waiting: (waitingRes && typeof waitingRes.count === 'number') ? waitingRes.count : 0,
      serving: (servingRes && typeof servingRes.count === 'number') ? servingRes.count : 0,
      consultsToday: (consultsRes && typeof consultsRes.count === 'number') ? consultsRes.count : 0,
      vitalsToday: (vitalsRes && typeof vitalsRes.count === 'number') ? vitalsRes.count : 0,
      dispensesToday: rxCount + otcCount
    };

    renderClinicalMetrics();
  } catch (err) {
    console.warn('Failed to load clinical operations metrics:', err);
  }
}

function renderClinicalMetrics() {
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

  if (statQueueFoot) {
    if (clinicalMetricsCache.serving > 0) {
      statQueueFoot.textContent = `${clinicalMetricsCache.serving} patient${clinicalMetricsCache.serving > 1 ? 's' : ''} being served`;
      statQueueFoot.className = 'stat-foot stat-success';
    } else if (clinicalMetricsCache.waiting > 0) {
      statQueueFoot.textContent = `${clinicalMetricsCache.waiting} waiting in triage/consult`;
      statQueueFoot.className = 'stat-foot stat-warning';
    } else {
      statQueueFoot.textContent = 'Queue is currently clear';
      statQueueFoot.className = 'stat-foot';
    }
  }
}

function attachClinicalCardNavigation() {
  const queueCard = document.getElementById('stat-card-queue');
  if (queueCard && !queueCard.dataset.navAttached) {
    queueCard.dataset.navAttached = 'true';
    queueCard.addEventListener('click', () => {
      const appointmentsNav = document.querySelector('[data-section="appointments"]') || document.querySelector('[data-section="consultations"]');
      if (appointmentsNav) appointmentsNav.click();
    });
  }

  const consultsCard = document.getElementById('stat-card-consults');
  if (consultsCard && !consultsCard.dataset.navAttached) {
    consultsCard.dataset.navAttached = 'true';
    consultsCard.addEventListener('click', () => {
      const consultNav = document.querySelector('[data-section="consultations"]');
      if (consultNav) consultNav.click();
    });
  }

  const vitalsCard = document.getElementById('stat-card-vitals');
  if (vitalsCard && !vitalsCard.dataset.navAttached) {
    vitalsCard.dataset.navAttached = 'true';
    vitalsCard.addEventListener('click', () => {
      const vitalsNav = document.querySelector('[data-section="vitals"]');
      if (vitalsNav) vitalsNav.click();
    });
  }

  const dispensesCard = document.getElementById('stat-card-dispenses');
  if (dispensesCard && !dispensesCard.dataset.navAttached) {
    dispensesCard.dataset.navAttached = 'true';
    dispensesCard.addEventListener('click', () => {
      const pharmacyNav = document.querySelector('[data-section="pharmacy"]');
      if (pharmacyNav) pharmacyNav.click();
      else window.location.href = 'dashboard-pharmacist.html';
    });
  }

  const patientsCard = document.getElementById('stat-card-patients');
  if (patientsCard && !patientsCard.dataset.navAttached) {
    patientsCard.dataset.navAttached = 'true';
    patientsCard.addEventListener('click', () => {
      const usersNav = document.querySelector('[data-section="users"]');
      if (usersNav) usersNav.click();
    });
  }

  const staffCard = document.getElementById('stat-card-staff');
  if (staffCard && !staffCard.dataset.navAttached) {
    staffCard.dataset.navAttached = 'true';
    staffCard.addEventListener('click', () => {
      const schedNav = document.querySelector('[data-section="schedule"]');
      if (schedNav) schedNav.click();
    });
  }
}

function renderDashboardInsights() {
  const updateMetric = (el, val) => {
    if (!el) return;
    el.textContent = String(val);
    el.classList.remove('data-loaded');
    void el.offsetWidth; // Trigger reflow for smooth re-animation
    el.classList.add('data-loaded');
  };

  updateMetric(statPatients, latestPatientsList.length || 0);

  const activeCount = latestStaffList.filter(isCurrentlyLoggedInStaffAccount).length;
  updateMetric(statActiveStaff, activeCount);

  // Render clinical operations metrics
  renderClinicalMetrics();
  loadClinicalOperationsMetrics().then(() => {
    renderDashboardChart();
  });

  // Attach card navigation
  attachClinicalCardNavigation();
  attachLaunchpadNavigation();

  toggleChartSkeleton('dashboard-chart', false);

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

function attachLaunchpadNavigation() {
  const cards = [
    { id: 'launchpad-call-queue', selector: '[data-section="queue-section"]' },
    { id: 'launchpad-consultation', selector: '[data-section="consultation-section"]' },
    { id: 'launchpad-vitals', selector: '[data-section="vitals-section"]' },
    { id: 'launchpad-pharmacy', selector: '[data-section="medicine-section"]' },
    { id: 'launchpad-citizens', selector: '[data-section="users-section"][data-pane="citizens-pane"]', fallback: '[data-section="users-section"]' },
    { id: 'launchpad-schedule', selector: '[data-section="schedule-section"]' }
  ];

  cards.forEach(({ id, selector, fallback }) => {
    const el = document.getElementById(id);
    if (!el || el.dataset.navAttached) return;
    el.dataset.navAttached = 'true';
    el.addEventListener('click', (e) => {
      e.preventDefault();
      const targetNav = document.querySelector(selector) || (fallback ? document.querySelector(fallback) : null);
      if (targetNav) {
        targetNav.click();
      }
    });
  });
}

function renderDashboardChart() {
  const canvas = document.getElementById('dashboard-chart');
  const emptyNode = document.getElementById('dashboard-chart-empty');
  const legendList = document.getElementById('dashboard-chart-legend');
  if (!canvas || typeof canvas.getContext !== 'function') return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const metrics = [
    { label: 'Consultations', value: clinicalMetricsCache.consultsToday || 0, color: '#0284c7' },
    { label: 'Triage Vitals', value: clinicalMetricsCache.vitalsToday || 0, color: '#10b981' },
    { label: 'Medicines Dispensed', value: clinicalMetricsCache.dispensesToday || 0, color: '#8b5cf6' },
    { label: 'Patients in Queue', value: clinicalMetricsCache.waiting || 0, color: '#f59e0b' }
  ];

  const total = metrics.reduce((sum, metric) => sum + (metric.value || 0), 0);
  const hasData = total > 0;

  if (emptyNode) emptyNode.classList.toggle('hidden', hasData);
  if (legendList) {
    legendList.innerHTML = '';
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
      value.textContent = String(metric.value);
      item.appendChild(value);
      legendList.appendChild(item);
    });
  }

  const baseSize = 260;
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

    const cx = baseSize / 2;
    const cy = baseSize / 2;
    const r = baseSize / 2 - 40;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.strokeStyle = '#e2e8f0';
    ctx.lineWidth = 22;
    ctx.stroke();

    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = '#94a3b8';
    ctx.font = '800 26px Inter, sans-serif';
    ctx.fillText('0', cx, cy - 8);
    ctx.font = '600 11px Inter, sans-serif';
    ctx.fillStyle = '#64748b';
    ctx.fillText('Encounters Today', cx, cy + 14);
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
    radius: baseSize / 2 - 50, // Reduced from -28 to -50 to make the radius smaller and more balanced
    ringWidth: 32 // Slightly thinner for an elegant, premium look
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

  // Use 'butt' to prevent round ends from overlapping adjacent segments, producing a clean separator.
  ctx.lineWidth = ringWidth;
  ctx.lineCap = 'butt';
  ctx.lineJoin = 'round';
  ctx.shadowBlur = 18;
  ctx.shadowColor = 'rgba(15, 23, 42, 0.15)';

  // Elegant subtle gap between segments if multiple segments are present
  const gapAngle = segments.length > 1 ? 0.03 : 0;

  segments.forEach((segment) => {
    const segmentSweep = segment.ratio * Math.PI * 2;
    const drawableSweep = Math.min(segmentSweep, Math.max(totalSweep - consumedSweep, 0));
    if (drawableSweep > gapAngle + 0.001) {
      ctx.beginPath();
      ctx.strokeStyle = segment.color;
      // Subtract half the gap from each end to draw a beautiful centered segment with gaps
      ctx.arc(centerX, centerY, radius, startAngle + gapAngle / 2, startAngle + drawableSweep - gapAngle / 2);
      ctx.stroke();
    }
    startAngle += segmentSweep;
    consumedSweep += segmentSweep;
  });

  ctx.shadowBlur = 0;

  // Perfectly align the inner white circle with the inner boundary of the ring (radius - ringWidth / 2 = 113px)
  const innerRadius = radius - ringWidth / 2;
  ctx.beginPath();
  ctx.fillStyle = '#ffffff';
  ctx.arc(centerX, centerY, innerRadius, 0, Math.PI * 2);
  ctx.fill();
  
  // Sleek subtle inner border
  ctx.strokeStyle = '#e2e8f0';
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // Premium text typography and hierarchy
  ctx.fillStyle = '#0f172a';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = '600 28px "Inter", "Segoe UI", -apple-system, sans-serif';
  ctx.fillText(String(total), centerX, centerY - 8);
  
  ctx.fillStyle = '#64748b';
  ctx.font = '500 11px "Inter", "Segoe UI", -apple-system, sans-serif';
  ctx.fillText('TOTAL ITEMS', centerX, centerY + 14);
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
    .order('created_at', { ascending: false })
    .limit(200);

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
  const patientsTbody = document.getElementById('citizens-tbody');
  if (patientsTbody) {
    renderTableSkeleton(patientsTbody, 5, 5);
  }
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
    updateUsersSectionTelemetry();
    renderDashboardInsights();
}

// --- Vitals Assessment (QR Scanning & Recording) ---
let html5QrcodeScanner = null;
let vitalsInitialized = false;
let activeVitalsQueueTicketId = null;

function setVitalsStationStatus(state = 'ready', text = 'Ready for Intake') {
  const pill = document.getElementById('vitals-station-status');
  if (!pill) return;
  pill.className = `vitals-status-pill ${state}`;
  pill.innerHTML = `<span class="vitals-status-dot"></span> <span>${text}</span>`;
}

async function loadRecentVitals() {
  const tbody = document.getElementById('vitals-recent-tbody');
  if (!tbody) return;

  const today = getManilaTodayStr();
  const todayStart = `${today}T00:00:00+08:00`;

  try {
    const { supabase } = await loadSupabaseModule();
    const { data: vitals, error } = await supabase
      .from('vital_signs')
      .select('id, created_at, blood_pressure, heart_rate, respiratory_rate, temperature, oxygen_saturation, chief_complaint, citizen:citizens(id, firstname, surname, age)')
      .gte('created_at', todayStart)
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) throw error;

    const rows = vitals || [];
    const countEl = document.getElementById('vitals-today-count');
    if (countEl) countEl.textContent = rows.length;

    let normalCount = 0;
    let flaggedCount = 0;

    if (!rows.length) {
      tbody.innerHTML = `
        <tr>
          <td colspan="7" style="text-align:center; padding:36px 16px; color:#94a3b8; font-size:13px;">
            <div style="display:flex; justify-content:center; margin-bottom:8px;">
              <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
              </svg>
            </div>
            <strong style="color:#475569;">No Vitals Recorded Today</strong><br>
            <span style="font-size:12px; color:#94a3b8;">Triaged patients will be logged in this feed as assessments are recorded.</span>
          </td>
        </tr>
      `;
      const normEl = document.getElementById('vitals-stat-normal');
      if (normEl) normEl.textContent = '0';
      const flagEl = document.getElementById('vitals-stat-flagged');
      if (flagEl) flagEl.textContent = '0';
      return;
    }

    tbody.innerHTML = rows.map((v) => {
      const time = v.created_at ? new Date(v.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '—';
      const patientName = v.citizen ? `${v.citizen.firstname} ${v.citizen.surname}` : 'Walk-in Patient';
      
      let isFlagged = false;
      let bpAlert = false;
      let tempAlert = false;

      if (v.blood_pressure) {
        const parts = String(v.blood_pressure).split('/');
        const sys = parseInt(parts[0], 10);
        const dia = parseInt(parts[1], 10);
        if (sys >= 140 || dia >= 90) {
          isFlagged = true;
          bpAlert = true;
        }
      }
      if (v.temperature && Number(v.temperature) >= 37.8) {
        isFlagged = true;
        tempAlert = true;
      }

      if (isFlagged) flaggedCount++; else normalCount++;

      const statusBadge = isFlagged
        ? `<span class="vitals-tag-flagged" title="${bpAlert ? 'Elevated BP ' : ''}${tempAlert ? 'High Temp' : ''}"><span class="chip-dot dot-flagged"></span> Flagged</span>`
        : `<span class="vitals-tag-normal"><span class="chip-dot dot-normal"></span> Normal</span>`;

      return `
        <tr>
          <td style="font-size:12px; font-weight:600; color:#64748b;">${time}</td>
          <td>
            <strong style="color:#0f172a;">${patientName}</strong>
            ${v.citizen?.age ? `<span style="font-size:11px; color:#64748b; margin-left:4px;">(${v.citizen.age}y)</span>` : ''}
          </td>
          <td><span style="font-family:monospace; font-weight:600; ${bpAlert ? 'color:#dc2626; font-weight:700;' : ''}">${v.blood_pressure || '—'}</span></td>
          <td>${v.heart_rate ? `${v.heart_rate} bpm` : '—'}</td>
          <td><span style="${tempAlert ? 'color:#dc2626; font-weight:700;' : ''}">${v.temperature ? `${v.temperature}°C` : '—'}</span></td>
          <td>${v.oxygen_saturation ? `${v.oxygen_saturation}%` : '—'}</td>
          <td>${statusBadge}</td>
        </tr>
      `;
    }).join('');

    const normEl = document.getElementById('vitals-stat-normal');
    if (normEl) normEl.textContent = normalCount;
    const flagEl = document.getElementById('vitals-stat-flagged');
    if (flagEl) flagEl.textContent = flaggedCount;

  } catch (err) {
    console.warn('Error loading recent vitals:', err);
  }
}

function initVitalsSection() {
  const startBtn = document.getElementById('start-scanner-btn');
  const stopBtn = document.getElementById('stop-scanner-btn');
  const statusText = document.getElementById('qr-status');
  const formContainer = document.getElementById('vitals-form-container');
  const vitalsForm = document.getElementById('vitals-form');
  const manualBtn = document.getElementById('manual-entry-btn');
  const selectQueueBtn = document.getElementById('vitals-select-queue-btn');
  const cancelFormBtn = document.getElementById('vitals-cancel-form-btn');

  loadRecentVitals();

  if (!startBtn || !stopBtn) return;

  if (vitalsInitialized) {
    if (vitalsForm && formContainer.classList.contains('hidden') && !html5QrcodeScanner) {
      if (statusText) {
        statusText.textContent = 'Scanner idle';
        statusText.style.color = '';
      }
      setVitalsStationStatus('ready', 'Ready for Intake');
      startBtn.classList.remove('hidden');
      stopBtn.classList.add('hidden');
    }
    return;
  }
  vitalsInitialized = true;

  // Cleanup any previous scanner instance
  if (html5QrcodeScanner) {
    html5QrcodeScanner.clear().catch(console.error);
    html5QrcodeScanner = null;
  }

  startBtn.addEventListener('click', async () => {
    startBtn.classList.add('hidden');
    stopBtn.classList.remove('hidden');
    if (statusText) {
      statusText.textContent = 'Camera active — scanning...';
      statusText.style.color = '#0284c7';
    }
    setVitalsStationStatus('scanning', 'Camera Scanning Active');
    formContainer.classList.add('hidden');

    try {
      html5QrcodeScanner = new Html5Qrcode('reader');
      const config = { fps: 10, qrbox: { width: 250, height: 250 } };

      await html5QrcodeScanner.start(
        { facingMode: 'environment' },
        config,
        async (decodedText) => {
          if (statusText) {
            statusText.textContent = 'QR Code detected!';
            statusText.style.color = '#15803d';
          }
          await stopScanner();
          handleQRDecoded(decodedText);
        },
        () => {
          // Ignore seek errors
        }
      );
    } catch (err) {
      console.error('Scanner start error:', err);
      if (statusText) {
        statusText.textContent = 'Camera access denied or unavailable.';
        statusText.style.color = '#b91c1c';
      }
      setVitalsStationStatus('ready', 'Camera Unavailable');
      startBtn.classList.remove('hidden');
      stopBtn.classList.add('hidden');
    }
  });

  if (manualBtn) {
    manualBtn.addEventListener('click', () => {
      stopScanner();
      setVitalsStationStatus('active', 'Walk-In Intake Active');
      formContainer.classList.remove('hidden');
      vitalsForm.reset();
      document.getElementById('vitals-citizen-id').value = '';
      activeVitalsQueueTicketId = null;
      formContainer.scrollIntoView({ behavior: 'smooth' });
    });
  }

  if (selectQueueBtn) {
    selectQueueBtn.addEventListener('click', () => {
      stopScanner();
      openQueueSelectionModal();
    });
  }

  if (cancelFormBtn) {
    cancelFormBtn.addEventListener('click', () => {
      vitalsForm.reset();
      formContainer.classList.add('hidden');
      setVitalsStationStatus('ready', 'Ready for Intake');
      activeVitalsQueueTicketId = null;
      window.scrollTo({ top: 0, behavior: 'smooth' });
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
    if (statusText) {
      statusText.textContent = 'Scanner idle';
      statusText.style.color = '';
    }
    setVitalsStationStatus('ready', 'Ready for Intake');
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
      if (statusText) {
        statusText.textContent = 'Scanner idle';
        statusText.style.color = '';
      }
      setVitalsStationStatus('ready', 'Ready for Intake');
      activeVitalsQueueTicketId = null;
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

    // Check if it's a queue ticket QR code
    if (decodedText.trim().startsWith('Q-')) {
      statusText.textContent = 'Queue ticket detected. Looking up patient...';
      const { data: ticket, error } = await supabase
        .from('queue_tickets')
        .select(`
          id,
          citizen_id,
          status,
          reason,
          symptoms,
          citizens (
            id,
            username,
            firstname,
            surname,
            age,
            complete_address,
            contact_number
          )
        `)
        .eq('ticket_code', decodedText.trim())
        .maybeSingle();

      if (error) throw error;

      if (!ticket || !ticket.citizens) {
        statusText.textContent = 'Queue ticket or patient profile not found.';
        statusText.style.color = '#b91c1c';
        return;
      }

      if (ticket.status !== 'on_call') {
        statusText.textContent = 'Patient is not yet on call.';
        statusText.style.color = '#ef4444';
        return;
      }

      const citizen = ticket.citizens;
      nameInput.value = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim();
      ageInput.value = citizen.age || '';
      addressInput.value = citizen.complete_address || '';
      contactInput.value = citizen.contact_number || '';
      citizenIdInput.value = citizen.id;

      // Populate complaint/reason from ticket
      const complaintParts = [];
      if (ticket.reason) complaintParts.push(ticket.reason);
      if (ticket.symptoms) complaintParts.push(ticket.symptoms);
      complaintInput.value = complaintParts.join(' - ');

      activeVitalsQueueTicketId = ticket.id; // Store ticket ID!

    } else if (decodedText.includes('NAME:') && decodedText.includes('TICKET:')) {
      // Check if it's our new rich data format
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
          .select('id, citizen_id')
          .eq('ticket_code', data.TICKET)
          .maybeSingle();
        
        if (ticketData) {
          citizenIdInput.value = ticketData.citizen_id;
          activeVitalsQueueTicketId = ticketData.id; // Store ticket ID!
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
  const listContainer = document.getElementById('queue-selection-list');

  modal.classList.remove('hidden');
  listContainer.innerHTML = '<div style="text-align: center; padding: 20px;">Loading active queue...</div>';

  try {
    const { supabase } = await loadSupabaseModule();
    const today = getManilaTodayStr();
    
    // Fetch patients who are in 'waiting' or 'on_call' status for today
    const { data: tickets, error } = await supabase
      .from('queue_tickets')
      .select(`
        id,
        queue_number,
        status,
        reason,
        symptoms,
        citizen_id,
        citizens (
          id,
          firstname,
          surname,
          age,
          complete_address,
          contact_number
        )
      `)
      .eq('queue_date', today)
      .in('status', ['waiting', 'on_call'])
      .order('queue_number', { ascending: true });

    if (error) throw error;

    currentSelectionQueue = tickets || [];
    renderQueueSelectionList(currentSelectionQueue);
  } catch (err) {
    console.error('Error fetching queue for selection:', err);
    listContainer.innerHTML = '<div style="text-align: center; color: #b91c1c; padding: 20px;">Failed to load queue. Please try again.</div>';
  }

  closeBtn.onclick = () => {
    modal.classList.add('hidden');
  };
}

function renderQueueSelectionList(tickets) {
  const listContainer = document.getElementById('queue-selection-list');
  if (!listContainer) return;

  if (tickets.length === 0) {
    listContainer.innerHTML = '<div style="text-align: center; color: #64748b; padding: 20px;">No patients currently waiting in the queue.</div>';
    return;
  }

  listContainer.innerHTML = '';
  tickets.forEach(t => {
    const item = document.createElement('div');
    item.className = 'queue-select-item';
    item.style.cssText = 'display: flex; justify-content: space-between; align-items: center; padding: 12px; border-bottom: 1px solid #e2e8f0; cursor: pointer; transition: background 0.15s;';
    
    const citizen = t.citizens;
    const name = citizen ? `${citizen.firstname} ${citizen.surname}` : 'Walk-in Patient';
    
    item.innerHTML = `
      <div>
        <strong style="font-size: 15px; color: #0284c7;">#${String(t.queue_number).padStart(3, '0')}</strong>
        <span style="font-weight: 600; margin-left: 8px;">${name}</span>
        <span style="font-size: 12px; color: #64748b; margin-left: 6px;">(${t.reason || 'General'})</span>
        <div style="font-size: 11px; color: #94a3b8; text-transform: uppercase; margin-top: 2px;">Status: ${t.status.replace('_', ' ')}</div>
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

  activeVitalsQueueTicketId = ticket.id; // Store ticket ID!

  formContainer.classList.remove('hidden');
  if (statusText) {
    statusText.textContent = `Queue #${String(ticket.queue_number).padStart(3, '0')} loaded`;
    statusText.style.color = '#0284c7';
  }
  setVitalsStationStatus('active', `Triage: #${String(ticket.queue_number).padStart(3, '0')}`);
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

    if (activeVitalsQueueTicketId) {
      payload.queue_ticket_id = Number(activeVitalsQueueTicketId);
    }

    const { error } = await supabase
      .from('vital_signs')
      .insert([payload]);

    if (error) throw error;

    showToast('Vital signs recorded successfully.', 'success');
    activeVitalsQueueTicketId = null;
    document.getElementById('vitals-form').reset();
    document.getElementById('vitals-form-container').classList.add('hidden');
    const qrStat = document.getElementById('qr-status');
    if (qrStat) {
      qrStat.textContent = 'Scanner idle';
      qrStat.style.color = '';
    }
    setVitalsStationStatus('ready', 'Ready for Intake');
    loadRecentVitals();

    if (typeof appointments !== 'undefined' && appointments.loadQueueTickets) {
      await appointments.loadQueueTickets();
    }
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
  const accountsTbody = document.getElementById('accounts-tbody');
  if (accountsTbody) {
    renderTableSkeleton(accountsTbody, 4, 5);
  }
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

  if (accountsTbody) {
    swapContainer(accountsTbody, (fragment) => {
      if (latestStaffList.length === 0) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td class="table-cell" colspan="5" style="text-align:center; padding:32px 16px; color:#94a3b8;">No registered staff accounts found.</td>';
        fragment.appendChild(tr);
        return;
      }

      latestStaffList.forEach(user => {
        const identifier = user.username || user.employee_id || makeDemoId();
        storedAccounts.set(identifier, user);

        const roleValue = user.role ? String(user.role).toLowerCase() : 'staff';
        const roleLabel = roleValue.charAt(0).toUpperCase() + roleValue.slice(1);
        const statusValue = getStaffPresenceStatus(user);
        const isDuty = statusValue.toLowerCase().includes('duty');
        const isBreak = statusValue.toLowerCase().includes('break');
        const dutyClass = isDuty ? 'on-duty' : (isBreak ? 'break' : 'off-duty');

        const initials = (user.username || 'ST').substring(0, 2).toUpperCase();
        const fullName = [user.firstname, user.surname].filter(Boolean).join(' ') || user.username || 'Medical Staff';

        const row = document.createElement('tr');
        row.className = 'account-row';
        row.setAttribute('data-role', roleValue);
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">
            <div class="user-avatar-cell">
              <div class="avatar-circle">${initials}</div>
              <div>
                <strong style="font-size:13.5px; color:#0f172a;">${escapeHtml(fullName)}</strong>
                <div style="font-size:11.5px; color:#64748b;">@${escapeHtml(user.username || '—')}</div>
              </div>
            </div>
          </td>
          <td class="table-cell"><span class="employee-badge">${escapeHtml(user.employee_id || 'EMP-—')}</span></td>
          <td class="table-cell"><span class="staff-role-badge role-${roleValue}">${escapeHtml(roleLabel)}</span></td>
          <td class="table-cell">
            <span class="duty-status-badge ${dutyClass}">
              <span class="duty-dot ${dutyClass}"></span>
              ${escapeHtml(statusValue)}
            </span>
          </td>
          <td class="table-cell" style="text-align:right;">
            <button type="button" class="btn small outline" data-action="view-staff" data-id="${escapeHtml(identifier)}" style="padding:3px 10px; font-size:11.5px; border-radius:9999px;">View Profile</button>
          </td>
        `;
        fragment.appendChild(row);
        attachAccountRowListener(row);
      });
    });

    applyStaffFinder();
    updateUsersSectionTelemetry();
  }

  renderDashboardInsights();
}

// Initial load (after auth check)
let diagnosisChart = null;
let consultsChart = null;

async function renderClinicalStats() {
  toggleChartSkeleton('diagnoses-chart', true);
  toggleChartSkeleton('consults-chart', true);
  const avgTempEl = document.getElementById('avg-temp');
  const hyperEl = document.getElementById('hypertension-count');
  if (avgTempEl) avgTempEl.innerHTML = '<span class="skeleton-shimmer stat-skeleton" aria-hidden="true"></span>';
  if (hyperEl) hyperEl.innerHTML = '<span class="skeleton-shimmer stat-skeleton" aria-hidden="true"></span>';
  try {
    const { supabase } = await loadSupabaseModule();
    
    // 1. Fetch Data (scoped to last 30 days to prevent memory overfetching)
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
    const { data: consults } = await supabase
      .from('consultations')
      .select('diagnosis, consulted_at')
      .gte('consulted_at', thirtyDaysAgo);
    const { data: vitals } = await supabase
      .from('vital_signs')
      .select('temperature, blood_pressure, created_at')
      .gte('created_at', thirtyDaysAgo);

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
  } finally {
    toggleChartSkeleton('diagnoses-chart', false);
    toggleChartSkeleton('consults-chart', false);
  }
}

async function initDashboardData() {
  toggleStatsSkeleton(true);
  toggleChartSkeleton('dashboard-chart', true);
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
    toggleStatsSkeleton(false);
    toggleChartSkeleton('dashboard-chart', false);
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
    if (manualRefreshInFlight) return;
    manualRefreshInFlight = true;
    try {
      toggleStatsSkeleton(true);
      toggleChartSkeleton('dashboard-chart', true);
      if (dashboardActivePreview) renderTableSkeleton(dashboardActivePreview, 4, 3);
      storedAccounts.clear();
      await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
      showToast('Dashboard data refreshed.', 'info');
    } finally {
      manualRefreshInFlight = false;
    }
  });
}

if (refreshAccountsBtn) {
  refreshAccountsBtn.addEventListener('click', async () => {
    if (manualRefreshInFlight) return;
    manualRefreshInFlight = true;
    try {
      storedAccounts.clear();
      await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData(), refreshFeedbackData()]);
      showToast('Account tables refreshed.', 'info');
    } finally {
      manualRefreshInFlight = false;
    }
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

function initConsultationQuickDiagnosis() {
  document.querySelectorAll('.diag-chip').forEach(btn => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = 'true';
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const diagVal = btn.getAttribute('data-diag');
      const diagInput = document.getElementById('consult-diagnosis');
      if (diagInput && diagVal) {
        diagInput.value = diagVal;
        showToast(`Diagnosis applied: ${diagVal}`, 'info');
        
        // Switch to Diagnosis tab so the physician sees the populated field
        const diagTabBtn = document.querySelector('.modal-tab[data-tab="tab-diagnosis"]');
        if (diagTabBtn) {
          diagTabBtn.click();
        }
        diagInput.focus();
      }
    });
  });
}

function initPrescriptionDosagePresets() {
  document.querySelectorAll('.rx-preset-chip').forEach(btn => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = 'true';
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const dosage = btn.getAttribute('data-dosage');
      const sig = btn.getAttribute('data-sig');
      
      const linesContainer = document.getElementById('prescription-lines');
      let lastLine = linesContainer?.lastElementChild;
      if (!lastLine) {
        const addBtn = document.getElementById('add-prescription-line');
        if (addBtn) {
          addBtn.click();
          lastLine = linesContainer?.lastElementChild;
        }
      }
      if (lastLine) {
        const dosageInput = lastLine.querySelector('.rx-dosage-input') || lastLine.querySelector('input[placeholder*="Dosage"]');
        const sigInput = lastLine.querySelector('.rx-instructions-input') || lastLine.querySelector('input[placeholder*="Instructions"]');
        if (dosageInput && dosage) dosageInput.value = dosage;
        if (sigInput && sig) sigInput.value = sig;
        showToast('Prescription dosage shortcut applied.', 'info');
      }
    });
  });
}

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
    const idPart = prefill.patientId ? `<span style="color:#cbd5e1">(${prefill.patientId})</span>` : '—';
    const servicePart = prefill.serviceLabel ? ` &mdash; <em>${prefill.serviceLabel}</em>` : '';
    displayId.innerHTML = `${namePart} ${idPart}${servicePart}`.trim();
  }

  // Store queue ticket id on form for later use
  if (consultationForm) {
    consultationForm.dataset.queueTicketId = prefill.queueTicketId ? String(prefill.queueTicketId) : '';
    consultationForm.dataset.patientName = prefill.patientName || '';
  }

  // Pre-fill fields answerable by "None" when no answers
  const defaultNoneFields = [
    { id: 'consult-pmh', val: prefill.pmh },
    { id: 'consult-allergies', val: prefill.allergies },
    { id: 'consult-immunization', val: prefill.immunization },
    { id: 'consult-social', val: prefill.social },
    { id: 'exam-heent', val: prefill.exam_heent },
    { id: 'exam-chest', val: prefill.exam_chest },
    { id: 'exam-abdomen', val: prefill.exam_abdomen },
    { id: 'exam-extremities', val: prefill.exam_extremities },
    { id: 'exam-others', val: prefill.exam_others },
    { id: 'consult-differential', val: prefill.differential },
    { id: 'consult-lab-orders', val: prefill.lab_orders },
    { id: 'consult-notes', val: prefill.notes }
  ];

  defaultNoneFields.forEach(({ id, val }) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.value = (val && String(val).trim()) ? String(val).trim() : 'None';
    if (!el.dataset.noneBehaviorAttached) {
      el.dataset.noneBehaviorAttached = 'true';
      el.addEventListener('focus', function () {
        if (this.value === 'None') this.select();
      });
      el.addEventListener('blur', function () {
        if (!this.value.trim()) this.value = 'None';
      });
    }
  });

  // Pre-fill HPI from symptoms/reason or default to None
  const hpiInput = document.getElementById('consult-hpi');
  if (hpiInput) {
    const initialHpi = prefill.symptoms || prefill.hpi;
    hpiInput.value = (initialHpi && String(initialHpi).trim()) ? String(initialHpi).trim() : 'None';
    if (!hpiInput.dataset.noneBehaviorAttached) {
      hpiInput.dataset.noneBehaviorAttached = 'true';
      hpiInput.addEventListener('focus', function () {
        if (this.value === 'None') this.select();
      });
      hpiInput.addEventListener('blur', function () {
        if (!this.value.trim()) this.value = 'None';
      });
    }
  }

  // Hide vitals banner initially, then fetch if ticket linked
  const vitalsBanner = document.getElementById('consult-vitals-banner');
  if (vitalsBanner) vitalsBanner.style.display = 'none';
  if (prefill.queueTicketId) {
    loadVitalsForConsultation(Number(prefill.queueTicketId));
  }

  initConsultationTabs();
  initConsultationQuickDiagnosis();
  initPrescriptionDosagePresets();
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
    const allergyBox  = document.getElementById('consult-allergy-alert');
    const allergyText = document.getElementById('consult-allergy-text');
    if (!banner || !grid) return;

    // Check for critical allergy warning
    const allergies = data.allergies || data.drug_allergies || (data.notes && data.notes.toLowerCase().includes('allerg') ? data.notes : null);
    if (allergies && allergyBox && allergyText) {
      allergyText.textContent = allergies;
      allergyBox.classList.remove('hidden');
      const allergyInput = document.getElementById('consult-allergies');
      if (allergyInput && (!allergyInput.value || allergyInput.value === 'None')) {
        allergyInput.value = allergies;
      }
    } else if (allergyBox) {
      allergyBox.classList.add('hidden');
    }

    const vitals = [
      { label: 'BP',   value: data.blood_pressure       ? `${data.blood_pressure} mmHg` : null },
      { label: 'HR',   value: data.heart_rate            ? `${data.heart_rate} bpm`       : null },
      { label: 'Temp', value: data.temperature           ? `${data.temperature} °C`       : null },
      { label: 'RR',   value: data.respiratory_rate      ? `${data.respiratory_rate} bpm` : null },
      { label: 'SpO₂', value: data.oxygen_saturation     ? `${data.oxygen_saturation}%`   : null },
    ].filter(v => v.value);

    if (vitals.length === 0 && !data.chief_complaint) return;

    grid.innerHTML = vitals.map(v => `
      <div class="vitals-mini-card">
        <div class="v-label">${v.label}</div>
        <div class="v-val">${v.value}</div>
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

    // Pre-fill HPI with chief complaint if HPI is empty or None
    const hpiInput = document.getElementById('consult-hpi');
    if (hpiInput && (!hpiInput.value || hpiInput.value === 'None') && data.chief_complaint) {
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

const consultModalCloseIcon = document.getElementById('consult-modal-close-icon');
if (consultModalCloseIcon) {
  consultModalCloseIcon.addEventListener('click', () => closeConsultationModal());
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

let consultActiveFilterRange = 'all';
let consultSearchQuery = '';

function initConsultationToolbar() {
  const searchInput = document.getElementById('consult-search-input');
  if (searchInput && !searchInput.dataset.initialized) {
    searchInput.dataset.initialized = 'true';
    searchInput.addEventListener('input', (e) => {
      consultSearchQuery = e.target.value.trim().toLowerCase();
      renderConsultations();
    });
  }

  const chips = document.querySelectorAll('.consult-preset-chip');
  chips.forEach(chip => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        chips.forEach(c => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        consultActiveFilterRange = chip.dataset.range;
        
        const dateFromInput = document.getElementById('consult-date-from');
        const dateToInput = document.getElementById('consult-date-to');
        const todayStr = getManilaTodayStr();

        if (consultActiveFilterRange === 'today') {
          if (dateFromInput) dateFromInput.value = todayStr;
          if (dateToInput) dateToInput.value = todayStr;
        } else if (consultActiveFilterRange === 'week') {
          const now = new Date();
          const day = now.getDay();
          const diff = now.getDate() - day + (day === 0 ? -6 : 1);
          const monday = new Date(now.setDate(diff));
          if (dateFromInput) dateFromInput.value = monday.toISOString().slice(0, 10);
          if (dateToInput) dateToInput.value = todayStr;
        } else if (consultActiveFilterRange === 'month') {
          const now = new Date();
          const firstDay = new Date(now.getFullYear(), now.getMonth(), 1);
          if (dateFromInput) dateFromInput.value = firstDay.toISOString().slice(0, 10);
          if (dateToInput) dateToInput.value = todayStr;
        } else {
          if (dateFromInput) dateFromInput.value = '';
          if (dateToInput) dateToInput.value = '';
        }
        renderConsultations();
      });
    }
  });

  const clearBtn = document.getElementById('consult-date-clear');
  if (clearBtn && !clearBtn.dataset.bound) {
    clearBtn.dataset.bound = 'true';
    clearBtn.addEventListener('click', () => {
      const dateFromInput = document.getElementById('consult-date-from');
      const dateToInput = document.getElementById('consult-date-to');
      if (dateFromInput) dateFromInput.value = '';
      if (dateToInput) dateToInput.value = '';
      if (searchInput) searchInput.value = '';
      consultSearchQuery = '';
      consultActiveFilterRange = 'all';
      chips.forEach(c => c.classList.toggle('is-active', c.dataset.range === 'all'));
      renderConsultations();
    });
  }

  const sortSelect = document.getElementById('consult-sort-select');
  if (sortSelect && !sortSelect.dataset.bound) {
    sortSelect.dataset.bound = 'true';
    sortSelect.addEventListener('change', renderConsultations);
  }

  const dateFromInput = document.getElementById('consult-date-from');
  const dateToInput = document.getElementById('consult-date-to');
  if (dateFromInput && !dateFromInput.dataset.bound) {
    dateFromInput.dataset.bound = 'true';
    dateFromInput.addEventListener('change', () => {
      chips.forEach(c => c.classList.remove('is-active'));
      renderConsultations();
    });
  }
  if (dateToInput && !dateToInput.dataset.bound) {
    dateToInput.dataset.bound = 'true';
    dateToInput.addEventListener('change', () => {
      chips.forEach(c => c.classList.remove('is-active'));
      renderConsultations();
    });
  }
}

function renderServingQueue() {
  const container = document.getElementById('serving-workstation-container');
  const tableWrap = document.getElementById('serving-queue-table-wrap');
  const tbody = document.getElementById('serving-queue-tbody');
  const statusPill = document.getElementById('consult-desk-status-pill');
  const statusText = document.getElementById('consult-desk-status-text');

  const allowConsult = canConsultPatients();

  // Hard filter to ensure no completed/cancelled tickets ever show up in this active list
  const activeTickets = consultationQueueTickets.filter(c => {
    const status = String(c?.queueStatus || '').trim().toLowerCase();
    return status === 'serving' || status === 'on_call';
  });

  if (!container) return;

  if (activeTickets.length === 0) {
    if (statusPill) statusPill.className = 'consult-desk-pill ready';
    if (statusText) statusText.textContent = 'Station Ready • Waiting for Patient';
    if (tableWrap) tableWrap.classList.add('hidden');

    container.innerHTML = `
      <div class="consult-station-idle">
        <div class="station-idle-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
          </svg>
        </div>
        <div>
          <h4>Physician Station Ready</h4>
          <p>No patient currently called into the consultation room. Waiting for triage arrival or queue dispatch.</p>
        </div>
        <button id="consult-view-queue-btn" type="button" class="chip-btn chip-btn-outline" style="margin-left:auto; display:inline-flex; align-items:center; gap:6px;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
          View Live Queue
        </button>
      </div>
    `;

    const viewQueueBtn = document.getElementById('consult-view-queue-btn');
    if (viewQueueBtn) {
      viewQueueBtn.addEventListener('click', () => {
        showSection('queue-section');
      });
    }
    return;
  }

  // Active patient in station!
  const firstTicket = activeTickets[0];
  const displayName = firstTicket.patientName || firstTicket.patientId || 'Walk-in Patient';
  const queueNum = `#${String(firstTicket.queueNumber || 0).padStart(3, '0')}`;
  
  if (statusPill) statusPill.className = 'consult-desk-pill active';
  if (statusText) statusText.textContent = `Patient in Station: ${queueNum}`;

  const v = firstTicket.vitals || {};
  let vitalsHtml = '';
  if (v.blood_pressure || v.heart_rate || v.temperature || v.oxygen_saturation) {
    const isHighBp = v.blood_pressure && (parseInt(v.blood_pressure.split('/')[0]) >= 140 || parseInt(v.blood_pressure.split('/')[1]) >= 90);
    const isFever = v.temperature && Number(v.temperature) >= 37.8;
    vitalsHtml = `
      <div class="triage-vitals-strip">
        ${v.blood_pressure ? `<span class="triage-vital-pill ${isHighBp ? 'vital-alert' : ''}">BP ${v.blood_pressure}</span>` : ''}
        ${v.heart_rate ? `<span class="triage-vital-pill">HR ${v.heart_rate} bpm</span>` : ''}
        ${v.temperature ? `<span class="triage-vital-pill ${isFever ? 'vital-alert' : ''}">Temp ${v.temperature}°C</span>` : ''}
        ${v.oxygen_saturation ? `<span class="triage-vital-pill">SpO₂ ${v.oxygen_saturation}%</span>` : ''}
      </div>
    `;
  } else {
    vitalsHtml = `
      <div class="triage-vitals-strip">
        <span class="triage-vital-pill" style="color:#64748b;">No pre-consultation vitals recorded yet</span>
      </div>
    `;
  }

  container.innerHTML = `
    <div class="consult-active-call-card">
      <div class="call-card-left">
        <div class="call-card-queue-num">${queueNum}</div>
        <div class="call-card-info">
          <div class="call-card-name-row">
            <span class="call-card-name">${escapeHtml(displayName)}</span>
            <span class="call-card-tag">${escapeHtml(firstTicket.serviceLabel || 'General Consultation')}</span>
            ${firstTicket.age ? `<span style="font-size:12px; color:#64748b; font-weight:600;">${firstTicket.age} yrs</span>` : ''}
            <span style="font-size:12px; color:#64748b;">${firstTicket.patientId ? `(${firstTicket.patientId})` : ''}</span>
          </div>
          <div class="call-card-complaint">
            <strong style="color:#334155;">Chief Complaint:</strong> ${escapeHtml(firstTicket.symptoms || firstTicket.notes || 'Routine general checkup')}
          </div>
          ${vitalsHtml}
        </div>
      </div>
      <div class="call-card-actions">
        ${allowConsult ? `
          <button type="button" class="btn-start-consult" data-action="consult" data-id="${firstTicket.id}">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
            Begin Consultation
          </button>
        ` : '<span style="color:#94a3b8; font-size:13px; font-weight:600;">View Only Access</span>'}
      </div>
    </div>
  `;

  // Bind click on call card button
  const startBtn = container.querySelector('.btn-start-consult');
  if (startBtn) {
    startBtn.addEventListener('click', () => {
      openConsultationModal({
        patientId: firstTicket.patientId || '',
        patientName: firstTicket.patientName || '',
        serviceLabel: firstTicket.serviceLabel || '',
        queueTicketId: firstTicket.queueTicketId || null,
        symptoms: firstTicket.symptoms || '',
        notes: firstTicket.notes || ''
      });
    });
  }

  // If multiple patients are serving, show the secondary table
  if (activeTickets.length > 1 && tableWrap && tbody) {
    tableWrap.classList.remove('hidden');
    tbody.innerHTML = activeTickets.slice(1).map(c => `
      <tr>
        <td style="font-weight:700; color:#0369a1;">#${String(c.queueNumber || 0).padStart(3, '0')}</td>
        <td><strong>${escapeHtml(c.patientName || c.patientId || '—')}</strong></td>
        <td>${escapeHtml(c.serviceLabel || 'General Consultation')}</td>
        <td style="font-size:12px; color:#64748b;">${formatDateTime(c.created_at)}</td>
        <td style="text-align:right;">
          ${allowConsult ? `<button class="btn small" data-action="consult" data-id="${c.id}" style="background:#0369a1; color:#fff;">Consult</button>` : '—'}
        </td>
      </tr>
    `).join('');
  } else if (tableWrap) {
    tableWrap.classList.add('hidden');
  }
}

function renderConsultations() {
  if (!consultationsTbody) return;
  initConsultationToolbar();

  const sortSelect = document.getElementById('consult-sort-select');
  const sortBy = sortSelect ? sortSelect.value : 'date-desc';

  const dateFromInput = document.getElementById('consult-date-from');
  const dateToInput = document.getElementById('consult-date-to');
  const dateFrom = dateFromInput?.value ? new Date(dateFromInput.value + 'T00:00:00') : null;
  const dateTo = dateToInput?.value ? new Date(dateToInput.value + 'T23:59:59') : null;

  const allowPrescribe = canCreatePrescriptions();

  let rows = consultations.slice();

  // Apply search query filter
  if (consultSearchQuery) {
    rows = rows.filter(c => {
      const name = String(c.patientName || '').toLowerCase();
      const id = String(c.patientId || '').toLowerCase();
      const diag = String(c.diagnosis || '').toLowerCase();
      const symptoms = String(c.symptoms || '').toLowerCase();
      return name.includes(consultSearchQuery) || id.includes(consultSearchQuery) || diag.includes(consultSearchQuery) || symptoms.includes(consultSearchQuery);
    });
  }

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
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell" colspan="6" style="text-align:center; padding:36px 16px; color:#94a3b8;">
          <div style="display:flex; justify-content:center; margin-bottom:8px;">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>
            </svg>
          </div>
          <strong style="color:#475569;">No Consultation Records Found</strong><br>
          <span style="font-size:12px; color:#94a3b8;">Try clearing or adjusting your search keywords and date filters.</span>
        </td>
      `;
      fragment.appendChild(tr);
      return;
    }
    rows.forEach(c => {
      const displayName = c.patientName || c.patientId || '—';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell"><strong>${escapeHtml(displayName)}</strong></td>
        <td class="table-cell" style="color:#64748b; font-size:12.5px; font-family:monospace;">${escapeHtml(c.patientId || '—')}</td>
        <td class="table-cell"><span style="font-weight:600; color:#0f172a;">${escapeHtml((c.diagnosis || 'Unspecified').substring(0, 70))}</span></td>
        <td class="table-cell" style="font-size:12px; color:${c.follow_up_date ? '#0284c7' : '#94a3b8'}; font-weight:600;">
          ${c.follow_up_date ? new Date(c.follow_up_date).toLocaleDateString() : 'None Scheduled'}
        </td>
        <td class="table-cell" style="font-size:12px; color:#64748b;">${formatDateTime(c.created_at)}</td>
        <td class="table-cell" style="text-align:right;">
          <div style="display:inline-flex; gap:6px;">
            <button class="btn small" data-action="view" data-id="${c.id}" style="background:#f1f5f9; color:#334155; border:1px solid #cbd5e1; font-weight:600; display:inline-flex; align-items:center; gap:5px;">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
              View
            </button>
            ${allowPrescribe ? `
              <button class="btn small" data-action="prescribe" data-id="${c.id}" style="background:#0284c7; color:#fff; border:none; font-weight:600; display:inline-flex; align-items:center; gap:5px;">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 12h6m-3-3v6"/></svg>
                Prescribe
              </button>
            ` : ''}
          </div>
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
          { label: 'Follow-up Checkup Date', value: c.follow_up_date ? new Date(c.follow_up_date).toLocaleDateString() : 'None Scheduled' },
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
    follow_up_date: item?.follow_up_date || null,
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
    age: item?.citizen?.age || null,
    contactNumber: item?.citizen?.contact_number || null,
    vitals: item?.vital_signs || {},
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

  // Queue ticket code resolution: Q-20260902-MC-001 or QUEUE-123
  if (raw.startsWith('Q-') || raw.startsWith('QUEUE-')) {
    if (typeof tickets !== 'undefined' && Array.isArray(tickets)) {
      const match = tickets.find(t => t.ticket_code === raw || `QUEUE-${t.id}` === raw);
      if (match?.citizen_id) return Number(match.citizen_id);
      if (match?.citizen?.id) return Number(match.citizen.id);
    }
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
    .select('id,patient_identifier,symptoms,diagnosis,notes,follow_up_date,consulted_at,created_at,doctor_staff_id, citizen:citizens(firstname, surname)')
    .order('consulted_at', { ascending: false })
    .limit(200);

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
    .select('id,queue_number,ticket_code,service_label,status,reason,symptoms,created_at,served_at,citizen_id,citizen:citizens(id,firstname,surname,email,age,contact_number)')
    .eq('status', 'serving')
    .order('queue_number', { ascending: true });

  let { data, error } = await query.eq('queue_date', queueDate);

  // Resilience Fallback: If no "serving" tickets for "today" (local), fetch only RECENT active serving tickets (last 24h).
  if (!error && (!data || data.length === 0)) {
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    console.log('No serving tickets for today, attempting fallback to recent serving tickets (last 24h)...');
    const fb = await supabase
      .from('queue_tickets')
      .select('id,queue_number,ticket_code,service_label,status,reason,symptoms,created_at,served_at,citizen_id,citizen:citizens(id,firstname,surname,email,age,contact_number)')
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

  // Also query vitals for these serving tickets if available
  if (data && data.length > 0) {
    const ticketIds = data.map(t => t.id).filter(Boolean);
    if (ticketIds.length > 0) {
      try {
        const { data: vData } = await supabase
          .from('vital_signs')
          .select('queue_ticket_id,citizen_id,blood_pressure,heart_rate,temperature,oxygen_saturation')
          .in('queue_ticket_id', ticketIds);

        if (vData && vData.length > 0) {
          const vMap = {};
          vData.forEach(v => {
            if (v.queue_ticket_id) vMap[v.queue_ticket_id] = v;
          });
          data.forEach(t => {
            t.vital_signs = vMap[t.id] || null;
          });
        }
      } catch (vErr) {
        console.warn('Could not load vitals for serving tickets:', vErr);
      }
    }
  }

  return (data || []).map(mapNowServingQueueRow);
}

async function refreshConsultationData() {
  const servingTbody = document.getElementById('serving-queue-tbody');
  const consultsTbody = document.getElementById('consultations-tbody');
  if (servingTbody) renderTableSkeleton(servingTbody, 5, 2);
  if (consultsTbody) renderTableSkeleton(consultsTbody, 5, 4);
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
        symptoms: cleanNone(document.getElementById('consult-hpi')?.value),
        diagnosis,
        notes: cleanNone(document.getElementById('consult-notes')?.value),
        hpi: cleanNone(document.getElementById('consult-hpi')?.value),
        pmh: cleanNone(document.getElementById('consult-pmh')?.value),
        allergies: cleanNone(document.getElementById('consult-allergies')?.value),
        immunization: cleanNone(document.getElementById('consult-immunization')?.value),
        social: cleanNone(document.getElementById('consult-social')?.value),
        physical_exam: {
          heent: cleanNone(document.getElementById('exam-heent')?.value || document.getElementById('consult-heent')?.value),
          chest: cleanNone(document.getElementById('exam-chest')?.value || document.getElementById('consult-chest')?.value),
          heart: cleanNone(document.getElementById('consult-heart')?.value),
          abdomen: cleanNone(document.getElementById('exam-abdomen')?.value || document.getElementById('consult-abdomen')?.value),
          extremities: cleanNone(document.getElementById('exam-extremities')?.value || document.getElementById('consult-extremities')?.value),
          neurological: cleanNone(document.getElementById('consult-neurological')?.value),
          others: cleanNone(document.getElementById('exam-others')?.value)
        },
        differential: cleanNone(document.getElementById('consult-differential')?.value),
        lab_orders: cleanNone(document.getElementById('consult-lab-orders')?.value),
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
      symptoms: cleanNone(payload.symptoms),
      diagnosis: payload.diagnosis,
      notes: cleanNone(payload.notes),
      hpi: cleanNone(payload.hpi),
      pmh: cleanNone(payload.pmh),
      allergies: cleanNone(payload.allergies),
      immunization_status: cleanNone(payload.immunization),
      social_history: cleanNone(payload.social),
      physical_exam: payload.physical_exam,
      differential_diagnosis: cleanNone(payload.differential),
      lab_orders: cleanNone(payload.lab_orders),
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
    symptoms: cleanNone(payload.symptoms || payload.hpi),
    diagnosis: String(payload.diagnosis || '').trim(),
    notes: cleanNone(payload.notes),
    hpi: cleanNone(payload.hpi || payload.symptoms),
    pmh: cleanNone(payload.pmh),
    allergies: cleanNone(payload.allergies),
    immunization_status: cleanNone(payload.immunization),
    social_history: cleanNone(payload.social),
    physical_exam: payload.physical_exam || {},
    differential_diagnosis: cleanNone(payload.differential),
    lab_orders: cleanNone(payload.lab_orders),
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
    .order('created_at', { ascending: false })
    .limit(200);

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

  // --- Start Drug Allergy Check Safeguard ---
  const patientAllergies = [];

  // Check the active document input for any newly typed/edited allergies
  const currentAllergiesInput = document.getElementById('consult-allergies');
  if (currentAllergiesInput && currentAllergiesInput.value.trim()) {
    const parts = currentAllergiesInput.value.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
    patientAllergies.push(...parts);
  }

  // Fetch historic allergies from past consultations in the database
  if (!isDemoMode && !isApiMode) {
    try {
      const { supabase } = await loadSupabaseModule();
      const citizenId = resolveCitizenIdFromIdentifier(cleanPatientId);
      if (citizenId) {
        const { data: consults } = await supabase
          .from('consultations')
          .select('allergies')
          .eq('patient_citizen_id', citizenId)
          .not('allergies', 'is', null);

        if (consults && consults.length > 0) {
          consults.forEach(c => {
            if (c.allergies) {
              const parts = c.allergies.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
              patientAllergies.push(...parts);
            }
          });
        }
      }
    } catch (err) {
      console.error('Error fetching patient allergies during prescription creation:', err);
    }
  }

  // Remove duplicate entries
  const uniqueAllergies = [...new Set(patientAllergies)];

  // Cross-reference selected medicines against allergies
  if (uniqueAllergies.length > 0) {
    for (const item of normalizedItems) {
      const medName = String(item.name || '').toLowerCase().trim();
      for (const allergy of uniqueAllergies) {
        const allergyTerm = allergy.trim();
        if (allergyTerm && (medName.includes(allergyTerm) || allergyTerm.includes(medName))) {
          throw new Error(`CRITICAL ALLERGY ALERT: The patient has a documented allergy to "${allergyTerm.toUpperCase()}"! You cannot prescribe "${item.name}".`);
        }
      }
    }
  }
  // --- End Drug Allergy Check Safeguard ---

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

  let doctorStaffId = Number(cachedSessionUser?.id) || null;
  if (!doctorStaffId) {
    const session = await ensureAuthenticatedSession().catch(() => null);
    doctorStaffId = Number(session?.id || cachedSessionUser?.id) || null;
  }
  if (!doctorStaffId) {
    throw new Error('Unable to resolve the logged-in doctor account. Please refresh and log in again.');
  }

  const { supabase } = await loadSupabaseModule();
  const headerPayload = {
    consultation_id: Number.isFinite(Number(consultationDbId)) && Number(consultationDbId) > 0 ? Number(consultationDbId) : null,
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

  const itemRows = normalizedItems.map((it) => {
    let medId = it.medicine_id || null;
    if (!medId && Array.isArray(medicines)) {
      const match = medicines.find(m => String(m.name || '').trim().toLowerCase() === String(it.name || '').trim().toLowerCase());
      if (match) medId = match.id;
    }
    const row = {
      prescription_id: headerId,
      medicine_name: it.name,
      quantity: it.qty,
      unit: it.unit || null,
      dosage: it.dosage || null,
      frequency: it.frequency || null,
      duration: it.duration || null,
      instructions: it.instructions || null,
      additional_info: it.additionalInfo || null
    };
    if (medId) row.medicine_id = medId;
    return row;
  });

  let { error: itemsError } = await supabase
    .from('prescription_items')
    .insert(itemRows);

  // If the remote database does not have the medicine_id column yet, retry cleanly without it
  if (itemsError && itemsError.message && itemsError.message.toLowerCase().includes('medicine_id')) {
    console.warn('[Prescription] medicine_id column not found in database schema, falling back to standard schema.');
    const fallbackRows = itemRows.map(({ medicine_id, ...rest }) => rest);
    const { error: retryErr } = await supabase
      .from('prescription_items')
      .insert(fallbackRows);
    itemsError = retryErr;
  }

  if (itemsError) {
    throw new Error(itemsError.message || 'Unable to save prescription items.');
  }

  return { id: `P-${headerId}`, patient: cleanPatientId, items: normalizedItems };
}

let medicineActiveFilter = 'all';

function initMedicineSection() {
  const openAddBtn = document.getElementById('open-add-medicine-btn');
  const addPanel = document.getElementById('medicine-add-panel');
  const cancelAddBtn = document.getElementById('medicine-add-cancel-btn');
  const form = document.getElementById('medicine-form');

  if (openAddBtn && !openAddBtn.dataset.bound) {
    openAddBtn.dataset.bound = 'true';
    openAddBtn.addEventListener('click', () => {
      if (addPanel) addPanel.classList.toggle('hidden');
      const nameInput = document.getElementById('medicine-name-input');
      if (nameInput && !addPanel.classList.contains('hidden')) {
        nameInput.focus();
      }
    });
  }

  if (cancelAddBtn && !cancelAddBtn.dataset.bound) {
    cancelAddBtn.dataset.bound = 'true';
    cancelAddBtn.addEventListener('click', () => {
      if (addPanel) addPanel.classList.add('hidden');
      if (form) form.reset();
    });
  }

  if (form && !form.dataset.bound) {
    form.dataset.bound = 'true';
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = document.getElementById('medicine-name-input')?.value?.trim();
      const desc = document.getElementById('medicine-desc-input')?.value?.trim();
      const qty = parseInt(document.getElementById('medicine-qty-input')?.value, 10) || 0;
      const unit = document.getElementById('medicine-unit-input')?.value?.trim();
      const expiry = document.getElementById('medicine-expiry-input')?.value || null;

      if (!name) {
        showToast('Medicine name is required.', 'warning');
        return;
      }

      try {
        const { supabase } = await loadSupabaseModule();
        const payload = {
          name,
          description: desc || null,
          qty: Math.max(0, qty),
          unit: unit || null,
          expiry_date: expiry,
          created_by_staff_id: Number(cachedSessionUser?.id) || null
        };

        const { error } = await supabase.from('medicines').insert(payload);
        if (error) throw error;

        showToast(`Successfully registered ${name}.`, 'success');
        form.reset();
        if (addPanel) addPanel.classList.add('hidden');
        await refreshMedicineData();
      } catch (err) {
        console.error('Add medicine error:', err);
        showToast('Failed to add medicine. ' + (err.message || ''), 'error');
      }
    });
  }

  // Filter chips
  const filterChips = document.querySelectorAll('.ph-filter-chip');
  filterChips.forEach(chip => {
    if (!chip.dataset.bound) {
      chip.dataset.bound = 'true';
      chip.addEventListener('click', () => {
        filterChips.forEach(c => c.classList.remove('is-active'));
        chip.classList.add('is-active');
        medicineActiveFilter = chip.dataset.filter || 'all';
        renderMedicines();
      });
    }
  });

  // Search input
  const searchInput = document.getElementById('medicine-search-input');
  if (searchInput && !searchInput.dataset.bound) {
    searchInput.dataset.bound = 'true';
    searchInput.addEventListener('input', () => {
      renderMedicines();
    });
  }

  // Sort select
  const sortSelect = document.getElementById('medicine-sort-select');
  if (sortSelect && !sortSelect.dataset.bound) {
    sortSelect.dataset.bound = 'true';
    sortSelect.addEventListener('change', () => {
      renderMedicines();
    });
  }

  // Archive toggle
  const archToggle = document.getElementById('medicine-archived-toggle-btn');
  const archPanel = document.getElementById('medicine-archived-panel');
  if (archToggle && !archToggle.dataset.bound) {
    archToggle.dataset.bound = 'true';
    archToggle.addEventListener('click', async () => {
      isArchivedMedicinesVisible = !isArchivedMedicinesVisible;
      archToggle.innerHTML = isArchivedMedicinesVisible
        ? `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg> Hide Archived`
        : `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg> Show Archived`;
      if (archPanel) archPanel.classList.toggle('hidden', !isArchivedMedicinesVisible);
      if (isArchivedMedicinesVisible) {
        await refreshArchivedMedicineData();
      }
    });
  }

  // Table actions delegation for main medicine table
  const medTbody = document.getElementById('medicine-tbody');
  if (medTbody && !medTbody.dataset.bound) {
    medTbody.dataset.bound = 'true';
    medTbody.addEventListener('click', async (e) => {
      const btn = e.target.closest('button');
      if (!btn) return;
      const action = btn.dataset.action;
      const name = btn.dataset.name;
      if (!action || !name) return;

      if (action === 'add') {
        const input = prompt(`Add stock quantity for "${name}":`, '10');
        const qty = parseInt(input, 10);
        if (qty && qty > 0) {
          try {
            await addMedicineStockByName(name, qty);
            showToast(`Added ${qty} units to ${name}.`, 'success');
            await refreshMedicineData();
          } catch (err) {
            showToast('Failed to add stock.', 'error');
          }
        }
      } else if (action === 'sub') {
        const input = prompt(`Subtract/Dispense stock quantity for "${name}":`, '1');
        const qty = parseInt(input, 10);
        if (qty && qty > 0) {
          try {
            await reduceMedicineStockByName(name, qty);
            showToast(`Dispensed ${qty} units from ${name}.`, 'success');
            await refreshMedicineData();
          } catch (err) {
            showToast('Failed to reduce stock.', 'error');
          }
        }
      } else if (action === 'remove') {
        if (confirm(`Are you sure you want to archive "${name}" from the active dispensary?`)) {
          try {
            await removeMedicineEntryByName(name);
            showToast(`Archived ${name}.`, 'info');
            await Promise.all([refreshMedicineData(), refreshArchivedMedicineData()]);
          } catch (err) {
            showToast('Failed to archive medicine.', 'error');
          }
        }
      }
    });
  }

  // Table actions delegation for archived medicine table
  const archTbody = document.getElementById('medicine-archived-tbody');
  if (archTbody && !archTbody.dataset.bound) {
    archTbody.dataset.bound = 'true';
    archTbody.addEventListener('click', async (e) => {
      const btn = e.target.closest('button');
      if (!btn) return;
      const action = btn.dataset.action;
      const id = btn.dataset.id;
      if (!action || !id) return;

      if (action === 'restore') {
        try {
          await restoreMedicineEntryById(id);
          showToast('Medicine restored to active dispensary.', 'success');
          await Promise.all([refreshMedicineData(), refreshArchivedMedicineData()]);
        } catch (err) {
          showToast('Failed to restore medicine.', 'error');
        }
      } else if (action === 'hard-delete') {
        if (confirm('Permanently delete this medicine record? This action cannot be undone.')) {
          try {
            await permanentlyDeleteArchivedMedicineById(id);
            showToast('Medicine permanently deleted.', 'info');
            await refreshArchivedMedicineData();
          } catch (err) {
            showToast('Failed to delete permanently.', 'error');
          }
        }
      }
    });
  }
}

function renderMedicines() {
  if (!medicineTbody) return;
  initMedicineSection();

  // Update datalist for prescriptions
  const medicineList = document.getElementById('medicine-list');
  if (medicineList) {
    medicineList.innerHTML = medicines.map(m => `<option value="${m.name}">${m.name} (${m.unit || ''})</option>`).join('');
  }

  // Calculate Telemetry across ALL active medicines
  const now = new Date();
  let totalCount = medicines.length;
  let inStockCount = 0;
  let lowStockCount = 0;
  let expiringSoonCount = 0;
  let outCount = 0;

  medicines.forEach(m => {
    const isOut = m.qty <= 0;
    const isLow = m.qty > 0 && m.qty <= 5;
    let isExpired = false;
    let isExpiringSoon = false;

    if (m.expiry_date) {
      const exp = new Date(m.expiry_date);
      const diffDays = Math.ceil((exp - now) / (1000 * 60 * 60 * 24));
      if (diffDays < 0) isExpired = true;
      else if (diffDays <= 90) isExpiringSoon = true;
    }

    if (isExpired || isOut) {
      outCount++;
    } else if (isLow) {
      lowStockCount++;
    } else {
      inStockCount++;
    }

    if (isExpiringSoon && !isExpired) {
      expiringSoonCount++;
    }
  });

  // Update Telemetry metric values
  const totalEl = document.getElementById('ph-stat-total');
  const inStockEl = document.getElementById('ph-stat-instock');
  const lowEl = document.getElementById('ph-stat-low');
  const outEl = document.getElementById('ph-stat-out');

  if (totalEl) totalEl.textContent = String(totalCount);
  if (inStockEl) inStockEl.textContent = String(inStockCount);
  if (lowEl) lowEl.textContent = String(lowStockCount);
  if (outEl) outEl.textContent = String(outCount);

  // Update filter chip counters
  const chipAll = document.getElementById('chip-count-all');
  const chipInStock = document.getElementById('chip-count-instock');
  const chipLow = document.getElementById('chip-count-low');
  const chipExp = document.getElementById('chip-count-expiring');
  const chipOut = document.getElementById('chip-count-out');

  if (chipAll) chipAll.textContent = String(totalCount);
  if (chipInStock) chipInStock.textContent = String(inStockCount);
  if (chipLow) chipLow.textContent = String(lowStockCount);
  if (chipExp) chipExp.textContent = String(expiringSoonCount);
  if (chipOut) chipOut.textContent = String(outCount);

  // Filter based on search query
  const searchQuery = (medicineSearchInput?.value || '').toLowerCase().trim();
  let filtered = medicines.filter(m => 
    m.name.toLowerCase().includes(searchQuery) || 
    (m.description || '').toLowerCase().includes(searchQuery) ||
    (m.unit || '').toLowerCase().includes(searchQuery)
  );

  // Filter based on active filter chip
  if (medicineActiveFilter === 'in_stock') {
    filtered = filtered.filter(m => m.qty > 5 && (!m.expiry_date || new Date(m.expiry_date) >= now));
  } else if (medicineActiveFilter === 'low_stock') {
    filtered = filtered.filter(m => m.qty > 0 && m.qty <= 5);
  } else if (medicineActiveFilter === 'expiring') {
    filtered = filtered.filter(m => {
      if (!m.expiry_date) return false;
      const diffDays = Math.ceil((new Date(m.expiry_date) - now) / (1000 * 60 * 60 * 24));
      return diffDays >= 0 && diffDays <= 90;
    });
  } else if (medicineActiveFilter === 'out_of_stock') {
    filtered = filtered.filter(m => m.qty <= 0 || (m.expiry_date && new Date(m.expiry_date) < now));
  }

  // Sort
  const sortSelect = document.getElementById('medicine-sort-select');
  const sortBy = sortSelect ? sortSelect.value : 'name-asc';

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

  const role = getSessionRole();
  const allowAdjust = canAdjustMedicineInventory(role);
  const allowAddNew = canAddNewMedicine(role);

  // Show register button if user is authorized
  const openAddBtn = document.getElementById('open-add-medicine-btn');
  if (openAddBtn) {
    openAddBtn.style.display = allowAddNew ? 'inline-flex' : 'none';
  }

  swapContainer(medicineTbody, (fragment) => {
    if (!filtered.length) {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="table-cell" colspan="6" style="text-align:center; padding:36px 16px; color:#94a3b8;">
          <div style="display:flex; justify-content:center; margin-bottom:8px;">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7Z"/><path d="m8.5 8.5 7 7"/>
            </svg>
          </div>
          <strong style="color:#475569;">No Medicines Found</strong><br>
          <span style="font-size:12px; color:#94a3b8;">Try clearing search keywords or selecting another status filter.</span>
        </td>
      `;
      fragment.appendChild(tr);
      return;
    }

    filtered.forEach(m => {
      const tr = document.createElement('tr');

      // Status calculation
      const isLowStock = m.qty <= 5 && m.qty > 0;
      const isOutOfStock = m.qty <= 0;
      let isExpired = false;
      let diffDays = null;

      if (m.expiry_date) {
        const exp = new Date(m.expiry_date);
        diffDays = Math.ceil((exp - now) / (1000 * 60 * 60 * 24));
        if (diffDays < 0) isExpired = true;
      }

      let statusHtml = '<span class="ph-filter-chip" style="background:#dcfce7; color:#15803d; border-color:#bbf7d0; font-size:11px; padding:2px 8px;"><span class="chip-dot dot-normal"></span> In Stock</span>';
      if (isExpired) {
        statusHtml = '<span class="ph-filter-chip" style="background:#fee2e2; color:#991b1b; border-color:#fecaca; font-size:11px; padding:2px 8px;"><span class="chip-dot dot-flagged"></span> Expired</span>';
      } else if (isOutOfStock) {
        statusHtml = '<span class="ph-filter-chip" style="background:#fee2e2; color:#991b1b; border-color:#fecaca; font-size:11px; padding:2px 8px;"><span class="chip-dot dot-flagged"></span> Out of Stock</span>';
      } else if (isLowStock) {
        statusHtml = '<span class="ph-filter-chip" style="background:#fef3c7; color:#92400e; border-color:#fde68a; font-size:11px; padding:2px 8px;"><span class="chip-dot" style="background:#f59e0b;"></span> Low Stock</span>';
      }

      // Expiry badge
      let expiryBadge = '<span class="ph-expiry-badge" style="background:#f1f5f9; color:#64748b;">No Expiry Set</span>';
      if (m.expiry_date) {
        const dateStr = new Date(m.expiry_date).toLocaleDateString();
        if (isExpired) {
          expiryBadge = `<span class="ph-expiry-badge expiry-expired">Expired (${dateStr})</span>`;
        } else if (diffDays <= 30) {
          expiryBadge = `<span class="ph-expiry-badge expiry-critical">Critical (${diffDays}d left)</span>`;
        } else if (diffDays <= 90) {
          expiryBadge = `<span class="ph-expiry-badge expiry-warning">Warning (${diffDays}d left)</span>`;
        } else {
          expiryBadge = `<span class="ph-expiry-badge expiry-good">Valid (${dateStr})</span>`;
        }
      }

      // Stock level meter
      const pct = Math.min(100, Math.round((m.qty / 100) * 100));
      let fillClass = 'fill-healthy';
      if (isOutOfStock || isExpired) fillClass = 'fill-empty';
      else if (isLowStock) fillClass = 'fill-low';

      // Auto detect or classify Rx vs OTC based on name or description
      const lowerName = `${m.name} ${m.description || ''}`.toLowerCase();
      const isRx = lowerName.includes('antibiotic') || lowerName.includes('amoxicillin') || lowerName.includes('rx') || lowerName.includes('mefenamic') || lowerName.includes('losartan') || lowerName.includes('metformin');
      const classificationBadge = isRx
        ? '<span class="badge-rx">Rx</span>'
        : '<span class="badge-otc">OTC</span>';

      tr.innerHTML = `
        <td class="table-cell">
          <div style="display:flex; align-items:center; gap:8px;">
            ${classificationBadge}
            <div>
              <strong style="color:#0f172a; font-size:13.5px;">${escapeHtml(m.name)}</strong>
              ${m.description ? `<div style="font-size:11.5px; color:#64748b; margin-top:2px;">${escapeHtml(m.description)}</div>` : ''}
            </div>
          </div>
        </td>
        <td class="table-cell">
          <div class="ph-stock-bar-wrap">
            <div style="display:flex; justify-content:space-between; font-size:12px; font-weight:700;">
              <span style="${m.qty <= 5 ? 'color:#dc2626;' : 'color:#0f172a;'}">${m.qty} ${escapeHtml(m.unit || 'units')}</span>
              <span style="color:#94a3b8; font-size:10.5px; font-weight:500;">/ 100</span>
            </div>
            <div class="ph-stock-bar-track">
              <div class="ph-stock-bar-fill ${fillClass}" style="width:${Math.max(4, pct)}%;"></div>
            </div>
          </div>
        </td>
        <td class="table-cell" style="color:#64748b; font-size:12.5px;">${escapeHtml(m.unit || 'units')}</td>
        <td class="table-cell">${expiryBadge}</td>
        <td class="table-cell">${statusHtml}</td>
        <td class="table-cell" style="text-align:right;">
          ${allowAdjust ? `
            <div style="display:inline-flex; gap:6px;">
              <button type="button" class="btn small" data-action="add" data-name="${escapeHtml(m.name)}" style="background:#f0fdf4; color:#15803d; border:1px solid #bbf7d0; font-weight:600; display:inline-flex; align-items:center; gap:4px; padding:3px 8px;">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                Add
              </button>
              <button type="button" class="btn small" data-action="sub" data-name="${escapeHtml(m.name)}" style="background:#fffbeb; color:#b45309; border:1px solid #fde68a; font-weight:600; display:inline-flex; align-items:center; gap:4px; padding:3px 8px;">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="5" y1="12" x2="19" y2="12"/></svg>
                Dispense
              </button>
              <button type="button" class="btn small" data-action="remove" data-name="${escapeHtml(m.name)}" style="background:#fff1f2; color:#be123c; border:1px solid #fecdd3; font-weight:600; display:inline-flex; align-items:center; gap:4px; padding:3px 8px;">
                <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                Archive
              </button>
            </div>
          ` : '<span style="color:#94a3b8; font-size:12px;">View Only</span>'}
        </td>
      `;

      fragment.appendChild(tr);
    });
  });
}

function mapMedicineRow(item) {
  return {
    id: Number(item?.id) || null,
    name: String(item?.name || '').trim(),
    description: String(item?.description || '').trim(),
    qty: Math.max(0, Number(item?.qty) || 0),
    unit: String(item?.unit || '').trim(),
    expiry_date: item?.expiry_date || null,
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
    .select('id,name,description,qty,unit,expiry_date,archived_at,created_at,updated_at')
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
    .select('id,name,description,qty,unit,expiry_date,archived_at,created_at,updated_at')
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
  const archTbody = document.getElementById('medicine-archived-tbody');
  if (archTbody && (!archivedMedicines || archivedMedicines.length === 0)) {
    renderTableSkeleton(archTbody, 5, 3);
  }
  try {
    archivedMedicines = await listArchivedMedicineData();
  } catch (error) {
    console.error('Failed to refresh archived medicines:', error);
    archivedMedicines = [];
  }
  renderArchivedMedicines();
}

async function refreshMedicineData() {
  const medTbody = document.getElementById('medicine-tbody');
  if (medTbody && (!medicines || medicines.length === 0)) {
    renderTableSkeleton(medTbody, 7, 5);
  }
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
          { label: 'Follow-up Checkup Date', value: entry.follow_up_date ? new Date(entry.follow_up_date).toLocaleDateString() : 'None Scheduled' },
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

let activePatientAllergies = [];

async function openPrescriptionModalForPatient(patientId = '', consultationDbId = null, patientName = '', queueTicketId = null) {
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

  // Load and cache allergies for dynamic client-side alerts
  activePatientAllergies = [];
  const currentAllergiesInput = document.getElementById('consult-allergies');
  if (currentAllergiesInput && currentAllergiesInput.value.trim()) {
    const parts = currentAllergiesInput.value.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
    activePatientAllergies.push(...parts);
  }

  const cleanPatientId = String(patientId || '').trim();
  if (cleanPatientId && !isDemoMode && !isApiMode) {
    try {
      const { supabase } = await loadSupabaseModule();
      const citizenId = resolveCitizenIdFromIdentifier(cleanPatientId);
      if (citizenId) {
        const { data: consults } = await supabase
          .from('consultations')
          .select('allergies')
          .eq('patient_citizen_id', citizenId)
          .not('allergies', 'is', null);

        if (consults && consults.length > 0) {
          consults.forEach(c => {
            if (c.allergies) {
              const parts = c.allergies.split(/[,;\n]+/).map(p => p.trim().toLowerCase()).filter(p => p);
              activePatientAllergies.push(...parts);
            }
          });
        }
      }
    } catch (err) {
      console.error('Error fetching patient allergies:', err);
    }
  }
  activePatientAllergies = [...new Set(activePatientAllergies)];

  // Display allergy banner in prescription modal if allergies exist
  const prescAllergyBanner = document.getElementById('prescription-allergy-banner');
  const prescAllergyText = document.getElementById('prescription-allergy-text');
  if (prescAllergyBanner && prescAllergyText) {
    if (activePatientAllergies.length > 0) {
      prescAllergyBanner.style.display = 'block';
      prescAllergyText.textContent = `Patient is allergic to: ${activePatientAllergies.map(a => a.toUpperCase()).join(', ')}`;
    } else {
      prescAllergyBanner.style.display = 'none';
    }
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
  const medInput = line.querySelector('.pres-med');

  // Inline real-time allergy error message container
  const errorContainer = document.createElement('div');
  errorContainer.style.fontSize = '11px';
  errorContainer.style.fontWeight = '600';
  errorContainer.style.color = '#ef4444';
  errorContainer.style.marginTop = '4px';
  errorContainer.style.display = 'none';
  medInput.parentNode.appendChild(errorContainer);

  const checkAllergy = () => {
    const medName = medInput.value.toLowerCase().trim();
    if (!medName || activePatientAllergies.length === 0) {
      medInput.style.borderColor = '#cbd5e1';
      medInput.style.background = '#ffffff';
      errorContainer.style.display = 'none';
      return;
    }

    let foundAllergy = null;
    for (const allergy of activePatientAllergies) {
      const allergyTerm = allergy.trim();
      if (allergyTerm && (medName.includes(allergyTerm) || allergyTerm.includes(medName))) {
        foundAllergy = allergyTerm;
        break;
      }
    }

    if (foundAllergy) {
      medInput.style.borderColor = '#ef4444';
      medInput.style.background = '#fef2f2';
      errorContainer.textContent = `ALLERGY DETECTED: Patient is allergic to "${foundAllergy.toUpperCase()}"!`;
      errorContainer.style.display = 'block';
    } else {
      medInput.style.borderColor = '#cbd5e1';
      medInput.style.background = '#ffffff';
      errorContainer.style.display = 'none';
    }
  };

  medInput.addEventListener('input', checkAllergy);
  medInput.addEventListener('change', checkAllergy);

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

    // Search for prescription header with joined doctor, consultation, patient, and items
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
        doctor:staff(firstname, surname),
        consultation:consultations(
          patient_citizen_id,
          patient:citizens(firstname, surname)
        ),
        items:prescription_items(*)
      `)
      .eq('prescription_code', prescriptionCode)
      .single();

    if (prescriptionError || !prescriptionData) {
      showToast('Prescription not found', 'error');
      return;
    }

    // Get patient information from joined data
    let patientName = 'Unknown Patient';
    let patientId = prescriptionData.patient_identifier || '-';

    if (prescriptionData.consultation?.patient) {
      const p = prescriptionData.consultation.patient;
      patientName = `${p.firstname || ''} ${p.surname || ''}`.trim() || 'Unknown Patient';
      patientId = prescriptionData.consultation.patient_citizen_id || patientId;
    } else if (prescriptionData.patient_identifier) {
      // Fallback lookup if no consultation link exists
      const { data: citizenData } = await supabase
        .from('citizens')
        .select('firstname, surname')
        .eq('id', prescriptionData.patient_identifier)
        .maybeSingle();

      if (citizenData) {
        patientName = `${citizenData.firstname || ''} ${citizenData.surname || ''}`.trim() || 'Unknown Patient';
      }
    }

    // Prescription items from joined data
    const itemsData = prescriptionData.items || [];

    // Get current stock for each medicine (single batch query)
    const medicineNames = itemsData.map(item => item.medicine_name).filter(Boolean);
    const stockMap = {};
    if (medicineNames.length > 0) {
      const { data: stockData } = await supabase
        .from('medicines')
        .select('name, qty')
        .in('name', medicineNames)
        .is('archived_at', null);

      if (stockData) {
        stockData.forEach(item => {
          stockMap[item.name] = item.qty;
        });
      }
    }

    const docFirst = prescriptionData.doctor?.firstname || prescriptionData.doctor?.first_name || '';
    const docLast = prescriptionData.doctor?.surname || prescriptionData.doctor?.last_name || '';
    const docNameFormatted = [docFirst, docLast].filter(Boolean).join(' ');

    // Store current prescription data
    currentPrescriptionData = {
      ...prescriptionData,
      patientName,
      patientId,
      doctorName: docNameFormatted ? `Dr. ${docNameFormatted}` : 'Unknown Doctor'
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
  } else if (status === 'partial') {
    statusBadge.textContent = 'Partially Dispensed';
    statusBadge.style.background = '#fef9c3';
    statusBadge.style.color = '#854d0e';
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
    const remaining = item.remaining_quantity ?? (item.quantity - (item.dispensed_quantity ?? 0));
    const dispensedQty = item.dispensed_quantity ?? 0;
    const itemFullyDispensed = remaining <= 0;
    const hasStock = item.currentStock >= remaining;
    if (!hasStock && !itemFullyDispensed) hasInsufficientStock = true;

    const isDispensed = status === 'dispensed';
    const isCancelled = status === 'cancelled';
    // Allow selecting undispensed items that have stock; partial rows are still selectable
    const canSelect = !isDispensed && !isCancelled && !itemFullyDispensed && item.currentStock > 0;
    const maxDispense = Math.min(remaining, Math.max(0, item.currentStock));

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
      <td style="text-align:center;">${item.quantity} ${escapeHtml(item.unit || '')}</td>
      <td style="text-align:center;">${dispensedQty}</td>
      <td style="text-align:center;font-weight:600;color:${itemFullyDispensed ? '#16a34a' : '#0891b2'};">${remaining}</td>
      <td>
        <span style="color: ${hasStock ? '#16a34a' : '#dc2626'}; font-weight: 600;">
          ${item.currentStock}
        </span>
      </td>
      <td>
        ${itemFullyDispensed
          ? '<span style="color:#16a34a;">Complete</span>'
          : `<input
              type="number"
              class="pharmacy-dispense-quantity"
              data-index="${index}"
              min="0"
              max="${maxDispense}"
              value="${maxDispense}"
              ${canSelect ? '' : 'disabled'}
              style="width:64px;padding:4px 6px;border:1px solid #cbd5e1;border-radius:6px;text-align:center;"
            >`}
      </td>
      <td>
        ${itemFullyDispensed
          ? '<span style="color: #16a34a; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Done</span>'
          : (dispensedQty > 0
              ? '<span style="color: #d97706; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> Partial</span>'
              : (hasStock
                  ? '<span style="color: #0891b2; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg> Pending</span>'
                  : '<span style="color: #dc2626; font-weight: 600; display: flex; align-items: center; gap: 4px;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg> Insufficient</span>'))}
      </td>
    `;
    tbody.appendChild(row);
  });

  // Show/hide warning message
  const warningDiv = document.getElementById('pharmacy-warning-message');
  if (hasInsufficientStock && (status === 'pending' || status === 'partial')) {
    warningDiv.classList.remove('hidden');
  } else {
    warningDiv.classList.add('hidden');
  }

  // Disable buttons if already fully dispensed or cancelled; keep enabled for pending/partial
  const dispenseSelectedBtn = document.getElementById('pharmacy-dispense-selected-btn');
  const dispenseAllBtn = document.getElementById('pharmacy-dispense-all-btn');
  const cancelBtn = document.getElementById('pharmacy-cancel-prescription-btn');
  const isDispensed = status === 'dispensed';
  const isCancelled = status === 'cancelled';

  if (isDispensed || isCancelled) {
    dispenseSelectedBtn.disabled = true;
    dispenseAllBtn.disabled = true;
    cancelBtn.disabled = isDispensed; // can still cancel a partial
    dispenseSelectedBtn.style.opacity = '0.5';
    dispenseAllBtn.style.opacity = '0.5';
    cancelBtn.style.opacity = isDispensed ? '0.5' : '1';
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

  const selectedItems = [];
  let totalSelectedQty = 0;
  for (const cb of checkboxes) {
    const index = parseInt(cb.dataset.index);
    const item = currentMedicineItems[index];
    const input = document.querySelector(`.pharmacy-dispense-quantity[data-index="${index}"]`);
    const quantity = parseInt(input?.value, 10);
    const remaining = item.remaining_quantity ?? (item.quantity - (item.dispensed_quantity ?? 0));
    const maximum = Math.min(remaining, item.currentStock);
    if (!Number.isInteger(quantity) || quantity < 0 || quantity > maximum) {
      showToast(`Enter a quantity from 0 to ${maximum} for ${item.medicine_name}.`, 'warning');
      return;
    }
    totalSelectedQty += quantity;
    selectedItems.push({ ...item, dispenseQuantity: quantity });
  }

  if (totalSelectedQty === 0) {
    showToast('Please enter a quantity greater than 0 for at least one selected medicine.', 'warning');
    return;
  }

  await dispenseMedicines(selectedItems);
}

async function dispenseAllMedicines() {
  // Only include undispensed items that have sufficient stock
  const availableItems = currentMedicineItems.filter(item => {
    const remaining = item.remaining_quantity ?? (item.quantity - (item.dispensed_quantity ?? 0));
    return remaining > 0 && item.currentStock > 0;
  });
  
  if (availableItems.length === 0) {
    showToast('No medicines available to dispense', 'error');
    return;
  }

  await dispenseMedicines(availableItems);
}

async function dispenseMedicines(items) {
  // Only items with quantity > 0 are dispatched for deduction & event recording
  const itemsToDispense = items.filter(item => (item.dispenseQuantity ?? 1) > 0);
  if (itemsToDispense.length === 0) {
    showToast('No medicines with quantity greater than 0 to dispense', 'warning');
    return;
  }

  if (!confirm(`Are you sure you want to dispense ${itemsToDispense.length} medicine(s)?`)) {
    return;
  }

  // Build per-item payload using remaining_quantity (dispense remaining for selected items)
  const dispensePayload = itemsToDispense.map(item => ({
    prescription_item_id: item.id,
    quantity: item.dispenseQuantity ?? Math.min(
      item.remaining_quantity ?? (item.quantity - (item.dispensed_quantity ?? 0)),
      item.currentStock
    )
  }));

  try {
    const { supabase } = await loadSupabaseModule();

    const { data, error } = await supabase.rpc('dispense_prescription_items', {
      p_prescription_code: currentPrescriptionData.prescription_code,
      p_items: dispensePayload
    });

    if (error) {
      console.error('Error dispensing medicines:', error);
      showToast(error.message || 'Error dispensing medicines', 'error');
      return;
    }

    if (data?.error) {
      showToast(data.error, 'error');
      return;
    }

    const newStatus = data?.dispensing_status || 'dispensed';
    const label = newStatus === 'partial' ? 'partially dispensed' : 'fully dispensed';
    showToast(`Prescription ${newStatus === 'partial' ? 'partially' : 'successfully'} dispensed (${items.length} item(s))`, 'success');

    // Refresh the display with updated data from DB
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
// Pharmacy module disabled - pharmacists use dedicated dashboard
// if (document.readyState === 'loading') {
//   document.addEventListener('DOMContentLoaded', initPharmacyModule);
// } else {
//   initPharmacyModule();
// }

// --- Vital Signs Assessment Modal & Real-Time Risk Engine ---
const vaModal = document.getElementById('vital-assessment-modal');
const vaForm = document.getElementById('vital-assessment-form');

function evaluateVitalsRisk() {
  // 1. Blood Pressure Risk
  const bpInput = document.getElementById('va-bp');
  const bpBadge = document.getElementById('va-bp-badge');
  if (bpInput && bpBadge) {
    const val = bpInput.value.trim();
    if (val && val.includes('/')) {
      const [sysStr, diaStr] = val.split('/');
      const sys = parseInt(sysStr, 10);
      const dia = parseInt(diaStr, 10);
      if (!isNaN(sys) && !isNaN(dia)) {
        bpBadge.className = 'vital-risk-badge';
        if (sys >= 180 || dia >= 120) {
          bpBadge.classList.add('vital-risk-crisis');
          bpBadge.textContent = 'Hypertensive Crisis';
        } else if (sys >= 140 || dia >= 90) {
          bpBadge.classList.add('vital-risk-stage2');
          bpBadge.textContent = 'Stage 2 HTN Alert';
        } else if (sys >= 130 || dia >= 80) {
          bpBadge.classList.add('vital-risk-stage1');
          bpBadge.textContent = 'Stage 1 HTN';
        } else if (sys >= 120 && dia < 80) {
          bpBadge.classList.add('vital-risk-elevated');
          bpBadge.textContent = 'Elevated BP';
        } else if (sys < 120 && dia < 80 && sys >= 90 && dia >= 60) {
          bpBadge.classList.add('vital-risk-normal');
          bpBadge.textContent = 'Normal BP';
        } else if (sys < 90 || dia < 60) {
          bpBadge.classList.add('vital-risk-hypo');
          bpBadge.textContent = 'Hypotension';
        }
      } else {
        bpBadge.classList.add('hidden');
      }
    } else {
      bpBadge.classList.add('hidden');
    }
  }

  // 2. Heart Rate Risk
  const hrInput = document.getElementById('va-hr');
  const hrBadge = document.getElementById('va-hr-badge');
  if (hrInput && hrBadge) {
    const hr = parseFloat(hrInput.value);
    if (!isNaN(hr) && hr > 0) {
      hrBadge.className = 'vital-risk-badge';
      if (hr > 100) {
        hrBadge.classList.add('vital-risk-tachy');
        hrBadge.textContent = 'Tachycardia (>100 bpm)';
      } else if (hr < 60) {
        hrBadge.classList.add('vital-risk-brady');
        hrBadge.textContent = 'Bradycardia (<60 bpm)';
      } else {
        hrBadge.classList.add('vital-risk-normal');
        hrBadge.textContent = 'Normal Pulse';
      }
    } else {
      hrBadge.classList.add('hidden');
    }
  }

  // 3. Respiratory Rate Risk
  const rrInput = document.getElementById('va-rr');
  const rrBadge = document.getElementById('va-rr-badge');
  if (rrInput && rrBadge) {
    const rr = parseFloat(rrInput.value);
    if (!isNaN(rr) && rr > 0) {
      rrBadge.className = 'vital-risk-badge';
      if (rr > 20) {
        rrBadge.classList.add('vital-risk-tachy');
        rrBadge.textContent = 'Tachypnea (>20 bpm)';
      } else if (rr < 12) {
        rrBadge.classList.add('vital-risk-brady');
        rrBadge.textContent = 'Bradypnea (<12 bpm)';
      } else {
        rrBadge.classList.add('vital-risk-normal');
        rrBadge.textContent = 'Normal RR';
      }
    } else {
      rrBadge.classList.add('hidden');
    }
  }

  // 4. Temperature Risk
  const tempInput = document.getElementById('va-temp');
  const tempBadge = document.getElementById('va-temp-badge');
  if (tempInput && tempBadge) {
    const temp = parseFloat(tempInput.value);
    if (!isNaN(temp) && temp > 0) {
      tempBadge.className = 'vital-risk-badge';
      if (temp >= 38.0) {
        tempBadge.classList.add('vital-risk-fever');
        tempBadge.textContent = 'High Fever (≥38.0°C)';
      } else if (temp >= 37.5) {
        tempBadge.classList.add('vital-risk-elevated');
        tempBadge.textContent = 'Low-Grade Fever';
      } else if (temp < 35.5) {
        tempBadge.classList.add('vital-risk-hypo');
        tempBadge.textContent = 'Hypothermia Alert';
      } else {
        tempBadge.classList.add('vital-risk-normal');
        tempBadge.textContent = 'Afebrile (Normal)';
      }
    } else {
      tempBadge.classList.add('hidden');
    }
  }

  // 5. Oxygen Saturation Risk
  const spo2Input = document.getElementById('va-spo2');
  const spo2Badge = document.getElementById('va-spo2-badge');
  if (spo2Input && spo2Badge) {
    const spo2 = parseFloat(spo2Input.value);
    if (!isNaN(spo2) && spo2 > 0) {
      spo2Badge.className = 'vital-risk-badge';
      if (spo2 < 90) {
        spo2Badge.classList.add('vital-risk-hypoxia');
        spo2Badge.textContent = 'Critical Hypoxia (<90%)';
      } else if (spo2 < 95) {
        spo2Badge.classList.add('vital-risk-stage2');
        spo2Badge.textContent = 'Low SpO₂ (Hypoxia)';
      } else {
        spo2Badge.classList.add('vital-risk-normal');
        spo2Badge.textContent = 'Normal SpO₂ (≥95%)';
      }
    } else {
      spo2Badge.classList.add('hidden');
    }
  }

  // 6. Anthropometrics & Body Mass Index (BMI)
  const heightInput = document.getElementById('va-height');
  const weightInput = document.getElementById('va-weight');
  const bmiValEl = document.getElementById('va-bmi-value');
  const bmiBadge = document.getElementById('va-bmi-badge');
  if (heightInput && weightInput && bmiValEl && bmiBadge) {
    const h = parseFloat(heightInput.value);
    const w = parseFloat(weightInput.value);
    if (!isNaN(h) && !isNaN(w) && h > 40 && w > 2) {
      const hm = h / 100;
      const bmi = w / (hm * hm);
      bmiValEl.textContent = bmi.toFixed(1);
      bmiBadge.className = 'bmi-category-badge';
      if (bmi < 18.5) {
        bmiBadge.classList.add('bmi-underweight');
        bmiBadge.textContent = 'Underweight';
      } else if (bmi <= 24.9) {
        bmiBadge.classList.add('bmi-normal');
        bmiBadge.textContent = 'Normal Weight';
      } else if (bmi <= 29.9) {
        bmiBadge.classList.add('bmi-overweight');
        bmiBadge.textContent = 'Overweight';
      } else {
        bmiBadge.classList.add('bmi-obese');
        bmiBadge.textContent = 'Obese';
      }
      bmiBadge.classList.remove('hidden');
    } else {
      bmiValEl.textContent = '—';
      bmiBadge.classList.add('hidden');
    }
  }
}

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

  // Wire real-time risk assessment input listeners
  ['va-bp', 'va-hr', 'va-rr', 'va-temp', 'va-spo2', 'va-height', 'va-weight'].forEach(id => {
    const el = document.getElementById(id);
    if (el && !el.dataset.riskBound) {
      el.addEventListener('input', evaluateVitalsRisk);
      el.dataset.riskBound = 'true';
    }
  });

  // Load and display patient symptoms & reason submitted during queue entry
  const symptomsSection = document.getElementById('va-patient-symptoms-section');
  const symptomsDisplay = document.getElementById('va-patient-symptoms-display');
  if (symptomsSection && symptomsDisplay) {
    let detailHtml = '';
    if (ticket.reason) {
      detailHtml += `<div style="margin-bottom:6px;"><strong>Reason for Visit:</strong><br/><span style="color:#2d3748;">${ticket.reason}</span></div>`;
    }
    if (ticket.symptoms) {
      detailHtml += `<div><strong>Symptom Description:</strong><br/><span style="color:#2d3748;">${ticket.symptoms}</span></div>`;
    }
    if (detailHtml) {
      symptomsDisplay.innerHTML = detailHtml;
      symptomsSection.style.display = 'block';
    } else {
      symptomsSection.style.display = 'none';
    }
  }

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
      // New assessment: pre-fill chief complaint with reason + symptoms
      if (document.getElementById('va-chief-complaint')) {
        let combined = '';
        if (ticket.reason) combined += ticket.reason;
        if (ticket.symptoms) {
          if (combined) combined += ': ';
          combined += ticket.symptoms;
        }
        document.getElementById('va-chief-complaint').value = combined || '';
      }
    }
  } catch (err) { console.warn('Error checking existing vitals:', err); }
  
  evaluateVitalsRisk();
  vaModal.classList.remove('hidden');
  vaModal.style.display = 'flex';
}

function closeVitalAssessmentModal() {
  if (vaModal) { vaModal.classList.add('hidden'); vaModal.style.display = 'none'; }
}

if (vaForm) {
  // Prevent typing minus or plus signs in numeric vital inputs to block negative numbers
  const numericVitals = vaForm.querySelectorAll('input[type="number"]');
  numericVitals.forEach(input => {
    input.addEventListener('keydown', (e) => {
      if (e.key === '-' || e.key === '+') {
        e.preventDefault();
      }
    });
  });

  vaForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const submitBtn = vaForm.querySelector('button[type="submit"]');
    const ticketId = document.getElementById('va-queue-ticket-id')?.value;
    const citizenId = document.getElementById('va-citizen-id')?.value;
    const complaint = document.getElementById('va-chief-complaint')?.value;
    if (!ticketId) { showToast('Missing queue ticket reference.', 'error'); return; }

    // Retrieve input values for validation
    const bp = document.getElementById('va-bp')?.value?.trim();
    const hrVal = document.getElementById('va-hr')?.value?.trim();
    const rrVal = document.getElementById('va-rr')?.value?.trim();
    const tempVal = document.getElementById('va-temp')?.value?.trim();
    const spo2Val = document.getElementById('va-spo2')?.value?.trim();

    // 1. Temperature Validation (No under 30, no negative, valid clinical range)
    if (tempVal !== undefined && tempVal !== null && tempVal !== '') {
      const temp = parseFloat(tempVal);
      if (isNaN(temp)) {
        showToast('Temperature must be a valid number.', 'warning');
        return;
      }
      if (temp < 0) {
        showToast('Temperature cannot be negative.', 'warning');
        return;
      }
      if (temp < 30.0) {
        showToast('Temperature cannot be under 30.0°C.', 'warning');
        return;
      }
      if (temp > 45.0) {
        showToast('Temperature cannot exceed 45.0°C.', 'warning');
        return;
      }
    }

    // 2. Heart Rate Validation (No negative, positive clinical limit)
    if (hrVal !== undefined && hrVal !== null && hrVal !== '') {
      const hr = parseInt(hrVal, 10);
      if (isNaN(hr)) {
        showToast('Heart Rate must be a valid number.', 'warning');
        return;
      }
      if (hr < 0) {
        showToast('Heart Rate cannot be negative.', 'warning');
        return;
      }
      if (hr > 300) {
        showToast('Heart Rate cannot exceed 300 bpm.', 'warning');
        return;
      }
    }

    // 3. Respiratory Rate Validation (No negative, positive clinical limit)
    if (rrVal !== undefined && rrVal !== null && rrVal !== '') {
      const rr = parseInt(rrVal, 10);
      if (isNaN(rr)) {
        showToast('Respiratory Rate must be a valid number.', 'warning');
        return;
      }
      if (rr < 0) {
        showToast('Respiratory Rate cannot be negative.', 'warning');
        return;
      }
      if (rr > 100) {
        showToast('Respiratory Rate cannot exceed 100 bpm.', 'warning');
        return;
      }
    }

    // 4. Oxygen Saturation (SpO2) Validation (No negative, 0-100%)
    if (spo2Val !== undefined && spo2Val !== null && spo2Val !== '') {
      const spo2 = parseInt(spo2Val, 10);
      if (isNaN(spo2)) {
        showToast('Oxygen Saturation must be a valid number.', 'warning');
        return;
      }
      if (spo2 < 0) {
        showToast('Oxygen Saturation cannot be negative.', 'warning');
        return;
      }
      if (spo2 > 100) {
        showToast('Oxygen Saturation cannot exceed 100%.', 'warning');
        return;
      }
    }

    // 5. Blood Pressure Validation (No negative, Systolic/Diastolic format)
    if (bp !== undefined && bp !== null && bp !== '') {
      if (bp.includes('-')) {
        showToast('Blood Pressure values cannot be negative.', 'warning');
        return;
      }
      const bpPattern = /^\d{2,3}\/\d{2,3}$/;
      if (!bpPattern.test(bp)) {
        showToast('Blood Pressure must be in format Systolic/Diastolic (e.g. 120/80).', 'warning');
        return;
      }
    }

    setLoading(submitBtn, true);
    try {
      const user = await ensureAuthenticatedSession();
      const { supabase } = await loadSupabaseModule();
      const rpcPayload = {
        p_queue_ticket_id: Number(ticketId),
        p_citizen_id: citizenId ? Number(citizenId) : null,
        p_chief_complaint: complaint || 'General Checkup',
        p_blood_pressure: bp || null,
        p_heart_rate: hrVal ? parseInt(hrVal, 10) : null,
        p_temperature: tempVal ? parseFloat(tempVal) : null,
        p_respiratory_rate: rrVal ? parseInt(rrVal, 10) : null,
        p_oxygen_saturation: spo2Val ? parseInt(spo2Val, 10) : null,
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
    // Gentle 60-second fallback refresh only when page is visible (Realtime handles instant updates)
    setInterval(() => {
      if (document.visibilityState === 'visible') refresh();
    }, 60000);
  };

  const setupRealtime = async () => {
    if (isDemoMode) return;
    try {
      const { supabase } = await loadSupabaseModule();
      if (queueBoardChannel) {
        try { supabase.removeChannel(queueBoardChannel); } catch (_) {}
        queueBoardChannel = null;
      }
      const today = new Date();
      const queueDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      queueBoardChannel = supabase
        .channel('queue-board-updates')
        .on('postgres_changes', {
          event: '*',
          schema: 'public',
          table: 'queue_tickets',
          filter: `queue_date=eq.${queueDate}`
        }, (payload) => {
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

  const startConsultationFromTicket = (ticket) => {
    if (!ticket) return;
    if (!canConsultPatients()) {
      showToast('Only doctors can conduct consultations.', 'warning');
      return;
    }
    const citizen = ticket.citizen || {};
    const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || ticket.walkin_patient_name || 'Walk-in Patient';
    openConsultationModal({
      patientId: citizen.id ? String(citizen.id) : (ticket.walkin_patient_name || 'Walk-in Patient'),
      patientName: fullName,
      serviceLabel: ticket.service_label || 'General Consultation',
      queueTicketId: ticket.id,
      symptoms: ticket.symptoms || '',
      notes: ticket.reason || ''
    });
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
    const consultServingBtn = document.getElementById('queue-consult-serving-btn');
    if (consultServingBtn && !consultServingBtn.dataset.bound) {
      consultServingBtn.addEventListener('click', () => {
        if (!canConsultPatients()) {
          showToast('Only doctors can conduct consultations.', 'warning');
          return;
        }
        const getStatus = (t) => String(t.status || '').trim().toLowerCase();
        const serving = state.tickets.filter(t => getStatus(t) === 'serving');
        if (serving.length === 0) {
          showToast('No patients are currently in Now Serving.', 'warning');
          return;
        }
        if (serving.length === 1) {
          startConsultationFromTicket(serving[0]);
        } else {
          showToast('Multiple patients are being served. Click Consultation on the specific ticket card.', 'info');
        }
      });
      consultServingBtn.dataset.bound = 'true';
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
    const waitCountEl = document.getElementById('queue-waiting-count');
    const oncallCountEl = document.getElementById('queue-oncall-count');
    const serveCountEl = document.getElementById('queue-serving-count');
    if (!state.tickets || state.tickets.length === 0) {
      if (waitCountEl) waitCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
      if (oncallCountEl) oncallCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
      if (serveCountEl) serveCountEl.innerHTML = '<span class="skeleton-shimmer queue-count-skeleton"></span>';
    }
    try {
      const { supabase } = await loadSupabaseModule();
      
      const manilaToday = new Intl.DateTimeFormat('fr-CA', {
        timeZone: 'Asia/Manila',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
      }).format(new Date());

      // Include active tickets from today OR any unresolved active ticket from the past 24 hours (midnight rollover protection)
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const yesterdayStr = new Intl.DateTimeFormat('fr-CA', {
        timeZone: 'Asia/Manila',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
      }).format(yesterday);

      const { data, error } = await supabase
        .from('queue_tickets')
        .select('id, queue_number, ticket_code, status, queue_date, citizen_type, service_label, symptoms, reason, citizen:citizens(id, firstname, surname, age, sex, contact_number), vitals:vital_signs(id)')
        .gte('queue_date', yesterdayStr)
        .in('status', ['waiting', 'on_call', 'serving'])
        .order('queue_date', { ascending: true })
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
      if (el) {
        el.textContent = val;
        el.classList.remove('data-loaded');
        void el.offsetWidth;
        el.classList.add('data-loaded');
      }
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
        servingBadge.className = 'queue-station-pill active';
        servingBadge.innerHTML = `
          <span class="queue-station-dot"></span>
          <span><strong>Now Serving:</strong> <span style="background:#2563eb;color:#fff;padding:1px 7px;border-radius:6px;font-family:monospace;font-size:11.5px;margin-left:2px;">${servingNumbers.join(', ')}</span></span>
        `;
        servingBadge.style.display = 'inline-flex';
      } else {
        servingBadge.className = 'queue-station-pill ready';
        servingBadge.innerHTML = `
          <span class="queue-station-dot"></span>
          <span>Station Ready • Queue Clear</span>
        `;
      }
    }

    // Toggle consultation button in queue header for doctors when tickets are in Now Serving
    const consultServingBtn = document.getElementById('queue-consult-serving-btn');
    if (consultServingBtn) {
      if (lanes.serving.length > 0 && canConsultPatients()) {
        consultServingBtn.style.display = 'inline-flex';
        consultServingBtn.innerHTML = `
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" style="vertical-align:-1px;margin-right:4px;"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
          ${lanes.serving.length === 1 ? 'Consult Serving' : `Consult Serving (${lanes.serving.length})`}
        `;
      } else {
        consultServingBtn.style.display = 'none';
      }
    }
  };

  const renderLane = (id, list) => {
    const container = document.getElementById(id);
    if (!container) return;
    if (list.length === 0) {
      let emptyIcon = '';
      let emptyTitle = 'Queue Clear';
      let emptySubtitle = 'No tickets currently in this lane.';
      let iconClass = 'waiting-icon';

      if (id === 'queue-waiting-list') {
        iconClass = 'waiting-icon';
        emptyIcon = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#f59e0b" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>`;
        emptyTitle = 'Lobby Queue Clear';
        emptySubtitle = 'No patients currently waiting. New check-ins and appointments will appear here.';
      } else if (id === 'queue-oncall-list') {
        iconClass = 'oncall-icon';
        emptyIcon = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#8b5cf6" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5L6 9H2v6h4l5 4V5z"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>`;
        emptyTitle = 'No Active Calls';
        emptySubtitle = 'Called patients holding for triage arrival and vitals checking will appear here.';
      } else if (id === 'queue-serving-list') {
        iconClass = 'serving-icon';
        emptyIcon = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#16a34a" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>`;
        emptyTitle = 'Station Ready';
        emptySubtitle = 'No consultation in progress. Call or serve a patient to begin clinical evaluation.';
      }

      container.innerHTML = `
        <div class="queue-lane-empty-state">
          <div class="empty-state-icon ${iconClass}">${emptyIcon}</div>
          <div class="empty-state-title">${emptyTitle}</div>
          <div class="empty-state-subtitle">${emptySubtitle}</div>
        </div>
      `;
      return;
    }

    const getIndicatorHtml = (type) => {
      if (type === 'pwd') {
        return `<span style="background:#fef08a;color:#854d0e;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;display:inline-flex;align-items:center;gap:4px;margin-left:6px;" title="PWD">
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="5" r="2"/><path d="M12 7v5h3"/><path d="M15 19l2-3"/><path d="M7 16a5 5 0 1 0 5-8"/></svg>
          PWD
        </span>`;
      }
      if (type === 'pregnant') {
        return `<span style="background:#fbcfe8;color:#be185d;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;display:inline-flex;align-items:center;gap:4px;margin-left:6px;" title="Pregnant">
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>
          Pregnant
        </span>`;
      }
      return '';
    };

    container.innerHTML = list.map(t => `
      <div class="queue-ticket-card" data-id="${t.id}" draggable="true">
        <div class="queue-ticket-top">
          <span class="queue-ticket-queue">#${String(t.queue_number).padStart(3, '0')}</span>
          ${(t.vitals && t.vitals.length > 0) ? '<span class="vitals-badge" title="Vital assessment completed">Vitals Assessed</span>' : ''}
          <span class="queue-ticket-code">${t.ticket_code}</span>
        </div>
        <div class="queue-ticket-name" style="display:flex;align-items:center;">
          ${t.citizen?.firstname ? `${t.citizen.firstname} ${t.citizen.surname || ''}` : (t.walkin_patient_name || 'Walk-in Patient')}
          ${!t.citizen?.firstname ? '<span style="background:#e0f2fe;color:#0369a1;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:700;margin-left:6px;">Walk-in</span>' : ''}
          ${getIndicatorHtml(t.citizen_type)}
        </div>
        <div class="queue-ticket-meta">${t.service_label}</div>
        <div class="queue-ticket-actions">
          ${getStatus(t) === 'waiting' ? '<button class="queue-ticket-btn" data-action="move" data-lane="on_call">On Call</button>' : ''}
          ${getStatus(t) === 'on_call' ? ((t.vitals && t.vitals.length > 0) ? '<button class="queue-ticket-btn" data-action="move" data-lane="serving">Serve</button>' : '') + '<button class="queue-ticket-btn btn-vital" data-action="vital">Vitals</button>' : ''}
          ${getStatus(t) === 'serving' ? (canConsultPatients() ? `
            <button class="queue-ticket-btn btn-consult" data-action="consult">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;">
                <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
              </svg>
              Consultation
            </button>` : '') : ''}
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
          const ticket = state.tickets.find(t => String(t.id) === String(id));
          if (ticket) {
            const { data, error } = await supabase.from('queue_tickets')
              .update({ status: lane })
              .eq('id', id)
              .eq('status', ticket.status)
              .select();
            if (!error && (!data || data.length === 0)) {
              alert('This ticket was already processed by another staff member.');
            }
          }
        } else if (action === 'complete') {
          const ticket = state.tickets.find(t => String(t.id) === String(id));
          if (ticket) {
            await supabase.from('queue_tickets')
              .update({ status: 'completed', completed_at: new Date().toISOString() })
              .eq('id', id)
              .eq('status', ticket.status);
          }

        } else if (action === 'vital') {
          const ticket = state.tickets.find(t => String(t.id) === String(id));
          if (ticket) {
            if (typeof openVitalAssessmentModal === 'function') {
              await openVitalAssessmentModal(ticket);
            }
          }
          return;
        } else if (action === 'consult') {
          const ticket = state.tickets.find(t => String(t.id) === String(id));
          if (ticket) {
            startConsultationFromTicket(ticket);
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
    const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || ticket.walkin_patient_name || 'Walk-in Patient';
    const age = citizen.age ? `${citizen.age} yrs` : 'Age N/A';
    const gender = citizen.sex || 'Sex N/A';
    const phone = citizen.contact_number || 'No phone';

    body.innerHTML = `
      <div style="background:#f8fafc; border-radius:12px; padding:16px; margin-bottom:16px; border:1px solid #e2e8f0;">
        <div style="font-size:11px; color:#64748b; font-weight:700; text-transform:uppercase; margin-bottom:4px;">Patient Info</div>
        <div style="font-size:18px; font-weight:800; color:#0f172a; margin-bottom:2px;">
          ${fullName}
          ${!citizen.firstname ? '<span style="background:#e0f2fe;color:#0369a1;padding:2px 6px;border-radius:4px;font-size:11px;font-weight:700;margin-left:6px;vertical-align:middle;">Walk-in Patient</span>' : ''}
        </div>
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

    const consultDetailBtn = document.getElementById('queue-ticket-consult-btn');
    if (consultDetailBtn) {
      if (getStatus(ticket) === 'serving' && canConsultPatients()) {
        consultDetailBtn.style.display = 'inline-flex';
        consultDetailBtn.onclick = () => {
          modal.classList.add('hidden');
          startConsultationFromTicket(ticket);
        };
      } else {
        consultDetailBtn.style.display = 'none';
      }
    }

    const closeBtn = document.getElementById('queue-ticket-detail-close');
    if (closeBtn) {
      closeBtn.onclick = () => modal.classList.add('hidden');
    }
    
    // Also handle delete if needed
    const deleteBtn = document.getElementById('queue-ticket-delete-btn');
    if (deleteBtn) {
      deleteBtn.onclick = async () => {
        const confirmation = await openDialogModal({
          title: 'Delete Queue Ticket',
          message: 'Are you sure you want to delete this queue ticket? This action cannot be undone.',
          confirmText: 'Delete',
          cancelText: 'Cancel'
        });
        if (!confirmation.confirmed) return;
        
        try {
          setLoading(deleteBtn, true);
          const { supabase } = await loadSupabaseModule();
          
          // Use Number(id) if it's a numeric ID, or keep as string if it's a UUID. 
          // Our state uses string IDs for consistency with dataset.
          const { error } = await supabase
            .from('queue_tickets')
            .delete()
            .eq('id', Number(id));

          if (error) throw error;

          showToast('Ticket deleted successfully.', 'success');
          modal.classList.add('hidden');
          await refresh(); // Await refresh to ensure UI is updated before user interacts again
        } catch (err) {
          console.error('[Queue] Delete error:', err);
          showToast(err.message || 'Failed to delete ticket.', 'error');
        } finally {
          setLoading(deleteBtn, false);
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
