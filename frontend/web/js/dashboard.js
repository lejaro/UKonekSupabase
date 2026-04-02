const sidebar = document.getElementById('sidebar');
const burger = document.getElementById('burger');

const API_BASE = String(window.UKONEK_CONFIG?.API_BASE || '').trim();
const isApiMode = API_BASE.length > 0;
const isDemoMode = Boolean(window.UKONEK_CONFIG?.FORCE_DEMO);
let authServiceModulePromise = null;
let staffServiceModulePromise = null;
let supabaseModulePromise = null;
let authSessionModulePromise = null;

let cachedSessionUser = null;
let sessionUserRole = null;
const DEFAULT_SECTION_ID = 'dashboard-section';
const STAFF_PRESENCE_TIMEOUT_MS = 2 * 60 * 1000;
const STAFF_PRESENCE_HEARTBEAT_MS = 60 * 1000;
const ADMIN_DASHBOARD_REFRESH_MS = 15000;
let presenceHeartbeatTimer = null;
let adminDashboardRefreshTimer = null;
let adminDashboardRefreshInFlight = false;
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

window.addEventListener('load', () => {
  setTimeout(() => {
    dismissPagePreloader();
  }, 2800);
});

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
  if (title.includes('admin')) return 'admin';
  if (title.includes('specialist')) return 'specialist';
  return 'staff';
}

const DEMO_REGISTERED_USERS = [
  {
    username: 'bcruz',
    first_name: 'Ben',
    last_name: 'Cruz',
    employee_id: 'UK-1007',
    role: 'nurse',
    status: 'Active',
    created_at: '2024-11-10T10:30:00Z',
    email: 'bcruz@ukonek.local',
    birthday: '1988-07-22'
  },
  {
    username: 'creyes',
    first_name: 'Carla',
    last_name: 'Reyes',
    employee_id: 'UK-1015',
    role: 'admin',
    status: 'Inactive',
    created_at: '2024-12-01T08:15:00Z',
    email: 'creyes@ukonek.local',
    birthday: '1985-01-14'
  }
];

const demoDelay = (ms = 500) => new Promise((resolve) => setTimeout(resolve, ms));
const makeDemoId = () => (typeof crypto !== 'undefined' && crypto.randomUUID
  ? crypto.randomUUID()
  : `demo-${Date.now()}-${Math.random().toString(16).slice(2)}`);


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

async function ensureAuthenticatedSession(force = false) {
  if (!force && cachedSessionUser) {
    sessionUserRole = cachedSessionUser.role || sessionUserRole;
    return cachedSessionUser;
  }

  try {
    const authService = await loadAuthServiceModule();
    const profile = await authService.getAuthenticatedStaffProfile();

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
  return (sessionUserRole || detectRoleFromTitle()).toLowerCase();
}


function isAdminUser(user) {
  return String(user?.role || '').trim().toLowerCase() === 'admin';
}

const SECTION_ROLE_RULES = {
  'dashboard-section': ['admin'],
  'users-section': ['admin', 'doctor', 'nurse', 'staff'],
  'reports-section': ['admin'],
  'medicine-section': ['admin', 'doctor', 'nurse', 'staff'],
  'consultation-section': ['admin', 'doctor', 'nurse', 'staff'],
  'schedule-section': ['admin', 'doctor', 'nurse', 'staff'],
  'profile-section': ['admin', 'doctor', 'nurse', 'staff']
};

function isSectionAllowedForRole(sectionId, role) {
  const roleKey = String(role || '').trim().toLowerCase();
  const allowed = SECTION_ROLE_RULES[sectionId];
  if (!allowed || allowed.length === 0) return true;
  return allowed.includes(roleKey);
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
    document.querySelectorAll('.admin-only').forEach((element) => {
      element.classList.add('hidden');
    });
  }

  sessionUserRole = String(user?.role || detectRoleFromTitle()).trim().toLowerCase() || sessionUserRole;

  const userNameNode = document.querySelector('.user-name');
  if (userNameNode) {
    userNameNode.textContent = getDisplayFirstName(user);
  }

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
  admin: { adjust: false, add: false },
  specialist: { adjust: true, add: false },
  staff: { adjust: true, add: true }
};

function canAdjustMedicineInventory(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(MEDICINE_PERMISSIONS[key]?.adjust);
}

function canAddNewMedicine(role = getSessionRole()) {
  const key = (role || '').toLowerCase();
  return Boolean(MEDICINE_PERMISSIONS[key]?.add);
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
      activeMenu.classList.remove('hidden');
    }

    // Toggle dropdown when clicking a nav button.
    if (isDropdownBtn && activeMenu) {
      activeMenu.classList.toggle('hidden');
    }

    // Nav activation logic
    if (sectionId || isDropdownBtn) {
      hideAllSections();
      clearActiveNav();

      // Activate clicked element
      el.classList.add('is-active');

      // Activate parent dropdown btn for dropdown items
      if (isDropdownItem && parentItem) {
        const parentBtn = parentItem.querySelector('.nav-btn');
        if (parentBtn) parentBtn.classList.add('is-active');
      }

      showSection(sectionId || el.getAttribute('data-section'), sectionOptions);
    }
  });
}

document.addEventListener('click', (event) => {
  if (!sidebar) return;
  if (sidebar.contains(event.target)) return;
  document.querySelectorAll('.dropdown-menu').forEach((menu) => menu.classList.add('hidden'));
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
    if (!isToday(announcement?.date)) return;
    items.push({
      type: 'Announcement',
      title: announcement?.title || 'Announcement',
      detail: announcement?.preview || announcement?.content || '',
      date: parseDateValue(announcement?.date)
    });
  });

  latestFeedbackList.forEach((feedback) => {
    if (!isToday(feedback?.date)) return;
    items.push({
      type: 'Feedback',
      title: feedback?.subject || 'Feedback received',
      detail: feedback?.from || 'Anonymous',
      date: parseDateValue(feedback?.date)
    });
  });

  return items.sort((a, b) => {
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
    const typeLabel = document.createElement('span');
    typeLabel.className = 'notif-type';
    typeLabel.textContent = item.type;
    li.appendChild(typeLabel);

    const strong = document.createElement('strong');
    strong.textContent = item.title;
    li.appendChild(strong);

    const meta = document.createElement('span');
    meta.className = 'notif-meta';
    const timeStamp = item.date
      ? item.date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true })
      : 'Today';
    meta.textContent = item.detail ? `${timeStamp} • ${item.detail}` : timeStamp;
    li.appendChild(meta);

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
  const role = String(user?.role || getSessionRole()).toLowerCase();
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
        renderDashboardInsights();
        break;
      // Add more as needed
    }
    const { tab, pane } = options;

    if (sectionId === 'users-section') {
      if (pane === 'registration-pane') {
        toggleUsersPane('registration-pane');
      } else {
        toggleUsersPane('accounts-pane');
        const defaultPane = isAdminUser(user) ? 'registered-pane' : 'citizens-pane';
        revealPane(pane || defaultPane);
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
      employee_id: payload.employee_id,
      role: payload.role,
      doctor_specialization: payload.doctor_specialization || null,
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
      doctor_specialization: payload?.doctor_specialization ?? null,
      doctorSpecialization: payload?.doctor_specialization ?? null,
      specialization: payload?.doctor_specialization ?? null,
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
  const { data, error } = await supabase.rpc('create_staff_account_admin', {
    p_first_name: payload.first_name,
    p_middle_name: payload.middle_name,
    p_last_name: payload.last_name,
    p_birthday: payload.birthday,
    p_gender: payload.gender,
    p_username: payload.username,
    p_employee_id: payload.employee_id,
    p_email: payload.email,
    p_role: payload.role,
    p_doctor_specialization: payload.doctor_specialization || null,
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
    const employee_id = document.getElementById('reg-employee-id').value.trim();
    const username = document.getElementById('reg-username').value.trim();
    const email = document.getElementById('reg-email').value.trim();
    const password = document.getElementById('reg-password').value;
    const confirmPassword = document.getElementById('reg-confirm-password').value;
    const role = document.getElementById('reg-role').value;
    const doctorSpecialization = document.getElementById('reg-doctor-specialization')
      ? document.getElementById('reg-doctor-specialization').value.trim()
      : '';

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

    if (!first_name || !last_name || !employee_id || !username || !email || !role) {
      if (err) {
        err.textContent = 'Please fill in all required fields.';
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

    if (role === 'doctor' && !doctorSpecialization) {
      if (err) {
        err.textContent = 'Doctor specialization is required for doctor accounts.';
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
        employee_id,
        email: email.toLowerCase(),
        role,
        doctor_specialization: role === 'doctor' ? doctorSpecialization : null,
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
const regDoctorSpecializationField = document.getElementById('reg-doctor-specialization-field');
const regDoctorSpecializationInput = document.getElementById('reg-doctor-specialization');

function updateRegistrationSpecializationVisibility() {
  if (!regRoleInput || !regDoctorSpecializationField) return;
  const isDoctor = String(regRoleInput.value || '').toLowerCase() === 'doctor';
  regDoctorSpecializationField.classList.toggle('hidden', !isDoctor);
  if (regDoctorSpecializationInput) {
    regDoctorSpecializationInput.required = isDoctor;
    if (!isDoctor) regDoctorSpecializationInput.value = '';
  }
}

if (regRoleInput) {
  regRoleInput.addEventListener('change', updateRegistrationSpecializationVisibility);
  updateRegistrationSpecializationVisibility();
}

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

// Employee ID numeric only
const employeeIdInput = document.getElementById('reg-employee-id');
if (employeeIdInput) {
  employeeIdInput.addEventListener('input', function () {
    this.value = this.value.replace(/\D+/g, '');
  });
}

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
    loadSchedules(user);
  }
}

function populateProfile(user) {
  const name = document.getElementById('profile-name');
  const email = document.getElementById('profile-email');
  const role = document.getElementById('profile-role');
  const specializationField = document.getElementById('profile-specialization-field');
  const specializationInput = document.getElementById('profile-specialization');
  const preview = document.getElementById('profile-pic-preview');

  if (name) name.value = user?.first_name || user?.username || '';
  if (email) email.value = user?.email || '';
  if (role) role.value = toTitleCase(user?.role || '');

  const isDoctor = String(user?.role || '').toLowerCase() === 'doctor';
  if (specializationField) specializationField.classList.toggle('hidden', !isDoctor);
  if (specializationInput) {
    specializationInput.value = isDoctor ? getSpecializationValue(user) : '';
    specializationInput.required = isDoctor;
  }

  if (preview) {
    preview.innerHTML = '';
    if (user?.profilePicture) {
      const img = document.createElement('img');
      img.src = user.profilePicture;
      img.style.maxWidth = '120px';
      img.style.borderRadius = '6px';
      preview.appendChild(img);
    }
  }
}

const profilePicInput = document.getElementById('profile-pic');
if (profilePicInput) {
  profilePicInput.addEventListener('change', (e) => {
    const preview = document.getElementById('profile-pic-preview');
    preview.innerHTML = '';
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const img = document.createElement('img');
    img.src = URL.createObjectURL(file);
    img.style.maxWidth = '120px';
    img.style.borderRadius = '6px';
    preview.appendChild(img);
  });
}

const profileSaveBtn = document.getElementById('profile-save-btn');
if (profileSaveBtn) {
  profileSaveBtn.addEventListener('click', async () => {
    const name = document.getElementById('profile-name').value.trim();
    const email = document.getElementById('profile-email').value.trim();
    const role = String(document.getElementById('profile-role')?.value || '').trim().toLowerCase();
    const specializationValue = String(document.getElementById('profile-specialization')?.value || '').trim();
    const fileInput = document.getElementById('profile-pic');

    const form = new FormData();
    form.append('displayName', name);
    form.append('email', email);
    if (role === 'doctor') {
      form.append('doctorSpecialization', specializationValue);
    }
    if (fileInput && fileInput.files && fileInput.files[0]) {
      form.append('avatar', fileInput.files[0]);
    }

    try {
      if (isApiMode) {
        const resp = await fetch(`${API_BASE}/api/staff/profile`, {
          method: 'POST',
          credentials: 'include',
          body: form
        });
        if (!resp.ok) throw new Error('Failed to save profile');
      } else {
        if (role === 'doctor') {
          const { supabase } = await loadSupabaseModule();
          const { data, error } = await supabase.rpc('set_my_doctor_specialization', {
            p_specialization: specializationValue || null
          });
          if (error) {
            throw new Error(error.message || 'Failed to save specialization');
          }
          if (data && data.error) {
            throw new Error(data.error);
          }
        }

        // Backendless mode: keep UI/session profile in sync.
        cachedSessionUser = {
          ...(cachedSessionUser || {}),
          first_name: name || cachedSessionUser?.first_name,
          email: email || cachedSessionUser?.email,
          doctor_specialization: role === 'doctor'
            ? specializationValue
            : (cachedSessionUser?.doctor_specialization || null)
        };
      }
      showToast('Profile updated', 'success');
      // re-sync session/profile
      const user = await ensureAuthenticatedSession();
      if (user) populateProfile(user);
    } catch (err) {
      console.error(err);
      showToast('Unable to save profile (offline placeholder)', 'error');
    }
  });
}

// Profile cancel - reset to session values
const profileCancelBtn = document.getElementById('profile-cancel-btn');
if (profileCancelBtn) {
  profileCancelBtn.addEventListener('click', async () => {
    const user = await ensureAuthenticatedSession();
    if (user) populateProfile(user);
    else {
      const form = document.getElementById('profile-form');
      if (form) form.reset();
      const preview = document.getElementById('profile-pic-preview');
      if (preview) preview.innerHTML = '';
    }
  });
}

// --- Schedule handling (doctor-based schedules). Admins can create/update/delete; others view only ---
let cachedScheduleDoctors = [];
let cachedScheduleEntries = [];

function getDoctorDisplayName(doctor) {
  const fullName = `${doctor?.first_name || ''} ${doctor?.last_name || ''}`.replace(/\s+/g, ' ').trim();
  if (fullName) return fullName;
  return doctor?.username || doctor?.email || 'Doctor';
}

function getSpecializationValue(entity) {
  return String(
    entity?.doctor_specialization
    ?? entity?.doctorSpecialization
    ?? entity?.specialization
    ?? ''
  ).trim();
}

function getDoctorSpecializationText(doctor) {
  return getSpecializationValue(doctor) || '—';
}

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

async function purgePastSchedules(records, user, source = 'doctor_schedules') {
  const normalized = Array.isArray(records) ? records : [];
  const expired = normalized.filter((entry) => isPastScheduleDateValue(entry?.schedule_date || entry?.date));

  // Always keep expired items out of the live UI list.
  const activeRecords = normalized.filter((entry) => !isPastScheduleDateValue(entry?.schedule_date || entry?.date));

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

function renderScheduleDoctors(doctors, user) {
  const tbody = document.getElementById('schedule-doctors-tbody');
  if (!tbody) return;

  tbody.innerHTML = '';
  if (!doctors.length) {
    tbody.innerHTML = '<tr><td class="table-cell" colspan="5">No doctor accounts found.</td></tr>';
    return;
  }

  doctors.forEach((doctor) => {
    const tr = document.createElement('tr');
    const statusText = getStaffPresenceStatus(doctor);
    const statusClass = getStaffPresenceBadgeClass(doctor);
    tr.innerHTML = `
      <td class="table-cell">${getDoctorDisplayName(doctor)}</td>
      <td class="table-cell">${getDoctorSpecializationText(doctor)}</td>
      <td class="table-cell">${doctor.email || '—'}</td>
      <td class="table-cell"><span class="${statusClass}">${statusText}</span></td>
      <td class="table-cell"></td>
    `;

    const actionsCell = tr.querySelector('td:last-child');
    if (isAdminUser(user)) {
      const setBtn = document.createElement('button');
      setBtn.type = 'button';
      setBtn.className = 'chip-btn';
      setBtn.textContent = 'Set Schedule';
      setBtn.addEventListener('click', () => openScheduleModal('create', { doctor_staff_id: doctor.id }));
      actionsCell.appendChild(setBtn);
    } else {
      actionsCell.textContent = '-';
    }

    tbody.appendChild(tr);
  });
}

function populateScheduleDoctorSelect(selectedDoctorId = null) {
  const select = document.getElementById('sched-doctor-id');
  if (!select) return;

  const selected = selectedDoctorId ? String(selectedDoctorId) : '';
  select.innerHTML = '<option value="">Select doctor</option>';

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
        doctors = (Array.isArray(staff) ? staff : []).filter((item) => String(item?.role || '').toLowerCase() === 'doctor');
      }
    } else {
      const [staffService, supabaseModule] = await Promise.all([loadStaffServiceModule(), loadSupabaseModule()]);
      const { supabase } = supabaseModule;

      const staff = await staffService.listStaff();
      doctors = (Array.isArray(staff) ? staff : []).filter((item) => String(item?.role || '').toLowerCase() === 'doctor');

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

  cachedScheduleDoctors = Array.isArray(doctors) ? [...doctors] : [];
  populateScheduleDoctorSelect();
  renderScheduleDoctors(cachedScheduleDoctors, user);
  renderSchedules(schedules, user, cachedScheduleDoctors);
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
    tbody.innerHTML = '<tr><td class="table-cell" colspan="6">No schedules found.</td></tr>';
    return;
  }

  schedules.forEach((schedule) => {
    const doctorId = schedule.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    const doctor = doctorId ? doctorMap.get(doctorId) : null;
    const doctorName = schedule.doctor_name || getDoctorDisplayName(doctor) || 'Doctor';
    const doctorSpecialization = getDoctorSpecializationText(doctor);
    const scheduleDate = schedule.schedule_date || schedule.date || '—';
    const startTime = formatScheduleTime(schedule.start_time || schedule.time);
    const endTime = formatScheduleTime(schedule.end_time);

    const tr = document.createElement('tr');
    tr.dataset.date = scheduleDate;
    tr.innerHTML = `
      <td class="table-cell">${doctorName}</td>
      <td class="table-cell">${doctorSpecialization}</td>
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
        if (!confirm('Delete this schedule?')) return;
        try {
          if (isApiMode) {
            const resp = await fetch(`${API_BASE}/api/schedules/${schedule.id}`, { method: 'DELETE', credentials: 'include' });
            if (!resp.ok) throw new Error('Delete failed');
          } else {
            const { supabase } = await loadSupabaseModule();
            let result = await supabase.from('doctor_schedules').delete().eq('id', schedule.id);
            if (result.error) {
              result = await supabase.from('schedules').delete().eq('id', schedule.id);
            }
            if (result.error) throw result.error;
          }
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
        { label: 'Specialization', value: doctorSpecialization },
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

      if (isApiMode) {
        const url = id ? `${API_BASE}/api/schedules/${id}` : `${API_BASE}/api/schedules`;
        const method = id ? 'PUT' : 'POST';
        const resp = await fetch(url, {
          method,
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            doctor: doctorName,
            doctor_staff_id: Number(doctorId),
            date,
            start_time: startTime,
            end_time: endTime,
            time: `${startTime}-${endTime}`,
            notes: notes || null
          })
        });
        if (!resp.ok) {
          const data = await resp.json().catch(() => ({}));
          throw new Error(data.message || 'Failed to save schedule');
        }
      } else {
        const { supabase } = await loadSupabaseModule();
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
      }

      closeScheduleModal();
      initProfileAndSchedule();

      if (id) {
        showToast('Schedule updated', 'success');
      } else {
        showScheduleSuccessModal();
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
    if (!confirm('Delete this schedule?')) return;
    try {
      if (isApiMode) {
        const resp = await fetch(`${API_BASE}/api/schedules/${id}`, { method: 'DELETE', credentials: 'include' });
        if (!resp.ok) throw new Error('Delete failed');
      } else {
        const { supabase } = await loadSupabaseModule();
        let result = await supabase.from('doctor_schedules').delete().eq('id', id);
        if (result.error) {
          result = await supabase.from('schedules').delete().eq('id', id);
        }
        if (result.error) throw result.error;
      }
      showToast('Schedule deleted', 'success');
      closeScheduleModal();
      initProfileAndSchedule();
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
  // Master init - call all content population functions
  initProfileAndSchedule();
  initClinicalData();
  await refreshAnnouncementsData();
  renderFeedbacks();
  initDashboardData();
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  initializeDashboard();
  navigateToSection(getSectionFromHash() || DEFAULT_SECTION_ID);
});



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
const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');
const patientsTbody = document.getElementById('citizens-tbody');
const staffFinderInput = document.getElementById('staff-finder-input');
const roleFilterInput = document.getElementById('role-filter');
const citizensFinderInput = document.getElementById('citizens-finder-input');
const userPaneIds = ['accounts-pane', 'registration-pane'];
const chartAnimationState = { frameId: null };

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

function applyCitizensFinder() {
  const query = String(citizensFinderInput?.value || '').trim().toLowerCase();
  const rows = document.querySelectorAll('#citizens-tbody tr.citizen-row');
  rows.forEach((row) => {
    const text = row.textContent ? row.textContent.toLowerCase() : '';
    row.style.display = !query || text.includes(query) ? '' : 'none';
  });
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
  const currentRole = getSessionRole();
  const allowedTarget = isSectionAllowedForRole(targetId, currentRole)
    ? targetId
    : (isSectionAllowedForRole('users-section', currentRole) ? 'users-section' : 'profile-section');

  if (allowedTarget !== targetId) {
    showToast('Access denied for this section.', 'warning');
  }

  hideAllSections();
  clearActiveNav();
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
    await refreshAnnouncementsData();
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
      await createAnnouncementEntry({ title, content });
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
      await updateAnnouncementEntry(announcementId, { title, content });
      await refreshAnnouncementsData();
      renderDashboardInsights();

      closeEditAnnouncementModal();
      closeDataDetail();
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
const announcementDetailTitle = document.getElementById('announcement-detail-title');
const announcementDetailBody = document.getElementById('announcement-detail-body');
const announcementDetailDate = document.getElementById('announcement-detail-date');
const dataDetailModal = document.getElementById('data-detail-modal');
const dataDetailCloseBtn = document.getElementById('data-detail-close');
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

if (dataDetailCloseBtn) dataDetailCloseBtn.addEventListener('click', closeDataDetail);
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
});

if (announcementDetailModal) {
  announcementDetailModal.addEventListener('click', (e) => {
    if (e.target === announcementDetailModal || e.target.classList.contains('modal-close')) {
      announcementDetailModal.classList.add('hidden');
    }
  });
}
if (announcementDetailClose) announcementDetailClose.addEventListener('click', () => announcementDetailModal.classList.add('hidden'));





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
  if (!user?.is_online) return false;

  const lastSeenValue = user?.last_seen;
  if (!lastSeenValue) return false;

  const lastSeenAt = new Date(lastSeenValue).getTime();
  if (!Number.isFinite(lastSeenAt)) return false;

  if (Date.now() - lastSeenAt > STAFF_PRESENCE_TIMEOUT_MS) return false;

  return true;
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

  if (!latestFeedbackList.length) {
    latestFeedbackList = loadFeedbacks();
  }
  const feedbackCount = latestFeedbackList.length || 0;
  if (statReports) statReports.textContent = String(feedbackCount);

  // Citizens count
  if (statPatients) statPatients.textContent = String(latestPatientsList.length || 0);

  const doctorsCount = latestStaffList.filter((user) => String(user.role || '').toLowerCase() === 'doctor').length;
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

  if (!latestFeedbackList.length) latestFeedbackList = loadFeedbacks();

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

// Load citizens (mobile app users)
async function loadPatientData() {
  let list = [];

  if (isDemoMode) {
    list = [];
  } else {
    try {
      if (isApiMode) {
        const response = await fetch(`${API_BASE}/api/citizens`, { credentials: 'include' });
        if (response && response.ok) {
          list = await response.json();
        }
      } else {
        const { supabase } = await loadSupabaseModule();
        let data = null;
        let error = null;

        ({ data, error } = await supabase
          .from('citizens')
          .select('username,email,created_at,status')
          .order('created_at', { ascending: false }));

        if (error) {
          ({ data, error } = await supabase
            .from('patients')
            .select('username,email,created_at,status')
            .order('created_at', { ascending: false }));
        }

        if (error) throw error;
        list = data || [];
      }
    } catch (error) {
      console.error('Error loading citizens:', error);
      list = [];
    }
  }

  latestPatientsList = Array.isArray(list) ? [...list] : [];

  if (patientsTbody) {
    patientsTbody.innerHTML = '';
    if (latestPatientsList.length === 0) {
      patientsTbody.innerHTML = '<tr><td class="table-cell" colspan="3">No citizen accounts found.</td></tr>';
    } else {
      latestPatientsList.forEach(user => {
        const row = document.createElement('tr');
        row.className = 'citizen-row';
        row.innerHTML = `
          <td class="table-cell">${user.username || user.name || '—'}</td>
          <td class="table-cell">${user.email || '—'}</td>
          <td class="table-cell">${formatDateTime(user.created_at)}</td>
        `;
        patientsTbody.appendChild(row);
        attachDetailRow(row, () => ({
          tag: 'Citizens',
          title: user.username || user.name || 'Citizen Account',
          subtitle: user.email || '',
          items: [
            { label: 'Username', value: user.username || user.name || '—' },
            { label: 'Email', value: user.email || '—' },
            { label: 'Registered', value: user.created_at ? new Date(user.created_at) : '—' }
          ]
        }));
      });
    }

    applyCitizensFinder();
  }
}

async function loadStaffData() {
  let staffList = [];

  if (isDemoMode) {
    staffList = DEMO_REGISTERED_USERS;
  } else {
    try {
      if (isApiMode) {
        const response = await fetch(`${API_BASE}/api/staff`, { credentials: 'include' });
        if (!response.ok) throw new Error('Failed to fetch staff');
        staffList = await response.json();
      } else {
        const staffService = await loadStaffServiceModule();
        staffList = await staffService.listStaff();
      }
    } catch (error) {
      console.error('Error loading staff:', error);
      staffList = DEMO_REGISTERED_USERS;
    }
  }

  latestStaffList = Array.isArray(staffList) ? [...staffList] : [];

  const accountsTbody = document.getElementById('accounts-tbody');
  if (accountsTbody) {
    accountsTbody.innerHTML = '';
    if (latestStaffList.length === 0) {
      accountsTbody.innerHTML = '<tr><td class="table-cell" colspan="5">No registered staff accounts found.</td></tr>';
    } else {
      latestStaffList.forEach(user => {
        const identifier = user.username || user.employee_id || makeDemoId();
        storedAccounts.set(identifier, user);

        const roleValue = user.role ? String(user.role) : '';
        const roleLabel = roleValue ? roleValue.charAt(0).toUpperCase() + roleValue.slice(1) : '—';
        const specializationLabel = getSpecializationValue(user) || '—';
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
          <td class="table-cell">${specializationLabel}</td>
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
async function initDashboardData() {
  try {
    const sessionUser = await ensureAuthenticatedSession();
    if (!sessionUser) return;

    startPresenceHeartbeat();
    applyRoleAccess(sessionUser);

    await loadPatientData();

    if (!isAdminUser(sessionUser)) {
      stopAdminDashboardAutoRefresh();
      renderDashboardInsights();
      return;
    }

    // Do not force section visibility here; active section is managed by navigateToSection.
    storedAccounts.clear();
    await loadStaffData();
    startAdminDashboardAutoRefresh();
    // Refresh counts after all data loaded
    renderDashboardInsights();
  } finally {
    dismissPagePreloader();
  }
}

initDashboardData();

window.addEventListener('pagehide', () => {
  handleAutoLogoutOnClose();
});

window.addEventListener('beforeunload', () => {
  handleAutoLogoutOnClose();
});

if (dashRefreshBtn) {
  dashRefreshBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData()]);
    showToast('Dashboard data refreshed.', 'info');
  });
}

if (refreshAccountsBtn) {
  refreshAccountsBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPatientData(), refreshAnnouncementsData()]);
    showToast('Account tables refreshed.', 'info');
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
const modalEditSpecialization = document.getElementById('modal-edit-specialization');
const modalEditSpecializationGroup = document.getElementById('modal-edit-specialization-group');
const modalEditBirthday = document.getElementById('modal-edit-birthday');

function syncModalSpecializationVisibility() {
  if (!modalEditRole || !modalEditSpecializationGroup) return;
  const isDoctor = String(modalEditRole.value || '').toLowerCase() === 'doctor';
  modalEditSpecializationGroup.classList.toggle('hidden', !isDoctor);
  if (modalEditSpecialization) {
    modalEditSpecialization.required = isDoctor;
    if (!isDoctor) modalEditSpecialization.value = '';
  }
}

if (modalEditRole) {
  modalEditRole.addEventListener('change', syncModalSpecializationVisibility);
}

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
    const roleValue = String(user.role || 'staff').trim().toLowerCase();
    modalEditRole.value = roleValue || 'staff';
  }
  if (modalEditSpecialization) {
    modalEditSpecialization.value = getSpecializationValue(user);
  }
  if (modalEditBirthday) modalEditBirthday.value = normalizeDateInput(user.birthday);
  syncModalSpecializationVisibility();
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
    const apiPayload = {
      ...payload,
      doctor_specialization: payload?.doctor_specialization ?? null,
      doctorSpecialization: payload?.doctor_specialization ?? null,
      specialization: payload?.doctor_specialization ?? null
    };
    const requestBody = JSON.stringify(apiPayload);
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

async function persistDoctorSpecializationById(staffId, specializationValue) {
  const normalized = String(specializationValue || '').trim() || null;

  if (isApiMode) {
    const endpoints = [
      `${API_BASE}/api/staff/${staffId}/specialization`,
      `${API_BASE}/api/staff/specialization`
    ];

    for (const endpoint of endpoints) {
      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({
            staffId,
            doctor_specialization: normalized,
            doctorSpecialization: normalized,
            specialization: normalized
          })
        });

        if (response.ok) {
          return true;
        }
      } catch (_) {
        // Continue to next fallback.
      }
    }
  }

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase.rpc('set_staff_specialization_admin', {
    target_staff_id: staffId,
    p_specialization: normalized
  });

  if (error) {
    throw new Error(error.message || 'Failed to save doctor specialization.');
  }

  if (data && data.error) {
    throw new Error(data.error);
  }

  return true;
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
  const modalSpecialization = document.getElementById('modal-specialization');
  const modalSpecializationGroup = document.getElementById('modal-specialization-group');
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
  const isDoctor = String(user.role || '').toLowerCase() === 'doctor';
  if (modalSpecializationGroup) modalSpecializationGroup.classList.toggle('hidden', !isDoctor);
  if (modalSpecialization) {
    modalSpecialization.textContent = isDoctor
      ? (getSpecializationValue(user) || '—')
      : '—';
  }
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
    const specializationValue = getSpecializationValue(user) || '—';

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
        { label: 'Specialization', value: specializationValue },
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

    const newPassword = window.prompt('Enter a new password (minimum 8 characters):', '');
    if (newPassword === null) return;

    const confirmPassword = window.prompt('Confirm the new password:', '');
    if (confirmPassword === null) return;

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
    const doctorSpecialization = String(modalEditSpecialization?.value || '').trim();
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

    if (role === 'doctor' && !doctorSpecialization) {
      setModalEditError('Doctor specialization is required for doctor accounts.');
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
      doctor_specialization: role === 'doctor' ? doctorSpecialization : null,
      birthday: String(modalEditBirthday?.value || '').trim() || null
    };

    try {
      modalSaveBtn.disabled = true;
      await updateStaffAccountById(currentAccountData.id, payload);
      if (role === 'doctor') {
        await persistDoctorSpecializationById(currentAccountData.id, doctorSpecialization);
      }
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

function openConsultationModal(prefill = {}) {
  if (!consultationModal) return;
  if (consultationForm) consultationForm.reset();
  if (prefill.patientId) {
    const patientInput = document.getElementById('consult-patient-id');
    if (patientInput) patientInput.value = prefill.patientId;
  }
  consultationModal.classList.remove('hidden');
}

function closeConsultationModal() {
  if (!consultationModal) return;
  consultationModal.classList.add('hidden');
  if (consultationForm) consultationForm.reset();
}

if (openConsultModalBtn) {
  openConsultModalBtn.addEventListener('click', () => openConsultationModal());
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
let medicines = [];
let prescriptions = [];

// === DUMMY DATA ARRAYS ===
const DUMMY_CONSULTATIONS = [
  {
    id: 'C-20240101',
    patientId: 'CIT-1001',
    symptoms: 'Fever, dry cough, fatigue',
    diagnosis: 'Seasonal Influenza',
    notes: 'Advise rest and plenty of fluids. Prescribe antiviral if symptoms persist.',
    created_at: '2024-12-10T09:15:00Z'
  },
  {
    id: 'C-20240115',
    patientId: 'CIT-1042',
    symptoms: 'Persistent headache and blurred vision',
    diagnosis: 'Hypertension monitoring',
    notes: 'Adjust maintenance meds. Schedule follow-up in two weeks.',
    created_at: '2024-12-12T13:40:00Z'
  },
  {
    id: 'C-20240128',
    patientId: 'CIT-1110',
    symptoms: 'Shortness of breath, mild chest tightness',
    diagnosis: 'Asthma exacerbation',
    notes: 'Nebulization done onsite. Prescribe inhaled corticosteroid.',
    created_at: '2024-12-15T08:05:00Z'
  }
];

const DUMMY_MEDICINES = [
  { name: 'Paracetamol 500mg', qty: 150, unit: 'tabs' },
  { name: 'Amoxicillin 500mg', qty: 80, unit: 'capsules' },
  { name: 'Ibuprofen 400mg', qty: 120, unit: 'tabs' },
  { name: 'Metformin 500mg', qty: 200, unit: 'tabs' },
  { name: 'Amlodipine 5mg', qty: 90, unit: 'tabs' },
  { name: 'Salbutamol Inhaler', qty: 25, unit: 'units' },
  { name: 'Insulin 100IU/ml', qty: 12, unit: 'vials' },
  { name: 'Losartan 50mg', qty: 75, unit: 'tabs' },
  { name: 'Atorvastatin 20mg', qty: 60, unit: 'tabs' }
];

const DUMMY_FEEDBACKS = [
  { id: 'F001', from: 'patient123@example.com', subject: 'Excellent service!', date: '2024-10-14', rating: 5 },
  { id: 'F002', from: 'john.doe@email.com', subject: 'Long wait time', date: '2024-10-13', rating: 3 },
  { id: 'F003', from: 'sarah.wilson@outlook.com', subject: 'Very professional doctor', date: '2024-10-12', rating: 5 },
  { id: 'F004', from: 'mike.johnson@gmail.com', subject: 'Prescription issue', date: '2024-10-11', rating: 2 },
  { id: 'F005', from: 'emily.chen@yahoo.com', subject: 'Great follow-up care', date: '2024-10-10', rating: 4 },
  { id: 'F006', from: 'david.lee@protonmail.com', subject: 'Clean facility, friendly staff', date: '2024-10-09', rating: 5 },
  { id: 'F007', from: 'lisa.martinez@icloud.com', subject: 'Billing confusion', date: '2024-10-08', rating: 3 },
  { id: 'F008', from: 'robert.taylor@gmail.com', subject: 'Outstanding emergency service', date: '2024-10-07', rating: 5 },
  { id: 'F009', from: 'anna.kovacs@hotmail.com', subject: 'Appointment scheduling easy', date: '2024-10-06', rating: 4 }
];


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

function renderConsultations() {
  if (!consultationsTbody) return;
  consultationsTbody.innerHTML = '';
  consultations.slice().reverse().forEach(c => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="table-cell">${c.id}</td>
      <td class="table-cell">${c.patientId}</td>
      <td class="table-cell">${(c.diagnosis||'').substring(0,60)}</td>
      <td class="table-cell">${formatDateTime(c.created_at)}</td>
      <td class="table-cell">
        <button class="btn small" data-action="view" data-id="${c.id}">View</button>
        <button class="btn small outline" data-action="prescribe" data-id="${c.id}">Prescribe</button>
      </td>
    `;
    consultationsTbody.appendChild(tr);
    attachDetailRow(tr, () => ({
      tag: 'Consultation',
      title: c.patientId || 'Consultation Record',
      subtitle: c.id,
      items: [
        { label: 'Consultation ID', value: c.id },
        { label: 'Patient ID', value: c.patientId },
        { label: 'Symptoms', value: c.symptoms || '—' },
        { label: 'Diagnosis', value: c.diagnosis || '—' },
        { label: 'Notes', value: c.notes || '—' },
        { label: 'Recorded', value: new Date(c.created_at) }
      ]
    }));
  });
}

function renderMedicines() {
  if (!medicineTbody) return;

  const role = getSessionRole();
  const allowAdjust = canAdjustMedicineInventory(role);
  const allowAddNew = canAddNewMedicine(role);

  const medicineFormEl = document.getElementById('medicine-form');
  if (medicineFormEl) {
    const formPanel = medicineFormEl.closest('.panel');
    if (formPanel) formPanel.classList.toggle('hidden', !allowAddNew);
    medicineFormEl.querySelectorAll('input, select, textarea, button').forEach((el) => {
      el.disabled = !allowAddNew;
    });
  }

  medicineTbody.innerHTML = '';
  medicines.forEach(m => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="table-cell">${m.name}</td>
      <td class="table-cell">${m.qty}</td>
      <td class="table-cell">${m.unit || ''}</td>
      <td class="table-cell"></td>
    `;

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
    } else {
      actionsTd.textContent = 'View only';
    }

    medicineTbody.appendChild(tr);
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
}

async function initClinicalData() {
  await ensureAuthenticatedSession().catch(() => null);
  consultations = loadFromStorage('ukonek_consultations');
  if (!Array.isArray(consultations) || consultations.length === 0) {
    consultations = [...DUMMY_CONSULTATIONS];
    saveToStorage('ukonek_consultations', consultations);
  }

  medicines = loadFromStorage('ukonek_medicine_inventory');
  if (!Array.isArray(medicines) || medicines.length === 0) {
    medicines = [...DUMMY_MEDICINES];
    saveToStorage('ukonek_medicine_inventory', medicines);
  }

  prescriptions = loadFromStorage('ukonek_prescriptions') || [];
  renderConsultations();
  renderMedicines();
}

function mapAnnouncementRow(item) {
  const content = String(item?.content || item?.body || item?.preview || '').trim();
  return {
    id: item?.id,
    title: String(item?.title || '').trim(),
    content,
    preview: content,
    date: item?.created_at
      ? new Date(item.created_at).toISOString().slice(0, 10)
      : String(item?.date || '').trim(),
    created_at: item?.created_at || null,
    updated_at: item?.updated_at || null
  };
}

function loadAnnouncementsFromLocalStorage() {
  try {
    const raw = localStorage.getItem('ukonek_announcements');
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.map(mapAnnouncementRow) : [];
  } catch (_) {
    return [];
  }
}

async function listAnnouncementsData() {
  if (isDemoMode) {
    return loadAnnouncementsFromLocalStorage();
  }

  if (isApiMode) {
    const response = await fetch(`${API_BASE}/api/announcements`, {
      method: 'GET',
      credentials: 'include'
    });

    if (!response.ok) {
      throw new Error('Unable to load announcements.');
    }

    const data = await response.json().catch(() => ([]));
    return (Array.isArray(data) ? data : []).map(mapAnnouncementRow);
  }

  const { supabase } = await loadSupabaseModule();
  const { data, error } = await supabase
    .from('announcements')
    .select('id,title,content,created_at,updated_at')
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(error.message || 'Unable to load announcements.');
  }

  return (data || []).map(mapAnnouncementRow);
}

async function createAnnouncementEntry({ title, content }) {
  const cleanTitle = String(title || '').trim();
  const cleanContent = String(content || '').trim();

  if (isDemoMode) {
    const next = [...loadAnnouncementsFromLocalStorage()];
    next.unshift({
      id: (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function')
        ? crypto.randomUUID()
        : `ann-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      title: cleanTitle,
      content: cleanContent,
      preview: cleanContent,
      date: new Date().toISOString().slice(0, 10),
      created_at: new Date().toISOString()
    });
    saveToStorage('ukonek_announcements', next);
    return true;
  }

  if (isApiMode) {
    const response = await fetch(`${API_BASE}/api/announcements`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: cleanTitle, content: cleanContent })
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Unable to create announcement.');
    }

    return true;
  }

  const { supabase } = await loadSupabaseModule();
  const payload = {
    title: cleanTitle,
    content: cleanContent,
    created_by_staff_id: Number(cachedSessionUser?.id) || null
  };

  const { error } = await supabase.from('announcements').insert(payload);
  if (error) {
    throw new Error(error.message || 'Unable to create announcement.');
  }

  return true;
}

async function updateAnnouncementEntry(announcementId, { title, content }) {
  const cleanTitle = String(title || '').trim();
  const cleanContent = String(content || '').trim();

  if (isDemoMode) {
    const all = loadAnnouncementsFromLocalStorage();
    const next = all.map((item) => {
      if (String(item.id) !== String(announcementId)) return item;
      return {
        ...item,
        title: cleanTitle,
        content: cleanContent,
        preview: cleanContent
      };
    });
    saveToStorage('ukonek_announcements', next);
    return true;
  }

  if (isApiMode) {
    let response = await fetch(`${API_BASE}/api/announcements/${announcementId}`, {
      method: 'PATCH',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: cleanTitle, content: cleanContent })
    });

    if (response.status === 404 || response.status === 405) {
      response = await fetch(`${API_BASE}/api/announcements/${announcementId}`, {
        method: 'PUT',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: cleanTitle, content: cleanContent })
      });
    }

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Unable to update announcement.');
    }

    return true;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('announcements')
    .update({ title: cleanTitle, content: cleanContent })
    .eq('id', Number(announcementId));

  if (error) {
    throw new Error(error.message || 'Unable to update announcement.');
  }

  return true;
}

async function deleteAnnouncementEntry(announcementId) {
  const targetId = String(announcementId || '').trim();
  if (!targetId) {
    throw new Error('Announcement ID is required.');
  }

  if (isDemoMode) {
    const next = loadAnnouncementsFromLocalStorage().filter((item) => String(item.id) !== targetId);
    saveToStorage('ukonek_announcements', next);
    return true;
  }

  if (isApiMode) {
    const response = await fetch(`${API_BASE}/api/announcements/${targetId}`, {
      method: 'DELETE',
      credentials: 'include'
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Unable to delete announcement.');
    }

    return true;
  }

  const { supabase } = await loadSupabaseModule();
  const { error } = await supabase
    .from('announcements')
    .delete()
    .eq('id', Number(targetId));

  if (error) {
    throw new Error(error.message || 'Unable to delete announcement.');
  }

  return true;
}

async function refreshAnnouncementsData() {
  try {
    latestAnnouncementsList = await listAnnouncementsData();
  } catch (error) {
    console.error('Failed to refresh announcements:', error);
    latestAnnouncementsList = [];
  }
  renderAnnouncements();
}

function renderAnnouncements() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;

  tbody.innerHTML = '';
  if (!latestAnnouncementsList.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="3" class="table-cell">No announcements yet.</td>';
    tbody.appendChild(tr);
  }
  latestAnnouncementsList.forEach(a => {
    const tr = document.createElement('tr');
    tr.className = 'announcement-row';
    tr.innerHTML = `
      <td class="table-cell">${a.title}</td>
      <td class="table-cell">${(a.preview || '').substring(0, 80)}${(a.preview || '').length > 80 ? '...' : ''}</td>
      <td class="table-cell">${a.date}</td>
    `;
    tbody.appendChild(tr);
    attachAnnouncementRow(tr, a);
  });
  // Update stats
  if (document.getElementById('stat-announcements')) {
    document.getElementById('stat-announcements').textContent = String(latestAnnouncementsList.length);
  }
}

function openAnnouncementDetailLegacy(announcement) {
  if (!announcementDetailModal) return;
  if (announcementDetailTitle) announcementDetailTitle.textContent = announcement.title || 'Announcement';
  if (announcementDetailBody) announcementDetailBody.textContent = announcement.content || announcement.body || announcement.preview || '—';
  if (announcementDetailDate) announcementDetailDate.textContent = announcement.date || '';
  announcementDetailModal.classList.remove('hidden');
}

function attachAnnouncementRow(row, announcement) {
  if (!row) return;
  if (dataDetailModal) {
    attachDetailRow(row, () => ({
      tag: 'Announcement',
      title: announcement.title || 'Announcement',
      subtitle: announcement.date || '',
      items: [
        { label: 'Title', value: announcement.title || '—' },
        { label: 'Date', value: announcement.date || '—' },
        { label: 'Summary', value: announcement.preview || '—' },
        { label: 'Details', value: announcement.content || announcement.body || announcement.preview || '—' }
      ],
      actions: isAdminUser(cachedSessionUser)
        ? [{
          label: 'Edit',
          className: 'btn',
          onClick: () => openEditAnnouncementModal(announcement)
        }, {
          label: 'Delete',
          className: 'btn btn-delete',
          onClick: async () => {
            const confirmed = window.confirm('Delete this announcement? This cannot be undone.');
            if (!confirmed) return;

            try {
              await deleteAnnouncementEntry(announcement.id);
              await refreshAnnouncementsData();
              renderDashboardInsights();
              closeDataDetail();
              showToast('Announcement deleted successfully.', 'success');
            } catch (error) {
              console.error('Error deleting announcement:', error);
              showToast(error.message || 'Failed to delete announcement.', 'error');
            }
          }
        }]
        : []
    }));
  } else {
    row.style.cursor = 'pointer';
    row.addEventListener('click', () => openAnnouncementDetailLegacy(announcement));
  }
}

function loadFeedbacks() {
  try {
    const raw = localStorage.getItem('ukonek_feedback');
    return raw ? JSON.parse(raw) : DUMMY_FEEDBACKS;
  } catch (err) {
    return DUMMY_FEEDBACKS;
  }
}

function renderFeedbacks() {
  const tbody = document.getElementById('feedback-tbody');
  if (!tbody) return;
  const feedbacks = loadFeedbacks();
  latestFeedbackList = Array.isArray(feedbacks) ? [...feedbacks] : [];
  tbody.innerHTML = '';
  feedbacks.forEach(f => {
    const tr = document.createElement('tr');
    tr.className = 'feedback-row';
    tr.innerHTML = `
      <td class="table-cell">${f.from}</td>
      <td class="table-cell">${f.subject}</td>
      <td class="table-cell">${f.date}</td>
    `;
    tbody.appendChild(tr);
    attachDetailRow(tr, () => ({
      tag: 'Feedback',
      title: f.subject || 'Feedback Detail',
      subtitle: f.from || '',
      items: [
        { label: 'From', value: f.from },
        { label: 'Subject', value: f.subject },
        { label: 'Date', value: f.date },
        { label: 'Rating', value: typeof f.rating !== 'undefined' ? `${f.rating} / 5` : '—' }
      ]
    }));
  });
  // Update stats
  if (document.getElementById('stat-reports')) {
    document.getElementById('stat-reports').textContent = String(feedbacks.length);
  }
}


initClinicalData();

// Consultation form submit
if (consultationForm) {
  consultationForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const patientId = document.getElementById('consult-patient-id').value.trim();
    const symptoms = document.getElementById('consult-symptoms').value.trim();
    const diagnosis = document.getElementById('consult-diagnosis').value.trim();
    const notes = document.getElementById('consult-notes').value.trim();
    if (!patientId || !diagnosis) { showToast('Patient ID and diagnosis required', 'warning'); return; }
    const entry = { id: `C-${Date.now()}`, patientId, symptoms, diagnosis, notes, created_at: new Date().toISOString() };
    consultations.push(entry);
    saveToStorage('ukonek_consultations', consultations);
    renderConsultations();
    if (consultationModal) {
      closeConsultationModal();
    } else {
      consultationForm.reset();
    }
    showToast('Consultation saved', 'success');
  });
}

// Open prescription modal
const consultAddPrescBtn = document.getElementById('consult-add-prescription');
if (consultAddPrescBtn && prescriptionModal) {
  consultAddPrescBtn.addEventListener('click', () => {
    if (prescriptionModal) prescriptionModal.classList.remove('hidden');
    // prefill patient id if available
    const pid = document.getElementById('consult-patient-id')?.value || '';
    if (prescriptionPatient) prescriptionPatient.value = pid;
    prescriptionLines.innerHTML = '';
    addPrescriptionLine();
  });
}

function addPrescriptionLine() {
  const line = document.createElement('div');
  line.className = 'field';
  line.innerHTML = `
    <label class="inputLabel">Medicine</label>
    <select class="pres-med" required>
      ${medicines.map(m => `<option value="${m.name}">${m.name} (${m.unit||''})</option>`).join('')}
    </select>
    <label class="inputLabel">Quantity</label>
    <input type="number" class="pres-qty" value="1" min="1" required />
    <button type="button" class="btn small" data-action="remove-line">Remove</button>
  `;
  prescriptionLines.appendChild(line);
  line.querySelector('[data-action="remove-line"]').addEventListener('click', () => line.remove());
}

if (addPrescriptionLineBtn) addPrescriptionLineBtn.addEventListener('click', addPrescriptionLine);

if (cancelPrescriptionBtn) cancelPrescriptionBtn.addEventListener('click', () => {
  if (prescriptionModal) prescriptionModal.classList.add('hidden');
});

if (prescriptionForm) {
  prescriptionForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const patient = prescriptionPatient.value.trim();
    if (!patient) { showToast('Patient ID required', 'warning'); return; }
    const items = [];
    const selects = prescriptionForm.querySelectorAll('.pres-med');
    const qtys = prescriptionForm.querySelectorAll('.pres-qty');
    for (let i = 0; i < selects.length; i++) {
      const name = selects[i].value;
      const qty = Number(qtys[i].value) || 0;
      if (name && qty > 0) items.push({ name, qty });
    }
    if (items.length === 0) { showToast('Add at least one medicine', 'warning'); return; }
    const pres = { id: `P-${Date.now()}`, patient, items, created_at: new Date().toISOString() };
    prescriptions.push(pres);
    saveToStorage('ukonek_prescriptions', prescriptions);

    // decrement inventory where possible
    items.forEach(it => {
      const idx = medicines.findIndex(m => m.name === it.name);
      if (idx >= 0) {
        medicines[idx].qty = Math.max(0, Number(medicines[idx].qty) - Number(it.qty));
      }
    });
    saveToStorage('ukonek_medicine_inventory', medicines);
    renderMedicines();

    if (prescriptionModal) prescriptionModal.classList.add('hidden');
    showToast('Prescription created and inventory updated', 'success');
  });
}

// Medicine form submit
if (medicineForm) {
  medicineForm.addEventListener('submit', (e) => {
    e.preventDefault();
    if (!canAddNewMedicine()) {
      showToast('You only have view access to the inventory.', 'warning');
      return;
    }
    const name = document.getElementById('med-name').value.trim();
    const qty = Number(document.getElementById('med-qty').value) || 0;
    const unit = document.getElementById('med-unit').value.trim();
    if (!name) { showToast('Medicine name required', 'warning'); return; }
    const idx = medicines.findIndex(m => m.name.toLowerCase() === name.toLowerCase());
    if (idx >= 0) {
      medicines[idx].qty = Number(medicines[idx].qty) + qty; // treat as adding stock
      medicines[idx].unit = unit || medicines[idx].unit;
    } else {
      medicines.push({ name, qty, unit });
    }
    saveToStorage('ukonek_medicine_inventory', medicines);
    renderMedicines();
    medicineForm.reset();
    showToast('Medicine added/updated', 'success');
  });
}

// medicine +/- actions
if (medicineTbody) {
  medicineTbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (!btn) return;
    const action = btn.getAttribute('data-action');
    const name = btn.getAttribute('data-name');
    if (!action || !name) return;
    if (!canAdjustMedicineInventory()) {
      showToast('You only have view access to the inventory.', 'warning');
      return;
    }
    const idx = medicines.findIndex(m => m.name === name);
    if (idx < 0) return;
    if (action === 'add') {
      const add = Number(prompt('Enter quantity to add', '1')) || 0;
      medicines[idx].qty = Number(medicines[idx].qty) + add;
    } else if (action === 'sub') {
      const sub = Number(prompt('Enter quantity to subtract', '1')) || 0;
      medicines[idx].qty = Math.max(0, Number(medicines[idx].qty) - sub);
    }
    saveToStorage('ukonek_medicine_inventory', medicines);
    renderMedicines();
  });
}

// Consultations table actions (view/prescribe)
if (consultationsTbody) {
  consultationsTbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (!btn) return;
    const action = btn.getAttribute('data-action');
    const id = btn.getAttribute('data-id');
    const entry = consultations.find(c => c.id === id);
    if (!action || !entry) return;
    if (action === 'view') {
      openDataDetail({
        tag: 'Consultation',
        title: entry.patientId || 'Consultation Detail',
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
      if (prescriptionModal) prescriptionModal.classList.remove('hidden');
      if (prescriptionPatient) prescriptionPatient.value = entry.patientId || '';
      prescriptionLines.innerHTML = '';
      addPrescriptionLine();
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
    const headers = ['ID', 'Patient', 'Diagnosis', 'Date'];
    const rows = consultations.map(c => [c.id, c.patientId, c.diagnosis, formatDateTime(c.created_at)]);
    generateReport('Consultations Report', headers, rows);
  });
}

if (medicineReportBtn) {
  medicineReportBtn.addEventListener('click', () => {
    const headers = ['Medicine', 'Quantity', 'Unit'];
    const rows = medicines.map(m => [m.name, m.qty, m.unit || '']);
    generateReport('Medicine Inventory Report', headers, rows);
  });
}

// Expose report generation for other entities
function generateUsersReport() {
  const rows = latestStaffList.map(u => [u.username || '', u.employee_id || '', u.role || '', u.status || '']);
  generateReport('Users Report', ['Username', 'Employee ID', 'Role', 'Status'], rows);
}

function generateCitizensReport() {
  const rows = latestPatientsList.map(c => [c.username || c.name || '', c.email || '', c.created_at || '']);
  generateReport('Citizens Report', ['Username', 'Email', 'Registered'], rows);
}

// wire up simple global report triggers (if buttons exist elsewhere)
const usersReportBtn = document.getElementById('users-report-btn');
if (usersReportBtn) usersReportBtn.addEventListener('click', generateUsersReport);

const citizensReportBtn = document.getElementById('citizens-report-btn');
if (citizensReportBtn) citizensReportBtn.addEventListener('click', generateCitizensReport);
