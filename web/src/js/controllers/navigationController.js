/**
 * Navigation & Shell Layout Controller
 * Manages sidebar, section transitions, topbar profiles, role-based navigation guards,
 * notification popovers, and confirmation dialogs.
 */

import { sessionStore } from '../services/sessionStore.js';
import * as authService from '../services/authService.js';
import * as sessionAuth from '../services/sessionAuth.js';
import { supabase } from '../lib/supabaseClient.js';
import { showToast, dismissPagePreloader, toggleUserSkeleton } from '../utils/uiHelpers.js';

export const DEFAULT_SECTION_ID = 'dashboard-section';

export const SECTION_ROLE_RULES = {
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
  'profile-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'security-section': ['admin', 'doctor', 'nurse', 'pharmacist']
};

export const SECTION_BREADCRUMBS = {
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
  'profile-section': 'Personal Profile',
  'security-section': 'Change Password'
};

let activeSectionHooks = {};
let activeDialogResolver = null;

export function registerSectionHooks(hooks = {}) {
  activeSectionHooks = { ...activeSectionHooks, ...hooks };
}

export function isSectionAllowedForRole(sectionId, role) {
  let roleKey = String(role || '').trim().toLowerCase();
  if (roleKey === 'staff') roleKey = 'nurse';
  const allowed = SECTION_ROLE_RULES[sectionId];
  if (!allowed || allowed.length === 0) return true;
  return allowed.includes(roleKey);
}

export function syncRoleNavigationAccess(role) {
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

export function hideAllSections() {
  document.querySelectorAll('.section-top').forEach(section => section.classList.add('hidden'));
  document.querySelectorAll('[id*="-pane"].hidden, .tab-pane').forEach(pane => pane.classList.add('hidden'));
}

export function clearActiveNav() {
  document.querySelectorAll('[data-section], .nav-btn, .nav-item.is-active').forEach(el => el.classList.remove('is-active'));
  document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
}

export function getSectionFromHash() {
  const hash = String(window.location.hash || '').replace('#', '').trim();
  if (hash && document.getElementById(hash)) return hash;
  return null;
}

export function setSectionHash(sectionId) {
  if (sectionId && window.history && window.history.replaceState) {
    window.history.replaceState(null, '', `#${sectionId}`);
  }
}

export function closeSidebarDropdownMenus(exceptItem = null) {
  document.querySelectorAll('.nav-item.dropdown').forEach((item) => {
    if (exceptItem && item === exceptItem) return;
    item.classList.remove('open');
    const menu = item.querySelector('.dropdown-menu');
    if (menu) menu.classList.add('hidden');
  });
}

export function state() {
  const sidebar = document.getElementById('sidebar');
  const burger = document.getElementById('burger');
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

export function toTitleCase(value) {
  const lower = String(value || '').trim().toLowerCase();
  if (!lower) return 'Unknown';
  return lower.charAt(0).toUpperCase() + lower.slice(1);
}

export function getDisplayFirstName(user) {
  const preferred = user?.first_name || user?.firstName || user?.firstname;
  if (preferred && String(preferred).trim()) {
    return String(preferred).trim();
  }
  return String(user?.username || '').trim() || 'User';
}

export function getRoleLogoConfig(roleValue) {
  const key = String(roleValue || '').trim().toLowerCase();
  switch (key) {
    case 'admin':
      return { className: 'role-logo-admin', label: 'Admin Dashboard', icon: 'shield' };
    case 'doctor':
      return { className: 'role-logo-doctor', label: 'Doctor', icon: 'stethoscope' };
    case 'nurse':
    case 'staff':
      return { className: 'role-logo-nurse', label: 'Nurse', icon: 'heart' };
    case 'pharmacist':
      return { className: 'role-logo-pharmacist', label: 'Pharmacist', icon: 'capsule' };
    default:
      return { className: 'role-logo-default', label: 'User', icon: 'user' };
  }
}

export function getRoleLogoSvg(iconName) {
  switch (iconName) {
    case 'shield':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l7 3v6c0 5-3.5 9.5-7 11-3.5-1.5-7-6-7-11V5l7-3z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9 12l2 2 4-4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    case 'stethoscope':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3v5a4 4 0 0 0 8 0V3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M10 12v2a4 4 0 0 0 8 0v-2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="18" cy="10" r="2" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>';
    case 'heart':
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7-4.4-9-8.5C1.3 9.2 3 6 6.3 6c2.1 0 3.2 1.2 3.7 2 .5-.8 1.6-2 3.7-2C17 6 18.7 9.2 17 12.5 15 16.6 8 21 8 21" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    default:
      return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M5 20a7 7 0 0 1 14 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';
  }
}

export function applyRoleLogos(roleValue) {
  const config = getRoleLogoConfig(roleValue);
  const targets = [
    document.getElementById('topbar-role-logo'),
    document.getElementById('profile-role-logo')
  ];
  const roleClasses = [
    'role-logo-admin', 'role-logo-doctor', 'role-logo-nurse', 'role-logo-pharmacist',
    'role-logo-staff', 'role-logo-default', 'role-logo-skeleton', 'skeleton-shimmer'
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

export function applyRoleAccess(user) {
  const role = String(user?.role || '').trim().toLowerCase();
  const isAdmin = role === 'admin';
  const isClinical = role === 'doctor' || role === 'nurse' || role === 'staff';
  const hasFullAccess = isAdmin || isClinical;

  document.body.setAttribute('data-role', role);
  document.body.classList.toggle('role-admin', isAdmin);

  const burgerBtn = document.getElementById('burger');
  const sidebar = document.getElementById('sidebar');
  if (isAdmin) {
    if (burgerBtn) burgerBtn.style.display = 'none';
    if (sidebar) sidebar.classList.remove('collapsed');
  } else {
    if (burgerBtn) burgerBtn.style.display = '';
  }

  document.querySelectorAll('.admin-only').forEach((element) => {
    if (isAdmin) {
      if (!element.classList.contains('section-top')) element.classList.remove('hidden');
    } else {
      element.classList.add('hidden');
    }
  });

  document.querySelectorAll('.clinical-only').forEach((element) => {
    if (isClinical) {
      if (!element.classList.contains('section-top')) element.classList.remove('hidden');
    } else {
      element.classList.add('hidden');
    }
  });

  document.querySelectorAll('.full-access').forEach((element) => {
    if (hasFullAccess) {
      if (!element.classList.contains('section-top')) element.classList.remove('hidden');
    } else {
      element.classList.add('hidden');
    }
  });

  syncRoleNavigationAccess(role);
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

  const mainDashTitle = document.getElementById('main-dashboard-title');
  const mainTopbarTitle = document.getElementById('main-topbar-title');
  if (mainDashTitle || mainTopbarTitle) {
    let roleText = toTitleCase(role);
    if (role === 'admin') roleText = 'Administrator';
    if (mainDashTitle) mainDashTitle.textContent = `${roleText} Dashboard`;
    if (mainTopbarTitle) mainTopbarTitle.textContent = `${roleText} Systems Overview`;
  }

  populateProfile(user);
}

export function populateProfile(user) {
  if (!user) return;
  const name = document.getElementById('profile-name');
  const email = document.getElementById('profile-email');
  const role = document.getElementById('profile-role');
  const empIdInput = document.getElementById('profile-employee-id');

  const displayName = [user.first_name, user.last_name].filter(Boolean).join(' ') || user.username || 'Clinician';
  const displayEmail = user.email || 'clinician@ukonek.local';
  const displayRole = user.role || 'nurse';
  const displayEmpId = user.employee_id || (user.id ? `STF-${String(user.id).slice(0, 6).toUpperCase()}` : 'STF-01');

  if (name) name.value = displayName;
  if (email) email.value = displayEmail;
  if (role) role.value = toTitleCase(displayRole);
  if (empIdInput) empIdInput.value = displayEmpId;

  const heroName = document.getElementById('profile-hero-name');
  const heroAvatar = document.getElementById('profile-hero-avatar');
  const heroRole = document.getElementById('profile-hero-role-badge');
  const heroEmail = document.getElementById('profile-hero-email');
  const heroEmpId = document.getElementById('profile-hero-emp-id');
  const scopeDisplay = document.getElementById('profile-scope-display');

  if (heroName) heroName.textContent = displayName;
  if (heroAvatar) {
    const initials = displayName
      .split(' ')
      .filter(Boolean)
      .map((w) => w[0])
      .slice(0, 2)
      .join('')
      .toUpperCase() || 'MD';
    heroAvatar.textContent = initials;
  }
  if (heroRole) {
    heroRole.textContent = displayRole === 'doctor' ? 'Attending Physician' : toTitleCase(displayRole);
    heroRole.className = `staff-role-badge role-${displayRole}`;
  }
  if (heroEmail) heroEmail.textContent = displayEmail;
  if (heroEmpId) heroEmpId.textContent = `ID: #${displayEmpId}`;
  if (scopeDisplay) scopeDisplay.textContent = `${toTitleCase(displayRole)} Access Level`;

  // Telemetry station info
  const osElem = document.getElementById('session-os-info');
  const browserElem = document.getElementById('session-browser-info');
  if (osElem) {
    const platform = navigator.userAgentData?.platform || navigator.platform || 'Desktop';
    osElem.textContent = `${platform} Station`;
  }
  if (browserElem) {
    let bName = 'Secure Browser';
    const ua = navigator.userAgent;
    if (ua.includes('Edg/')) bName = 'Microsoft Edge';
    else if (ua.includes('Chrome/')) bName = 'Google Chrome';
    else if (ua.includes('Firefox/')) bName = 'Mozilla Firefox';
    else if (ua.includes('Safari/')) bName = 'Apple Safari';
    browserElem.textContent = bName;
  }

  setupPasswordVisibilityToggles(document.getElementById('profile-section') || document);
}

export function showLogoutConfirmModal() {
  const profilePopover = document.getElementById('user-profile-popover');
  const profileTrigger = document.getElementById('user-profile-trigger');
  if (profilePopover) {
    profilePopover.classList.add('hidden');
    if (profileTrigger) profileTrigger.setAttribute('aria-expanded', 'false');
  }
  const notifPanel = document.getElementById('notif-panel');
  if (notifPanel) notifPanel.classList.add('hidden');
  const modal = document.getElementById('logout-confirm-modal');
  if (modal) modal.classList.remove('hidden');
}

export function hideLogoutConfirmModal() {
  const modal = document.getElementById('logout-confirm-modal');
  if (modal) modal.classList.add('hidden');
}

export async function performLogout() {
  try {
    sessionStore.clear();
    await authService.signOutStaff();
    sessionAuth.clearAuthSessionMeta();
    sessionStorage.removeItem('ukonek_role');
  } catch (error) {
    console.warn('Sign out warning:', error);
  } finally {
    window.location.replace('./index.html');
  }
}

export function closeDialogModal(result = { confirmed: false, values: [] }) {
  const dialogModal = document.getElementById('dialog-modal');
  if (dialogModal) dialogModal.classList.add('hidden');
  if (activeDialogResolver) {
    activeDialogResolver(result);
    activeDialogResolver = null;
  }
}

export function openDialogModal({
  title = 'Confirm',
  message = '',
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  inputs = []
} = {}) {
  const dialogModal = document.getElementById('dialog-modal');
  const dialogTitle = document.getElementById('dialog-title');
  const dialogMessage = document.getElementById('dialog-message');
  const dialogConfirmBtn = document.getElementById('dialog-confirm-btn');
  const dialogCancelBtn = document.getElementById('dialog-cancel-btn');
  const dialogInput1Wrap = document.getElementById('dialog-input-1-wrap');
  const dialogInput1Label = document.getElementById('dialog-input-1-label');
  const dialogInput1 = document.getElementById('dialog-input-1');
  const dialogInput2Wrap = document.getElementById('dialog-input-2-wrap');
  const dialogInput2Label = document.getElementById('dialog-input-2-label');
  const dialogInput2 = document.getElementById('dialog-input-2');
  const dialogError = document.getElementById('dialog-error');

  if (!dialogModal) return Promise.resolve({ confirmed: false, values: [] });

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

export function showSection(sectionId, options = {}) {
  if (!sectionId) return;

  const user = sessionStore.getUser();
  const role = user?.role || 'nurse';
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
  }

  // Invoke registered feature controller hook for this section
  if (typeof activeSectionHooks[sectionId] === 'function') {
    activeSectionHooks[sectionId](options);
  }
}

export function navigateToSection(sectionId, options = {}) {
  const targetId = document.getElementById(sectionId) ? sectionId : DEFAULT_SECTION_ID;
  const user = sessionStore.getUser();
  const currentRole = user?.role || 'nurse';
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

export function setupPasswordVisibilityToggles(root = document) {
  const EYE_OPEN = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 5c-5.5 0-9.3 4.1-10.7 6.1a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19s9.3-4.1 10.7-6.1a1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5zm0 11a5 5 0 1 1 0-10 5 5 0 0 1 0 10zm0-2.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/></svg>';
  const EYE_CLOSED = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M2.3 1.3a1 1 0 0 0-1.4 1.4l3 3A13.8 13.8 0 0 0 1.3 11a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19a12 12 0 0 0 4.6-.9l3.1 3.1a1 1 0 1 0 1.4-1.4zm7.5 10.3a2.5 2.5 0 0 0 3.6 2.4l-3.5-3.5c0 .4-.1.7-.1 1.1zM12 7a5 5 0 0 1 5 5c0 .7-.1 1.3-.4 1.9l1.5 1.5a13.8 13.8 0 0 0 4.6-4.4 1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5c-1.4 0-2.7.3-3.8.8l1.5 1.5c.6-.2 1.5-.3 2.3-.3z"/></svg>';

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
    toggleBtn.innerHTML = EYE_OPEN;
    toggleBtn.addEventListener('click', () => {
      const isPassword = input.type === 'password';
      input.type = isPassword ? 'text' : 'password';
      toggleBtn.innerHTML = isPassword ? EYE_CLOSED : EYE_OPEN;
      toggleBtn.setAttribute('aria-label', isPassword ? 'Hide password' : 'Show password');
      toggleBtn.setAttribute('aria-pressed', isPassword ? 'true' : 'false');
    });

    wrapper.appendChild(toggleBtn);
    input.dataset.toggleAttached = 'true';
  });
}

export function initNavigation() {
  const sidebar = document.getElementById('sidebar');
  const burger = document.getElementById('burger');
  const sidebarBackdrop = document.getElementById('sidebar-backdrop');
  const navContainer = document.querySelector('.nav');
  const profileTrigger = document.getElementById('user-profile-trigger');
  const profilePopover = document.getElementById('user-profile-popover');
  const logoutBtn = document.getElementById('logout-btn');
  const logoutConfirmModal = document.getElementById('logout-confirm-modal');
  const logoutConfirmYesBtn = document.getElementById('logout-confirm-yes');
  const logoutConfirmNoBtn = document.getElementById('logout-confirm-no');
  const dialogModal = document.getElementById('dialog-modal');
  const dialogCancelBtn = document.getElementById('dialog-cancel-btn');
  const dialogConfirmBtn = document.getElementById('dialog-confirm-btn');

  // Burger sidebar toggle
  if (burger) {
    burger.addEventListener('click', () => {
      if (document.body.getAttribute('data-role') === 'admin') return;
      if (window.innerWidth <= 900) {
        sidebar?.classList.toggle('slid');
        sidebar?.classList.remove('collapsed');
      } else {
        closeSidebarDropdownMenus();
        sidebar?.classList.toggle('collapsed');
      }
      state();
    });
    window.addEventListener('resize', state);
  }

  if (sidebarBackdrop) {
    sidebarBackdrop.addEventListener('click', () => {
      if (sidebar) sidebar.classList.remove('slid');
      state();
    });
  }

  // Profile Popover
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

  // Logout modal
  if (logoutBtn) {
    logoutBtn.addEventListener('click', () => {
      if (logoutConfirmModal) {
        showLogoutConfirmModal();
      } else {
        performLogout();
      }
    });
  }

  if (logoutConfirmYesBtn) logoutConfirmYesBtn.addEventListener('click', performLogout);
  if (logoutConfirmNoBtn) logoutConfirmNoBtn.addEventListener('click', hideLogoutConfirmModal);
  if (logoutConfirmModal) {
    logoutConfirmModal.addEventListener('click', (e) => {
      if (e.target === logoutConfirmModal) hideLogoutConfirmModal();
    });
  }

  // Confirmation dialog modal
  if (dialogCancelBtn) {
    dialogCancelBtn.addEventListener('click', () => closeDialogModal({ confirmed: false, values: [] }));
  }
  if (dialogConfirmBtn) {
    dialogConfirmBtn.addEventListener('click', () => {
      const values = [];
      const d1 = document.getElementById('dialog-input-1');
      const d2 = document.getElementById('dialog-input-2');
      if (d1 && !d1.closest('#dialog-input-1-wrap')?.classList.contains('hidden')) {
        values.push(String(d1.value || '').trim());
      }
      if (d2 && !d2.closest('#dialog-input-2-wrap')?.classList.contains('hidden')) {
        values.push(String(d2.value || '').trim());
      }
      closeDialogModal({ confirmed: true, values });
    });
  }
  if (dialogModal) {
    dialogModal.addEventListener('click', (e) => {
      if (e.target === dialogModal) closeDialogModal({ confirmed: false, values: [] });
    });
  }

  // Navigation clicks
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

      if (isDropdownItem && activeMenu) {
        closeSidebarDropdownMenus(parentItem);
        activeMenu.classList.remove('hidden');
        if (parentItem) parentItem.classList.add('open');
      }

      if (isDropdownBtn && activeMenu) {
        const willOpen = activeMenu.classList.contains('hidden');
        closeSidebarDropdownMenus(parentItem);
        activeMenu.classList.toggle('hidden', !willOpen);
        if (parentItem) parentItem.classList.toggle('open', willOpen);
      }

      if (sectionId || isDropdownBtn) {
        const targetId = sectionId || el.getAttribute('data-section');
        if (targetId) navigateToSection(targetId, sectionOptions);
      }
    });
  }

  setupPasswordVisibilityToggles();
  state();
}
