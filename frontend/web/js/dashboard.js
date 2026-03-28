const sidebar = document.getElementById('sidebar');
const burger = document.getElementById('burger');

// No backend - static/localStorage only
const API_BASE = '';
const isDemoMode = !API_BASE;

let cachedSessionUser = null;
let sessionUserRole = null;

function detectRoleFromTitle() {
  const title = document.title.toLowerCase();
  if (title.includes('admin')) return 'admin';
  if (title.includes('specialist')) return 'specialist';
  return 'staff';
}

const DEMO_REGISTERED_USERS = [
  {
    username: 'asmith',
    first_name: 'Alice',
    last_name: 'Smith',
    employee_id: 'UK-1001',
    role: 'doctor',
    status: 'Active',
    created_at: '2024-11-05T09:00:00Z',
    email: 'asmith@ukonek.local',
    birthday: '1990-03-02'
  },
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

const DEMO_PENDING_USERS = [
  {
    username: 'dramos',
    first_name: 'Dan',
    last_name: 'Ramos',
    employee_id: 'UK-2031',
    role: 'doctor',
    email: 'dramos@ukonek.local',
    created_at: '2024-12-12T04:00:00Z',
    specialization: 'Cardiology',
    schedule: JSON.stringify({ days: ['Tue', 'Thu'], startHour: 9, endHour: 12 })
  },
  {
    username: 'mgalang',
    first_name: 'Mira',
    last_name: 'Galang',
    employee_id: 'UK-2037',
    role: 'nurse',
    email: 'mgalang@ukonek.local',
    created_at: '2024-12-15T07:45:00Z',
    specialization: 'Community Health',
    schedule: JSON.stringify({ days: ['Mon', 'Wed', 'Fri'], startHour: 8, endHour: 11 })
  }
];

const DEMO_CITIZENS = [
  {
    username: 'jmendoza',
    email: 'jmendoza@example.com',
    created_at: '2024-10-05T13:25:00Z',
    status: 'Active'
  },
  {
    username: 'ldelacruz',
    email: 'ldelacruz@example.com',
    created_at: '2024-09-18T06:15:00Z',
    status: 'Active'
  },
  {
    username: 'rkho',
    email: 'rkho@example.com',
    created_at: '2024-11-20T16:40:00Z',
    status: 'Inactive'
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
  // Static demo - just reload/redirect
  window.location.replace('./index.html');
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

if (logoutBtn) {
  logoutBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      logoutConfirmModal.style.display = 'flex';
      return;
    }
    performLogout();
  });
}

if (logoutConfirmYesBtn) {
  logoutConfirmYesBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      logoutConfirmModal.style.display = 'none';
    }
    performLogout();
  });
}

if (logoutConfirmNoBtn) {
  logoutConfirmNoBtn.addEventListener('click', () => {
    if (logoutConfirmModal) {
      logoutConfirmModal.style.display = 'none';
    }
  });
}

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

  const role = detectRoleFromTitle();
  const profile = {
    role,
    username: 'Demo User',
    email: 'demo@ukonek.local',
    first_name: 'Demo',
    status: 'active'
  };

  cachedSessionUser = profile;
  sessionUserRole = role;
  return profile;
}

function getSessionRole() {
  return (sessionUserRole || detectRoleFromTitle()).toLowerCase();
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

  hideAllSections();
  clearActiveNav();
  updateNonAdminWorkspace(user);
  if (nonAdminSection) nonAdminSection.classList.remove('hidden');
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

    // Close all dropdowns first
    document.querySelectorAll('.dropdown-menu').forEach(m => m.classList.add('hidden'));

    // Toggle dropdown if clicking nav-btn
    if (isDropdownBtn && parentItem) {
      const menu = parentItem.querySelector('.dropdown-menu');
      if (menu) menu.classList.toggle('hidden');
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
    const timeStamp = item.date ? item.date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : 'Today';
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

  const targetSection = document.getElementById(sectionId);
  if (targetSection) {
    targetSection.classList.remove('hidden');
    
    // Dynamic refresh for section content
    const user = await ensureAuthenticatedSession();
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
      toggleUsersPane(pane || 'accounts-pane');
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

let pendingRegistrationProfile = null;

// --- ADD THESE MISSING DEFINITIONS AT THE TOP OF YOUR SCRIPT ---
const registerForm = document.getElementById('register-form');
const registerSubmitBtn = document.getElementById('register-submit-btn');
const registerOtpModal = document.getElementById('register-otp-modal');
const registerOtpForm = document.getElementById('register-otp-form');
const otpModalCloseBtn = document.getElementById('otp-modal-close-btn');
const otpCompleteBtn = document.getElementById('otp-complete-btn');
const registrationSuccessModal = document.getElementById('registration-success-modal');
const regSuccessDashboardBtn = document.getElementById('reg-success-dashboard-btn');
const regSuccessUsersBtn = document.getElementById('reg-success-users-btn');
const backToDashboardBtn = document.getElementById('back-to-dashboard-btn');
const registrationBackBtn = document.getElementById('registration-back-btn');
const registerResendOtpBtn = document.getElementById('register-resend-otp-btn');

// --- FIXED REGISTRATION HANDLER ---
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
    const email = document.getElementById('reg-email').value.trim();
    const role = document.getElementById('reg-role').value;

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

    if (!first_name || !last_name || !email || !role) {
      if (err) {
        err.textContent = 'Please fill in all required fields.';
        err.style.display = 'block';
      }
      return;
    }

    // Visual feedback
    if (registerSubmitBtn) {
      registerSubmitBtn.disabled = true;
      const label = registerSubmitBtn.querySelector('.btn-label');
      if (label) label.textContent = 'SENDING OTP...';
    }

    try {
      const payload = { first_name, middle_name, last_name, birthday, gender, employee_id, email, role };

      if (isDemoMode) {
        await demoDelay();
        pendingRegistrationProfile = payload;
        if (registerOtpModal) registerOtpModal.classList.remove('hidden');
        if (success) {
          success.textContent = 'Demo OTP sent. Please continue in the modal.';
          success.style.display = 'block';
        }
        showToast('Demo OTP sent to email', 'info');
      } else {
        const response = await fetch(`${API_BASE}/api/staff/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
          credentials: 'include'
        });

        const data = await response.json();
        if (!response.ok) throw new Error(data.message || 'Registration failed');

        pendingRegistrationProfile = payload;
        if (registerOtpModal) registerOtpModal.classList.remove('hidden');
        if (success) {
          success.textContent = data.message || 'OTP sent to email.';
          success.style.display = 'block';
        }
        showToast('OTP sent to email', 'info');
      }

    } catch (error) {
      if (err) {
        err.textContent = error.message || 'Unable to submit registration.';
        err.style.display = 'block';
      }
    } finally {
      if (registerSubmitBtn) {
        registerSubmitBtn.disabled = false;
        const label = registerSubmitBtn.querySelector('.btn-label');
        if (label) label.textContent = 'SEND OTP';
      }
    }
  });
}

// OTP Modal handlers
if (otpModalCloseBtn) {
  otpModalCloseBtn.addEventListener('click', () => {
    if (registerOtpModal) registerOtpModal.classList.add('hidden');
  });
}

if (registerOtpModal) {
  registerOtpModal.addEventListener('click', (event) => {
    if (event.target === registerOtpModal) {
      registerOtpModal.classList.add('hidden');
    }
  });
}

if (registerOtpForm) {
  registerOtpForm.addEventListener('submit', async (event) => {
    event.preventDefault();

    const otpModalError = document.getElementById('otp-modal-error');
    const otpModalSuccess = document.getElementById('otp-modal-success');
    const otp = document.getElementById('reg-otp').value.trim();
    const username = document.getElementById('reg-username').value.trim();
    const password = document.getElementById('reg-password').value;
    const confirmPassword = document.getElementById('reg-confirm-password').value;
    const consentGiven = document.getElementById('reg-consent').checked;

    if (otpModalError) otpModalError.style.display = 'none';
    if (otpModalSuccess) otpModalSuccess.style.display = 'none';

    if (!pendingRegistrationProfile || !pendingRegistrationProfile.email) {
      if (otpModalError) {
        otpModalError.textContent = 'No active registration request found. Please send OTP again.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (!/^\d{6}$/.test(otp)) {
      if (otpModalError) {
        otpModalError.textContent = 'Please enter a valid 6-digit OTP.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (!username || !password || !confirmPassword) {
      if (otpModalError) {
        otpModalError.textContent = 'Username, password, and confirm password are required.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (password !== confirmPassword) {
      if (otpModalError) {
        otpModalError.textContent = 'Passwords do not match.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (!consentGiven) {
      if (otpModalError) {
        otpModalError.textContent = 'Consent is required to continue.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (otpCompleteBtn) {
      otpCompleteBtn.disabled = true;
      const otpLabel = otpCompleteBtn.querySelector('.btn-label');
      if (otpLabel) otpLabel.textContent = 'CREATING ACCOUNT...';
    }

    try {
      if (isDemoMode) {
        await demoDelay();

        if (registerOtpModal) registerOtpModal.classList.add('hidden');
        if (registerForm) registerForm.reset();
        registerOtpForm.reset();

        const demoUser = {
          username,
          first_name: pendingRegistrationProfile?.first_name || username,
          last_name: pendingRegistrationProfile?.last_name || '',
          employee_id: pendingRegistrationProfile?.employee_id || `UK-${Date.now()}`,
          role: pendingRegistrationProfile?.role || 'staff',
          status: 'Active',
          created_at: new Date().toISOString(),
          email: pendingRegistrationProfile?.email || `${username}@demo.local`,
          birthday: pendingRegistrationProfile?.birthday || ''
        };

        DEMO_REGISTERED_USERS.unshift(demoUser);
        const pendingIndex = DEMO_PENDING_USERS.findIndex((entry) => entry.employee_id === demoUser.employee_id);
        if (pendingIndex > -1) DEMO_PENDING_USERS.splice(pendingIndex, 1);
        storedAccounts.clear();
        await Promise.all([loadStaffData(), loadPendingStaffData()]);

        pendingRegistrationProfile = null;
        if (registrationSuccessModal) registrationSuccessModal.classList.remove('hidden');
        showToast('Demo account created.', 'success');
        return;
      }

      const completeResponse = await fetch(`${API_BASE}/api/staff/complete-registration`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: pendingRegistrationProfile.email,
          otp,
          username,
          password,
          confirmPassword,
          consentGiven
        })
      });

      const completeData = await completeResponse.json();

      if (!completeResponse.ok) {
        if (otpModalError) {
          otpModalError.textContent = completeData.message || 'Unable to complete registration.';
          otpModalError.style.display = 'block';
        }
        return;
      }

      if (registerOtpModal) registerOtpModal.classList.add('hidden');
      if (registerForm) registerForm.reset();
      registerOtpForm.reset();
      pendingRegistrationProfile = null;

      if (registrationSuccessModal) registrationSuccessModal.classList.remove('hidden');
    } catch (error) {
      console.error('Error:', error);
      if (otpModalError) {
        otpModalError.textContent = 'Server connection failed.';
        otpModalError.style.display = 'block';
      }
    } finally {
      if (otpCompleteBtn) {
        otpCompleteBtn.disabled = false;
        const otpLabel = otpCompleteBtn.querySelector('.btn-label');
        if (otpLabel) otpLabel.textContent = 'COMPLETE REGISTRATION';
      }
    }
  });
}

// Resend OTP
if (registerResendOtpBtn) {
  registerResendOtpBtn.addEventListener('click', async (event) => {
    event.preventDefault();

    if (registerResendOtpBtn.getAttribute('aria-disabled') === 'true') return;

    const err = document.getElementById('register-error');
    const otpModalError = document.getElementById('otp-modal-error');
    const otpModalSuccess = document.getElementById('otp-modal-success');

    if (!pendingRegistrationProfile) {
      if (otpModalError) {
        otpModalError.textContent = 'No active registration request found. Please send OTP again.';
        otpModalError.style.display = 'block';
      }
      return;
    }

    if (err) err.style.display = 'none';
    if (otpModalError) otpModalError.style.display = 'none';
    if (otpModalSuccess) otpModalSuccess.style.display = 'none';

    registerResendOtpBtn.setAttribute('aria-disabled', 'true');
    registerResendOtpBtn.style.pointerEvents = 'none';
    registerResendOtpBtn.style.opacity = '0.65';
    registerResendOtpBtn.textContent = 'Sending...';

    try {
      if (isDemoMode) {
        await demoDelay();
        if (otpModalSuccess) {
          otpModalSuccess.style.display = 'block';
          otpModalSuccess.textContent = 'Demo OTP resent. Please check email.';
        }
        showToast('Demo OTP resent.', 'info');
      } else {
        const response = await fetch(`${API_BASE}/api/staff/register`, {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(pendingRegistrationProfile)
        });
        const data = await response.json();

        if (!response.ok) {
          if (otpModalError) {
            otpModalError.textContent = data.message || 'Failed to resend OTP.';
            otpModalError.style.display = 'block';
          }
          return;
        }

        if (otpModalSuccess) {
          otpModalSuccess.style.display = 'block';
          otpModalSuccess.textContent = data.message || 'OTP resent. Please check email.';
        }
      }
    } catch (error) {
      console.error('Error:', error);
      if (otpModalError) {
        otpModalError.textContent = 'Server connection failed.';
        otpModalError.style.display = 'block';
      }
    } finally {
      registerResendOtpBtn.setAttribute('aria-disabled', 'false');
      registerResendOtpBtn.style.pointerEvents = '';
      registerResendOtpBtn.style.opacity = '';
      registerResendOtpBtn.textContent = 'Resend OTP';
    }
  });
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
    navigateToSection('users-section', { pane: 'accounts-pane', tab: 'tab-registered' });
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
    const defaultUsersTab = document.getElementById('tab-registered');
    if (defaultUsersTab) defaultUsersTab.click();
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
  const preview = document.getElementById('profile-pic-preview');

  if (name) name.value = user?.first_name || user?.username || '';
  if (email) email.value = user?.email || '';
  if (role) role.value = toTitleCase(user?.role || '');

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
    const fileInput = document.getElementById('profile-pic');

    const form = new FormData();
    form.append('displayName', name);
    form.append('email', email);
    if (fileInput && fileInput.files && fileInput.files[0]) {
      form.append('avatar', fileInput.files[0]);
    }

    try {
      const resp = await fetch(`${API_BASE}/api/staff/profile`, {
        method: 'POST',
        credentials: 'include',
        body: form
      });
      if (!resp.ok) throw new Error('Failed to save profile');
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

// --- Schedule handling (simple calendar + list). Admins can create/update/delete; others view only ---
async function loadSchedules(user) {
  let schedules = [];
  try {
    const resp = await fetch(`${API_BASE}/api/schedules`, { credentials: 'include' });
    if (resp.ok) schedules = await resp.json();
    else schedules = [];
  } catch (err) {
    // fallback demo data - now richer
    schedules = DUMMY_SCHEDULES;
  }
  renderSchedules(schedules, user);
}

function renderSchedules(schedules, user) {
  const tbody = document.getElementById('schedule-tbody');
  const calendar = document.getElementById('calendar-container');
  if (!tbody || !calendar) return;
  tbody.innerHTML = '';
  calendar.innerHTML = '';

  // Simple calendar: show upcoming dates as buttons (read-only)
  const dates = [...new Set(schedules.map(s => s.date))];
  const dateList = document.createElement('div');
  dateList.style.display = 'flex';
  dateList.style.gap = '8px';
  dates.forEach(d => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip-btn';
    btn.textContent = d;
    btn.addEventListener('click', () => {
      // filter table to date
      Array.from(tbody.querySelectorAll('tr')).forEach(tr => {
        tr.style.display = tr.dataset.date === d ? '' : 'none';
      });
    });
    dateList.appendChild(btn);
  });
  calendar.appendChild(dateList);

  schedules.forEach(s => {
    const tr = document.createElement('tr');
    tr.dataset.date = s.date;
    tr.innerHTML = `
      <td class="table-cell">${s.doctor}</td>
      <td class="table-cell">${s.date}</td>
      <td class="table-cell">${s.time}</td>
      <td class="table-cell"></td>
    `;
    const actionsTd = tr.querySelector('td:last-child');
    if (isAdminUser(user)) {
      const editBtn = document.createElement('button');
      editBtn.className = 'btn small outline admin-only';
      editBtn.textContent = 'Edit';
      editBtn.addEventListener('click', () => openScheduleModal('edit', s));

      const delBtn = document.createElement('button');
      delBtn.className = 'btn small btn-delete admin-only';
      delBtn.textContent = 'Delete';
      delBtn.addEventListener('click', async () => {
        if (!confirm('Delete this schedule?')) return;
        try {
          const resp = await fetch(`${API_BASE}/api/schedules/${s.id}`, { method: 'DELETE', credentials: 'include' });
          if (!resp.ok) throw new Error('Delete failed');
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
      title: s.doctor || 'Schedule Detail',
      subtitle: s.date ? `${s.date} • ${s.time || ''}`.trim() : s.time || '',
      items: [
        { label: 'Doctor', value: s.doctor },
        { label: 'Date', value: s.date },
        { label: 'Time', value: s.time },
        { label: 'Schedule ID', value: s.id || '—' }
      ]
    }));
  });

  // enforce hiding of admin-only controls if not admin
  const sessionUserCheck = async () => {
    const sessionUser = await ensureAuthenticatedSession();
    if (!isAdminUser(sessionUser)) {
      document.querySelectorAll('.admin-only').forEach(e => e.classList.add('hidden'));
    } else {
      document.querySelectorAll('.admin-only').forEach(e => e.classList.remove('hidden'));
    }
  };
  sessionUserCheck();
}

// Schedule editor modal logic
function openScheduleModal(mode = 'create', schedule = null) {
  const modal = document.getElementById('schedule-editor-modal');
  const form = document.getElementById('schedule-form');
  const idInput = document.getElementById('sched-id');
  const doctorInput = document.getElementById('sched-doctor');
  const dateInput = document.getElementById('sched-date');
  const timeInput = document.getElementById('sched-time');
  const deleteBtn = document.getElementById('sched-delete-btn');
  const errorNode = document.getElementById('sched-form-error');

  if (!modal || !form) return;
  errorNode.textContent = '';
  if (mode === 'edit' && schedule) {
    idInput.value = schedule.id || '';
    doctorInput.value = schedule.doctor || '';
    dateInput.value = schedule.date || '';
    timeInput.value = schedule.time || '';
    deleteBtn.classList.remove('hidden');
  } else {
    idInput.value = '';
    doctorInput.value = '';
    dateInput.value = '';
    timeInput.value = '';
    deleteBtn.classList.add('hidden');
  }

  modal.classList.remove('hidden');
}

function closeScheduleModal() {
  const modal = document.getElementById('schedule-editor-modal');
  if (modal) modal.classList.add('hidden');
}

// submit handler
const schedForm = document.getElementById('schedule-form');
if (schedForm) {
  schedForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = document.getElementById('sched-id').value;
    const doctor = document.getElementById('sched-doctor').value.trim();
    const date = document.getElementById('sched-date').value;
    const time = document.getElementById('sched-time').value.trim();
    const errorNode = document.getElementById('sched-form-error');
    errorNode.textContent = '';

    if (!doctor || !date || !time) {
      errorNode.textContent = 'All fields are required.';
      return;
    }

    try {
      const url = id ? `${API_BASE}/api/schedules/${id}` : `${API_BASE}/api/schedules`;
      const method = id ? 'PUT' : 'POST';
      const resp = await fetch(url, {
        method,
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ doctor, date, time })
      });
      if (!resp.ok) {
        const data = await resp.json().catch(() => ({}));
        throw new Error(data.message || 'Failed to save schedule');
      }
      showToast(id ? 'Schedule updated' : 'Schedule created', 'success');
      closeScheduleModal();
      initProfileAndSchedule();
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
      const resp = await fetch(`${API_BASE}/api/schedules/${id}`, { method: 'DELETE', credentials: 'include' });
      if (!resp.ok) throw new Error('Delete failed');
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

function initializeDashboard() {
  // Master init - call all content population functions
  initProfileAndSchedule();
  initClinicalData();
  renderAnnouncements();
  renderFeedbacks();
  initDashboardData();

  // Auto-activate dashboard section
  const dashboardSectionEl = document.getElementById('dashboard-section');
  const dashboardNavItem = document.querySelector('[data-section="dashboard-section"]');
  if (dashboardSectionEl) dashboardSectionEl.classList.remove('hidden');
  if (dashboardNavItem) dashboardNavItem.classList.add('is-active');
}

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  initializeDashboard();
  navigateToSection('dashboard-section');
});



// Nav-related elements (keep globals for other code)
const dashboardSection = document.getElementById('dashboard-section');
const usersSection = document.getElementById('users-section');
const reportsSection = document.getElementById('reports-section');
const newRegistrationSection = document.getElementById('new-registration');

const statTotalStaff = document.getElementById('stat-total-staff');
const statPendingStaff = document.getElementById('stat-pending-staff');
const statDoctors = document.getElementById('stat-doctors');
const statActiveStaff = document.getElementById('stat-active-staff');
const statAnnouncements = document.getElementById('stat-announcements');
const statReports = document.getElementById('stat-reports');
const statCitizens = document.getElementById('stat-citizens');
const dashboardPendingPreview = document.getElementById('dashboard-pending-preview');
const dashboardActivePreview = document.getElementById('dashboard-active-preview');
const dashboardLastSync = document.getElementById('dashboard-last-sync');

const dashRefreshBtn = document.getElementById('dash-refresh-btn');
const dashOpenPendingBtn = document.getElementById('dash-open-pending-btn');
const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');
const citizensTbody = document.getElementById('citizens-tbody');
const citizensPane = document.getElementById('citizens-pane');
const userPaneIds = ['accounts-pane', 'registration-pane'];
const chartAnimationState = { frameId: null };

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
  hideAllSections();
  clearActiveNav();
  showSection(sectionId, options);
  const navMatch = document.querySelector(`.nav [data-section="${sectionId}"]`);
  if (navMatch) navMatch.classList.add('is-active');
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
  reportsRefreshBtn.addEventListener('click', () => {
    showToast('Reports data refreshed (placeholder).', 'info');
  });
}

// Create announcement modal handlers
const createAnnouncementBtn = document.getElementById('create-announcement-btn');
const createAnnouncementModal = document.getElementById('create-announcement-modal');
const createAnnouncementForm = document.getElementById('create-announcement-form');
const annSubmitBtn = document.getElementById('ann-submit-btn');
const annCancelBtn = document.getElementById('ann-cancel-btn');
const annFormError = document.getElementById('ann-form-error');

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

    // Placeholder API call
    try {
      showToast('Announcement created successfully (placeholder).', 'success');
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
    return Number.isNaN(value.getTime()) ? '—' : value.toLocaleString();
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
let latestPendingList = [];
let latestCitizensList = [];
let latestAnnouncementsList = [];
let latestFeedbackList = [];

function formatDateTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString();
}

function renderDashboardInsights() {
  if (statTotalStaff) statTotalStaff.textContent = String(latestStaffList.length);
  if (statPendingStaff) statPendingStaff.textContent = String(latestPendingList.length);

  if (!latestAnnouncementsList.length) {
    latestAnnouncementsList = loadAnnouncements();
  }
  const announcementsCount = latestAnnouncementsList.length || 0;
  if (statAnnouncements) statAnnouncements.textContent = String(announcementsCount);

  if (!latestFeedbackList.length) {
    latestFeedbackList = loadFeedbacks();
  }
  const feedbackCount = latestFeedbackList.length || 0;
  if (statReports) statReports.textContent = String(feedbackCount);

  // Citizens count
  if (statCitizens) statCitizens.textContent = String(latestCitizensList.length || 0);

  const doctorsCount = latestStaffList.filter((user) => String(user.role || '').toLowerCase() === 'doctor').length;
  if (statDoctors) statDoctors.textContent = String(doctorsCount);

  const activeCount = latestStaffList.filter((user) => String(user.status || '').toLowerCase() === 'active').length;
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

  renderDashboardChart();
}

function renderDashboardChart() {
  const canvas = document.getElementById('dashboard-chart');
  const emptyNode = document.getElementById('dashboard-chart-empty');
  const legendList = document.getElementById('dashboard-chart-legend');
  if (!canvas || typeof canvas.getContext !== 'function') return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  if (!latestAnnouncementsList.length) latestAnnouncementsList = loadAnnouncements();
  if (!latestFeedbackList.length) latestFeedbackList = loadFeedbacks();

  const metrics = [
    { label: 'Staff', value: latestStaffList.length, color: '#3b82f6' },
    { label: 'Pending', value: latestPendingList.length, color: '#f97316' },
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
async function loadCitizenData() {
  let list = [];

  if (isDemoMode) {
    list = DEMO_CITIZENS;
  } else {
    try {
      const response = await fetch(`${API_BASE}/api/citizens`, { credentials: 'include' });
      if (response && response.ok) {
        list = await response.json();
      }
    } catch (error) {
      console.error('Error loading citizens:', error);
      list = DEMO_CITIZENS;
    }
  }

  latestCitizensList = Array.isArray(list) ? [...list] : [];

  if (citizensTbody) {
    citizensTbody.innerHTML = '';
    if (latestCitizensList.length === 0) {
      citizensTbody.innerHTML = '<tr><td class="table-cell" colspan="4">No citizen accounts found.</td></tr>';
    } else {
      latestCitizensList.forEach(user => {
        const row = document.createElement('tr');
        row.innerHTML = `
          <td class="table-cell">${user.username || user.name || '—'}</td>
          <td class="table-cell">${user.email || '—'}</td>
          <td class="table-cell">${user.created_at ? new Date(user.created_at).toLocaleString() : '—'}</td>
          <td class="table-cell">${user.status || '—'}</td>
        `;
        citizensTbody.appendChild(row);
        attachDetailRow(row, () => ({
          tag: 'Citizens',
          title: user.username || user.name || 'Citizen Account',
          subtitle: user.email || '',
          items: [
            { label: 'Username', value: user.username || user.name || '—' },
            { label: 'Email', value: user.email || '—' },
            { label: 'Registered', value: user.created_at ? new Date(user.created_at) : '—' },
            { label: 'Status', value: user.status || '—' }
          ]
        }));
      });
    }
  }
}

async function loadStaffData() {
  let staffList = [];

  if (isDemoMode) {
    staffList = DEMO_REGISTERED_USERS;
  } else {
    try {
      const response = await fetch(`${API_BASE}/api/staff`, { credentials: 'include' });
      if (!response.ok) throw new Error('Failed to fetch staff');
      staffList = await response.json();
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
      accountsTbody.innerHTML = '<tr><td class="table-cell" colspan="4">No registered staff accounts found.</td></tr>';
    } else {
      latestStaffList.forEach(user => {
        const identifier = user.username || user.employee_id || makeDemoId();
        storedAccounts.set(identifier, user);

        const roleValue = user.role ? String(user.role) : '';
        const roleLabel = roleValue ? roleValue.charAt(0).toUpperCase() + roleValue.slice(1) : '—';
        const statusValue = user.status ? String(user.status) : 'Active';
        const statusSlug = statusValue.toLowerCase().replace(/\s+/g, '-');

        const row = document.createElement('tr');
        row.className = 'account-row';
        row.setAttribute('data-role', roleValue ? roleValue.toLowerCase() : '');
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">${user.username || '—'}</td>
          <td class="table-cell">${user.employee_id || '—'}</td>
          <td class="table-cell">${roleLabel}</td>
          <td class="table-cell"><span class="badge-${statusSlug}">${statusValue}</span></td>
        `;
        accountsTbody.appendChild(row);
        attachAccountRowListener(row);
      });
    }
  }

  renderDashboardInsights();
}

async function loadPendingStaffData() {
  let pendingList = [];

  if (isDemoMode) {
    pendingList = DEMO_PENDING_USERS;
  } else {
    try {
      const response = await fetch(`${API_BASE}/api/staff/pending`, { credentials: 'include' });
      if (!response.ok) throw new Error('Failed to fetch pending staff');
      pendingList = await response.json();
    } catch (error) {
      console.error('Error loading pending staff:', error);
      pendingList = DEMO_PENDING_USERS;
    }
  }

  latestPendingList = Array.isArray(pendingList) ? [...pendingList] : [];

  const pendingTbody = document.getElementById('pending-tbody');
  if (pendingTbody) {
    pendingTbody.innerHTML = '';
    if (latestPendingList.length === 0) {
      pendingTbody.innerHTML = '<tr><td class="table-cell" colspan="4">No pending registrations.</td></tr>';
    } else {
      latestPendingList.forEach(user => {
        const identifier = user.username || user.employee_id || makeDemoId();
        storedAccounts.set(identifier, user);

        const roleValue = user.role ? String(user.role) : '';
        const roleLabel = roleValue ? roleValue.charAt(0).toUpperCase() + roleValue.slice(1) : '—';
        const createdValue = user.created_at ? new Date(user.created_at).toLocaleString() : '—';

        const row = document.createElement('tr');
        row.className = 'pending-row';
        row.setAttribute('data-role', roleValue ? roleValue.toLowerCase() : '');
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">${user.username || '—'}</td>
          <td class="table-cell">${user.employee_id || '—'}</td>
          <td class="table-cell">${roleLabel}</td>
          <td class="table-cell">${createdValue}</td>
        `;
        pendingTbody.appendChild(row);
        attachPendingRowListener(row);
      });
    }
  }

  renderDashboardInsights();
}

// Initial load (after auth check)
async function initDashboardData() {
  const sessionUser = await ensureAuthenticatedSession();
  if (!sessionUser) return;

  applyRoleAccess(sessionUser);

  if (!isAdminUser(sessionUser)) {
    return;
  }

  if (dashboardSection) dashboardSection.classList.remove('hidden');
  if (dashboardLink) dashboardLink.classList.add('is-active');
  storedAccounts.clear();
  await Promise.all([loadStaffData(), loadPendingStaffData(), loadCitizenData()]);
  // Refresh counts after all data loaded
  renderDashboardInsights();
}

initDashboardData();

if (dashRefreshBtn) {
  dashRefreshBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPendingStaffData(), loadCitizenData()]);
    showToast('Dashboard data refreshed.', 'info');
  });
}

if (dashOpenPendingBtn) {
  dashOpenPendingBtn.addEventListener('click', () => {
    navigateToSection('users-section', { pane: 'accounts-pane', tab: 'tab-pending' });
  });
}

if (refreshAccountsBtn) {
  refreshAccountsBtn.addEventListener('click', async () => {
    storedAccounts.clear();
    await Promise.all([loadStaffData(), loadPendingStaffData(), loadCitizenData()]);
    showToast('Account tables refreshed.', 'info');
  });
}

// Utility validation functions
function validateEmail(email) {
  return /.+@.+\..+/.test(email);
}

// Role filter functionality
const roleFilter = document.getElementById('role-filter');
if (roleFilter) {
  roleFilter.addEventListener('change', (e) => {
    const filterValue = e.target.value.toLowerCase();
    const accountRows = document.querySelectorAll('.account-row');

    accountRows.forEach(row => {
      const role = row.getAttribute('data-role');
      if (filterValue === '' || role === filterValue) {
        row.style.display = '';
      } else {
        row.style.display = 'none';
      }
    });
  });
}

// Modal state
let currentAccountData = null;
let currentAction = null; // 'edit' or 'delete'

function openAccountModal(user) {
  if (!user) return;
  const modal = document.getElementById('account-modal');
  if (!modal) return;

  currentAccountData = { ...user };

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
  if (modalStatus) modalStatus.textContent = user.status || '—';
  if (modalContact) modalContact.textContent = user.employee_id || '—';
  if (modalBday) modalBday.textContent = birthdayText;

  ['address'].forEach(field => {
    const el = document.getElementById(`modal-${field}`);
    if (el) el.textContent = user[field] || '—';
  });

  if (confirmSection) confirmSection.style.display = 'none';
  if (modalActions) modalActions.style.display = 'flex';

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
    const statusValue = user.status || '—';
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

// attach listeners to any existing pending rows (none initially)
document.querySelectorAll('.pending-row').forEach(attachPendingRowListener);

// Tab switching (Registered / Pending / Citizens)
const tabRegistered = document.getElementById('tab-registered');
const tabPending = document.getElementById('tab-pending');
const tabCitizens = document.getElementById('tab-citizens');
const registeredPane = document.getElementById('registered-pane');
const pendingPane = document.getElementById('pending-pane');
const citizensPaneEl = document.getElementById('citizens-pane');
if (tabRegistered && tabPending && registeredPane && pendingPane && tabCitizens && citizensPaneEl) {
  tabRegistered.addEventListener('click', () => {
    tabRegistered.classList.add('active');
    tabPending.classList.remove('active');
    tabCitizens.classList.remove('active');
    registeredPane.classList.remove('hidden');
    pendingPane.classList.add('hidden');
    citizensPaneEl.classList.add('hidden');
  });
  tabPending.addEventListener('click', () => {
    tabPending.classList.add('active');
    tabRegistered.classList.remove('active');
    tabCitizens.classList.remove('active');
    pendingPane.classList.remove('hidden');
    registeredPane.classList.add('hidden');
    citizensPaneEl.classList.add('hidden');
  });
  tabCitizens.addEventListener('click', () => {
    tabCitizens.classList.add('active');
    tabRegistered.classList.remove('active');
    tabPending.classList.remove('active');
    citizensPaneEl.classList.remove('hidden');
    registeredPane.classList.add('hidden');
    pendingPane.classList.add('hidden');
  });
}

// Pending modal logic
function attachPendingRowListener(row) {
  row.addEventListener('click', () => {
    const identifier = row.getAttribute('data-id');
    const stored = storedAccounts.get(identifier);
    if (!stored) {
      console.error('Pending account data not found for:', identifier);
      return;
    }

    // Populate pending modal fields (create modal elements if absent)
    const pendingModal = document.getElementById('pending-modal');
    if (!pendingModal) {
      console.warn('Pending modal element not found in DOM');
      return;
    }

    let scheduleText = '—';
    if (stored.schedule) {
      try {
        const scheduleData = typeof stored.schedule === 'string' ? JSON.parse(stored.schedule) : stored.schedule;
        if (scheduleData && Array.isArray(scheduleData.days) && scheduleData.days.length > 0) {
          const startHour = Number.isFinite(scheduleData.startHour) ? `${scheduleData.startHour}:00` : '?';
          const endHour = Number.isFinite(scheduleData.endHour) ? `${scheduleData.endHour}:00` : '?';
          scheduleText = `${scheduleData.days.join(', ')} (${startHour} - ${endHour})`;
        }
      } catch (error) {
        scheduleText = String(stored.schedule);
      }
    }

    // set values
    document.getElementById('pending-username').textContent = stored.username || '—';
    document.getElementById('pending-employee-id').textContent = stored.employee_id || '—';
    document.getElementById('pending-email').textContent = stored.email || '—';
    document.getElementById('pending-role').textContent = stored.role ? (stored.role.charAt(0).toUpperCase() + stored.role.slice(1)) : '';
    document.getElementById('pending-specialization').textContent = stored.specialization || '—';
    document.getElementById('pending-schedule').textContent = scheduleText;
    document.getElementById('pending-submitted').textContent = formatDateTime(stored.created_at);

    // show modal
    pendingModal.style.display = 'flex';

    // accept/reject handlers use global pending-action-confirm-modal
    const showConfirm = (text, onConfirmAction) => {
      const global = document.getElementById('pending-action-confirm-modal');
      if (!global) {
        console.warn('Pending action confirm modal not found');
        return;
      }

      // close the pending modal immediately so the confirmation modal isn't displayed behind it
      pendingModal.style.display = 'none';

      document.getElementById('pending-action-text').textContent = text;
      global.style.display = 'flex';
      const yes = document.getElementById('pending-action-yes');
      const no = document.getElementById('pending-action-no');
      const cleanup = () => { global.style.display = 'none'; yes.onclick = null; no.onclick = null; };
      yes.onclick = () => { cleanup(); onConfirmAction(); };
      no.onclick = () => { cleanup(); };
    };

    document.getElementById('pending-accept').onclick = () => {
      showConfirm('Accept this registration and activate the account?', async () => {
        try {
          const res = await fetch(`${API_BASE}/api/staff/approve/${stored.id}`, { method: 'POST', credentials: 'include' });
          const data = await res.json();

          if (res.ok) {
            if (data.notificationEmailSent === true) {
              const recipient = data.notificationEmailRecipient || 'the registrant';
              showToast(`Account approved. Notification email sent to ${recipient}.`, 'success');
            } else if (data.notificationEmailSent === false) {
              const reason = data.notificationError ? ` Reason: ${data.notificationError}` : '';
              showToast(`Account approved, but notification email failed.${reason}`, 'warning');
            } else {
              showToast(data.message || 'Account approved successfully.', 'success');
            }
            loadStaffData();
            loadPendingStaffData();
          } else {
            showToast(data.message || 'Approval failed', 'error');
          }
        } catch (err) {
          console.error(err);
          showToast('Server error', 'error');
        }
      });
    };

    document.getElementById('pending-reject').onclick = () => {
      showConfirm('Reject this registration? This will permanently delete the submission.', async () => {
        try {
          const res = await fetch(`${API_BASE}/api/staff/reject/${stored.id}`, { method: 'POST', credentials: 'include' });
          const data = await res.json();
          if (res.ok) {
            showToast(data.message || 'Account rejected', 'success');
            loadPendingStaffData();
          } else {
            showToast(data.message || 'Rejection failed', 'error');
          }
        } catch (err) {
          console.error(err);
          showToast('Server error', 'error');
        }
      });
    };
  });
}

// Modal close button
const closeModalBtn = document.getElementById('modal-close-btn');
if (closeModalBtn) {
  closeModalBtn.addEventListener('click', () => {
    document.getElementById('account-modal').style.display = 'none';
    currentAccountData = null;
    currentAction = null;
  });
}

// Edit button
const editBtn = document.getElementById('modal-edit-btn');
if (editBtn) {
  editBtn.addEventListener('click', () => {
    currentAction = 'edit';
    document.getElementById('modal-confirm-text').textContent = 'Are you sure you want to edit this account?';
    document.getElementById('modal-actions').style.display = 'none';
    document.getElementById('modal-confirm-section').style.display = 'block';
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

// Confirm button
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

        const response = await fetch(`${API_BASE}/api/staff/${currentAccountData.id}`, {
          method: 'DELETE',
          credentials: 'include'
        });

        const data = await response.json().catch(() => ({}));
        if (!response.ok) {
          showToast(data.message || 'Failed to delete account.', 'error');
          return;
        }

        document.getElementById('account-modal').style.display = 'none';
        document.getElementById('modal-confirm-section').style.display = 'none';
        document.getElementById('modal-actions').style.display = 'flex';
        currentAccountData = null;
        currentAction = null;

        await Promise.all([loadStaffData(), loadPendingStaffData()]);
        showToast(data.message || 'Account deleted successfully.', 'success');
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

// --- Clickable stats to navigate to panes ---
const statAnnouncementsCard = document.getElementById('stat-announcements-card');
const statReportsCard = document.getElementById('stat-reports-card');
const statCitizensCard = document.getElementById('stat-citizens-card');

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

if (statCitizensCard) {
  statCitizensCard.addEventListener('click', async () => {
    hideAllSections();
    if (usersSection) usersSection.classList.remove('hidden');
    // ensure citizens data is loaded
    await loadCitizenData();
    const citizensTabButton = document.getElementById('tab-citizens');
    if (citizensTabButton) citizensTabButton.click();
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

const DUMMY_SCHEDULES = [
  { id: 1, doctor: 'Dr. Jane Smith (Cardiologist)', date: '2024-10-15', time: '09:00 - 12:00' },
  { id: 2, doctor: 'Dr. John Doe (General)', date: '2024-10-15', time: '14:00 - 17:00' },
  { id: 3, doctor: 'Dr. Maria Garcia (Pediatrician)', date: '2024-10-16', time: '10:00 - 13:00' },
  { id: 4, doctor: 'Dr. Ahmed Khan (Neurologist)', date: '2024-10-16', time: '15:00 - 18:00' },
  { id: 5, doctor: 'Dr. Li Wei (Dermatologist)', date: '2024-10-17', time: '09:00 - 12:00' },
  { id: 6, doctor: 'Dr. Sarah Johnson (Orthopedist)', date: '2024-10-17', time: '14:00 - 17:00' },
  { id: 7, doctor: 'Dr. Carlos Rodriguez (ENT)', date: '2024-10-18', time: '10:00 - 13:00' },
  { id: 8, doctor: 'Dr. Emily Chen (Ophthalmologist)', date: '2024-10-18', time: '15:00 - 18:00' },
  { id: 9, doctor: 'Dr. Michael Brown (Psychiatrist)', date: '2024-10-19', time: '09:00 - 12:00' },
  { id: 10, doctor: 'Dr. Anna Novak (Gynecologist)', date: '2024-10-19', time: '14:00 - 17:00' },
  { id: 11, doctor: 'Dr. Raj Patel (Endocrinologist)', date: '2024-10-20', time: '10:00 - 13:00' },
  { id: 12, doctor: 'Dr. Lisa Wong (Pulmonologist)', date: '2024-10-20', time: '15:00 - 18:00' }
];

const DUMMY_ANNOUNCEMENTS = [
  { id: 'A001', title: 'Flu Vaccination Campaign', preview: 'Annual flu shots available at all clinics starting Oct 15. Free for seniors...', date: '2024-10-14' },
  { id: 'A002', title: 'New Clinic Hours', preview: 'Saturday consultations now available from 9AM-1PM at Main Branch...', date: '2024-10-12' },
  { id: 'A003', title: 'Telemedicine Update', preview: 'Improved video quality and mobile app integration for remote consults...', date: '2024-10-10' },
  { id: 'A004', title: 'Staff Training Session', preview: 'Mandatory HIPAA compliance training on Oct 22, 2PM conference room...', date: '2024-10-09' },
  { id: 'A005', title: 'Patient Portal Upgrade', preview: 'New features: prescription refill requests, lab result viewing...', date: '2024-10-07' },
  { id: 'A006', title: 'Holiday Schedule Notice', preview: 'Clinic closed Oct 31 (Halloween) and Nov 1. Emergency line active...', date: '2024-10-05' },
  { id: 'A007', title: 'New Equipment Arrival', preview: 'Digital X-ray machine installed. Faster diagnostics starting Monday...', date: '2024-10-03' },
  { id: 'A008', title: 'Insurance Update', preview: 'MediCare+ now accepted. Update your insurance details in patient portal...', date: '2024-10-01' }
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
      <td class="table-cell">${new Date(c.created_at).toLocaleString()}</td>
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

function loadAnnouncements() {
  try {
    const raw = localStorage.getItem('ukonek_announcements');
    return raw ? JSON.parse(raw) : DUMMY_ANNOUNCEMENTS;
  } catch (err) {
    return DUMMY_ANNOUNCEMENTS;
  }
}

function renderAnnouncements() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;
  const announcements = loadAnnouncements();
  latestAnnouncementsList = Array.isArray(announcements) ? [...announcements] : [];
  tbody.innerHTML = '';
  announcements.forEach(a => {
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
    document.getElementById('stat-announcements').textContent = String(announcements.length);
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
      ]
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
    const rows = consultations.map(c => [c.id, c.patientId, c.diagnosis, new Date(c.created_at).toLocaleString()]);
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
  const rows = latestCitizensList.map(c => [c.username || c.name || '', c.email || '', c.created_at || '']);
  generateReport('Citizens Report', ['Username', 'Email', 'Registered'], rows);
}

// wire up simple global report triggers (if buttons exist elsewhere)
const usersReportBtn = document.getElementById('users-report-btn');
if (usersReportBtn) usersReportBtn.addEventListener('click', generateUsersReport);

const citizensReportBtn = document.getElementById('citizens-report-btn');
if (citizensReportBtn) citizensReportBtn.addEventListener('click', generateCitizensReport);
