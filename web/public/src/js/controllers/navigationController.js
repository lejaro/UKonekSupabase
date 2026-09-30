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
import { openDialogModal, closeDialogModal } from '../utils/dialogModal.js';

export { openDialogModal, closeDialogModal } from '../utils/dialogModal.js';

export const DEFAULT_SECTION_ID = 'dashboard-section';

export const SECTION_ROLE_RULES = {
  'dashboard-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'users-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'announcements-section': ['admin', 'doctor', 'nurse'],
  'feedback-section': ['admin', 'doctor', 'nurse'],
  'stats-section': ['admin', 'doctor', 'nurse'],
  'reports-section': ['admin', 'doctor', 'nurse'],
  'medicine-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'consultation-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'schedule-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'vitals-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'queue-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'profile-section': ['admin', 'doctor', 'nurse', 'pharmacist'],
  'security-section': ['admin', 'doctor', 'nurse', 'pharmacist']
};

export const SECTION_BREADCRUMBS = {
  'dashboard-section': 'Dashboard Overview',
  'schedule-section': 'Availability Schedule',
  'queue-section': 'Live Patient Queue',
  'vitals-section': 'Vitals Triage',
  'consultation-section': 'Consultations',
  'medicine-section': 'Pharmacy & Stock',
  'users-section': 'Personnel & Citizens',
  'announcements-section': 'Clinic Announcements',
  'feedback-section': 'Citizen Feedback',
  'stats-section': 'Clinical Analytics',
  'reports-section': 'Reports & Analytics',
  'profile-section': 'Profile',
  'security-section': 'Change Password'
};

let activeSectionHooks = {};

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

export function toPossessiveRole(roleName) {
  const raw = String(roleName || '').trim();
  if (!raw) return "User's";
  return raw.endsWith('s') || raw.endsWith('S') ? `${raw}'` : `${raw}'s`;
}

let currentActiveRole = 'nurse';

export function parseNameParts(fullName) {
  const trimmed = String(fullName || '').trim();
  if (!trimmed) return { firstName: '', lastName: '' };

  const parts = trimmed.split(/\s+/);
  if (parts.length === 1) {
    return { firstName: parts[0], lastName: '' };
  }

  if (parts.length > 2 && /^dr\.?$/i.test(parts[0])) {
    const lastName = parts.pop();
    const firstName = parts.join(' ');
    return { firstName, lastName };
  }

  const lastName = parts.pop();
  const firstName = parts.join(' ');
  return { firstName, lastName };
}

export function getDisplayFullName(user) {
  if (!user) return 'Clinical Personnel';
  const first = String(user.first_name || user.firstName || user.firstname || '').trim();
  const last = String(user.last_name || user.lastName || user.surname || '').trim();

  if (first && last) {
    if (first.toLowerCase() === last.toLowerCase()) {
      return first;
    }
    if (first.toLowerCase().endsWith(last.toLowerCase())) {
      return first;
    }
    return `${first} ${last}`;
  }
  const uname = String(user?.username || '').trim();
  const validUsername = uname && !uname.includes('@') ? uname : '';
  return validUsername || first || last || 'Clinical Personnel';
}

export function getDisplayFirstName(user) {
  // If user has a valid username (not an email), use that directly
  const uname = String(user?.username || '').trim();
  if (uname && !uname.includes('@')) {
    return uname;
  }
  const preferred = String(user?.first_name || user?.firstName || user?.firstname || '').trim();
  if (preferred) {
    const parts = preferred.split(/\s+/);
    if (parts.length > 1 && /^dr\.?$/i.test(parts[0])) {
      return `${parts[0]} ${parts[1]}`;
    }
    return parts[0];
  }
  const role = String(user?.role || '').trim();
  if (role) {
    return role.charAt(0).toUpperCase() + role.slice(1);
  }
  return 'User';
}

export function getInitials(fullName) {
  const raw = String(fullName || '').trim();
  if (!raw) return 'MD';

  const cleaned = raw
    .replace(/^(dr\.?|doctor|atty\.?|rn|md)\s+/i, '')
    .replace(/,\s*(md|rn|fpa|fpcp|fpcr)$/i, '')
    .trim();

  const parts = cleaned.split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'MD';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function getRoleLogoConfig(roleValue) {
  const key = String(roleValue || '').trim().toLowerCase();
  switch (key) {
    case 'admin':
      return { className: 'role-logo-admin', label: "Administrator's Dashboard", icon: 'shield' };
    case 'doctor':
      return { className: 'role-logo-doctor', label: "Doctor's Dashboard", icon: 'stethoscope' };
    case 'nurse':
    case 'staff':
      return { className: 'role-logo-nurse', label: "Nurse's Dashboard", icon: 'heart' };
    case 'pharmacist':
      return { className: 'role-logo-pharmacist', label: "Pharmacist's Dashboard", icon: 'capsule' };
    default:
      return { className: 'role-logo-default', label: "User's Dashboard", icon: 'user' };
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
  currentActiveRole = role;
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
    node.textContent = getDisplayFullName(user);
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
    const possessiveRole = toPossessiveRole(roleText);
    if (mainDashTitle) mainDashTitle.textContent = `${possessiveRole} Dashboard`;
    if (mainTopbarTitle) mainTopbarTitle.textContent = `${possessiveRole} Systems Overview`;
    document.title = `U-Konek — ${possessiveRole} Dashboard`;
  }

  populateProfile(user);
}

export function populateProfile(user) {
  if (!user) return;
  const name = document.getElementById('profile-name');
  const email = document.getElementById('profile-email');
  const role = document.getElementById('profile-role');
  const empIdInput = document.getElementById('profile-employee-id');
  const usernameInput = document.getElementById('profile-username');
  const specInput = document.getElementById('profile-specialization');
  const specWrap = document.getElementById('profile-specialization-wrap');

  const fullDisplayName = getDisplayFullName(user);
  const displayEmail = user.email || 'clinician@ukonek.local';
  const displayRole = user.role || 'nurse';
  const displayEmpId = user.employee_id || (user.id ? `STF-${String(user.id).slice(0, 6).toUpperCase()}` : 'STF-01');
  const rawUsername = String(user.username || '').trim();
  const displayUsername = rawUsername && !rawUsername.includes('@') ? rawUsername : '';
  const displaySpec = user.doctor_specialization || '';

  if (name) name.value = fullDisplayName;
  if (email) email.value = displayEmail;
  if (role) role.value = toTitleCase(displayRole);
  if (empIdInput) empIdInput.value = displayEmpId;
  if (usernameInput) usernameInput.value = displayUsername;

  const isDoc = isDoctorRole(displayRole);
  if (specWrap) {
    specWrap.style.display = isDoc ? 'block' : 'none';
  }
  if (specInput) {
    specInput.value = displaySpec;
  }

  const heroName = document.getElementById('profile-hero-name');
  const heroAvatar = document.getElementById('profile-hero-avatar');
  const heroRole = document.getElementById('profile-hero-role-badge');
  const heroEmail = document.getElementById('profile-hero-email');
  const heroEmpId = document.getElementById('profile-hero-emp-id');
  const scopeDisplay = document.getElementById('profile-scope-display');

  if (heroName) heroName.textContent = fullDisplayName;
  if (heroAvatar) {
    heroAvatar.textContent = getInitials(fullDisplayName);
  }
  if (heroRole) {
    heroRole.textContent = displayRole === 'doctor'
      ? (displaySpec ? `Attending Physician • ${displaySpec}` : 'Attending Physician')
      : toTitleCase(displayRole);
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
  const notifPanel = document.getElementById('notification-panel') || document.getElementById('notif-panel');
  if (notifPanel) notifPanel.classList.add('hidden');
  const modal = document.getElementById('logout-confirm-modal');
  if (modal) {
    modal.classList.remove('hidden');
    const cancelBtn = document.getElementById('logout-confirm-no');
    if (cancelBtn) setTimeout(() => cancelBtn.focus(), 50);
  }
}

export function hideLogoutConfirmModal() {
  const modal = document.getElementById('logout-confirm-modal');
  if (modal) modal.classList.add('hidden');
}

export function switchProfileSubpane(targetPaneId) {
  const profileTabsWrap = document.getElementById('profile-tabs');
  if (profileTabsWrap) {
    profileTabsWrap.querySelectorAll('.personnel-tab-btn').forEach((b) => {
      b.classList.toggle('is-active', b.getAttribute('data-pane') === targetPaneId);
    });
  }
  document.querySelectorAll('#profile-section .profile-subpane').forEach((pane) => {
    if (pane.id === targetPaneId) {
      pane.classList.remove('hidden');
    } else {
      pane.classList.add('hidden');
    }
  });

  const topbarTitleNode = document.getElementById('main-topbar-title');
  if (topbarTitleNode) {
    if (targetPaneId === 'profile-pane-security') {
      topbarTitleNode.textContent = SECTION_BREADCRUMBS['security-section'] || 'Change Password';
      setSectionHash('security-section');
    } else {
      topbarTitleNode.textContent = SECTION_BREADCRUMBS['profile-section'] || 'Personal Profile';
      setSectionHash('profile-section');
    }
  }

  if (targetPaneId === 'profile-pane-security') {
    setupPasswordVisibilityToggles(document.getElementById('profile-pane-security') || document);
    const newPwd = document.getElementById('profile-new-password');
    if (newPwd) {
      setTimeout(() => newPwd.focus(), 60);
    }
  }
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

export function isDoctorRole(value) {
  const key = String(value || '').trim().toLowerCase();
  return key === 'doctor' || key === 'specialist';
}

export function isScheduleRole(value) {
  const key = String(value || '').trim().toLowerCase();
  return key === 'doctor' || key === 'specialist' || key === 'nurse' || key === 'staff';
}

export function getDoctorDisplayName(doctor) {
  if (!doctor) return 'Doctor';
  const first = String(doctor.first_name || doctor.firstname || '').trim();
  const last = String(doctor.last_name || doctor.surname || '').trim();
  if (first && last) {
    if (first.toLowerCase() === last.toLowerCase()) {
      return first;
    }
    if (first.toLowerCase().endsWith(last.toLowerCase())) {
      return first;
    }
    return `${first} ${last}`;
  }
  return first || last || doctor.username || 'Doctor';
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
  // Alias security-section to profile-section with the security subpane
  if (sectionId === 'security-section') {
    return navigateToSection('profile-section', { ...options, pane: 'profile-pane-security' });
  }

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

  if (allowedTarget === 'profile-section' && options?.pane === 'profile-pane-security') {
    setSectionHash('security-section');
  } else {
    setSectionHash(allowedTarget);
  }

  const topbarTitleNode = document.getElementById('main-topbar-title');
  if (topbarTitleNode) {
    if (allowedTarget === 'profile-section' && options?.pane === 'profile-pane-security') {
      topbarTitleNode.textContent = SECTION_BREADCRUMBS['security-section'] || 'Change Password';
    } else if (allowedTarget === 'dashboard-section') {
      let roleText = toTitleCase(currentActiveRole || 'staff');
      if (currentActiveRole === 'admin') roleText = 'Administrator';
      const possessiveRole = toPossessiveRole(roleText);
      topbarTitleNode.textContent = `${possessiveRole} Systems Overview`;
      document.title = `U-Konek — ${possessiveRole} Dashboard`;
    } else if (SECTION_BREADCRUMBS[allowedTarget]) {
      topbarTitleNode.textContent = SECTION_BREADCRUMBS[allowedTarget];
    }
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

  // Notification Panel
  const notifBtn = document.getElementById('notif-btn');
  const notifPanel = document.getElementById('notification-panel') || document.getElementById('notif-panel');
  const notifCloseBtn = document.getElementById('notif-close-btn');

  if (notifBtn && notifPanel) {
    notifBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (profilePopover) {
        profilePopover.classList.add('hidden');
        if (profileTrigger) profileTrigger.setAttribute('aria-expanded', 'false');
      }
      notifPanel.classList.toggle('hidden');
    });

    if (notifCloseBtn) {
      notifCloseBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        notifPanel.classList.add('hidden');
      });
    }

    document.addEventListener('click', (e) => {
      if (!notifPanel.classList.contains('hidden')) {
        if (!notifPanel.contains(e.target) && !notifBtn.contains(e.target)) {
          notifPanel.classList.add('hidden');
        }
      }
    });
  }

  // Profile Popover
  if (profileTrigger && profilePopover) {
    profileTrigger.addEventListener('click', (e) => {
      e.stopPropagation();
      if (notifPanel) notifPanel.classList.add('hidden');

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

    // Popover navigation menu links (My Profile, Change Password, Availability Schedule)
    profilePopover.querySelectorAll('[data-section]').forEach((item) => {
      item.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        profilePopover.classList.add('hidden');
        if (profileTrigger) profileTrigger.setAttribute('aria-expanded', 'false');

        const sectionId = item.getAttribute('data-section');
        if (sectionId === 'security-section') {
          navigateToSection('profile-section', { pane: 'profile-pane-security' });
        } else if (sectionId) {
          const pane = item.dataset.pane || (sectionId === 'profile-section' ? 'profile-pane-details' : undefined);
          navigateToSection(sectionId, { pane });
        }
      });
    });
  }

  // Logout modal
  if (logoutBtn) {
    logoutBtn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (profilePopover) profilePopover.classList.add('hidden');
      if (profileTrigger) profileTrigger.setAttribute('aria-expanded', 'false');

      if (logoutConfirmModal) {
        showLogoutConfirmModal();
      } else {
        performLogout();
      }
    });
  }

  if (logoutConfirmYesBtn) {
    logoutConfirmYesBtn.addEventListener('click', (e) => {
      e.preventDefault();
      performLogout();
    });
  }
  if (logoutConfirmNoBtn) {
    logoutConfirmNoBtn.addEventListener('click', (e) => {
      e.preventDefault();
      hideLogoutConfirmModal();
    });
  }
  if (logoutConfirmModal) {
    logoutConfirmModal.addEventListener('click', (e) => {
      if (e.target === logoutConfirmModal) hideLogoutConfirmModal();
    });
  }
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && logoutConfirmModal && !logoutConfirmModal.classList.contains('hidden')) {
      hideLogoutConfirmModal();
    }
  });

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
  initProfileHandlers();
  state();
}

export function initProfileHandlers() {
  const profileTabsWrap = document.getElementById('profile-tabs');
  if (profileTabsWrap) {
    profileTabsWrap.querySelectorAll('.personnel-tab-btn').forEach((tabBtn) => {
      tabBtn.addEventListener('click', (e) => {
        e.preventDefault();
        const paneId = tabBtn.getAttribute('data-pane');
        if (paneId) switchProfileSubpane(paneId);
      });
    });
  }

  // Password strength & validation
  const newPasswordInput = document.getElementById('profile-new-password');
  const confirmPasswordInput = document.getElementById('profile-confirm-password');

  function evaluatePasswordStrength(pwd) {
    let score = 0;
    if (!pwd) return { score: 0, label: 'None', color: '#cbd5e1', pct: 0 };
    if (pwd.length >= 8) score += 1;
    if (pwd.length >= 12) score += 1;
    if (/[0-9]/.test(pwd)) score += 1;
    if (/[A-Z]/.test(pwd) && /[a-z]/.test(pwd)) score += 1;
    if (/[^A-Za-z0-9]/.test(pwd)) score += 1;

    if (score <= 1) return { score, label: 'Weak', color: '#ef4444', pct: 20 };
    if (score <= 3) return { score, label: 'Medium', color: '#f59e0b', pct: 60 };
    return { score, label: 'Strong', color: '#10b981', pct: 100 };
  }

  function updatePasswordValidationUI() {
    const pwd = newPasswordInput ? newPasswordInput.value : '';
    const confirmPwd = confirmPasswordInput ? confirmPasswordInput.value : '';

    const { label, color, pct } = evaluatePasswordStrength(pwd);
    const strengthLabel = document.getElementById('password-strength-label');
    const strengthMeter = document.getElementById('password-strength-meter');

    if (strengthLabel) {
      strengthLabel.textContent = label;
      strengthLabel.style.color = color;
    }
    if (strengthMeter) {
      strengthMeter.style.width = `${pct}%`;
      strengthMeter.style.background = color;
    }

    const ruleLength = document.getElementById('rule-length');
    const ruleComplexity = document.getElementById('rule-complexity');
    const ruleMatch = document.getElementById('rule-match');

    if (ruleLength) {
      ruleLength.style.color = pwd.length >= 8 ? '#16a34a' : '#64748b';
      ruleLength.style.fontWeight = pwd.length >= 8 ? '700' : '400';
    }
    if (ruleComplexity) {
      const hasComplexity = /[A-Za-z]/.test(pwd) && /[0-9]/.test(pwd);
      ruleComplexity.style.color = hasComplexity ? '#16a34a' : '#64748b';
      ruleComplexity.style.fontWeight = hasComplexity ? '700' : '400';
    }
    if (ruleMatch) {
      const isMatch = pwd.length > 0 && pwd === confirmPwd;
      ruleMatch.style.color = isMatch ? '#16a34a' : '#64748b';
      ruleMatch.style.fontWeight = isMatch ? '700' : '400';
    }
  }

  if (newPasswordInput) newPasswordInput.addEventListener('input', updatePasswordValidationUI);
  if (confirmPasswordInput) confirmPasswordInput.addEventListener('input', updatePasswordValidationUI);

  // Update password button handler
  const updatePasswordBtn = document.getElementById('profile-update-password-btn');
  const updatePasswordBtnText = document.getElementById('profile-update-password-btn-text');
  if (updatePasswordBtn) {
    updatePasswordBtn.addEventListener('click', async (e) => {
      e.preventDefault();
      const newPwd = (newPasswordInput?.value || '').trim();
      const confirmPwd = (confirmPasswordInput?.value || '').trim();

      if (!newPwd || newPwd.length < 8) {
        showToast('Password must be at least 8 characters in length.', 'error');
        newPasswordInput?.focus();
        return;
      }
      if (!/[A-Za-z]/.test(newPwd) || !/[0-9]/.test(newPwd)) {
        showToast('Password must contain both letters and numbers.', 'error');
        newPasswordInput?.focus();
        return;
      }
      if (newPwd !== confirmPwd) {
        showToast('Passwords do not match. Please verify.', 'error');
        confirmPasswordInput?.focus();
        return;
      }

      try {
        updatePasswordBtn.disabled = true;
        if (updatePasswordBtnText) updatePasswordBtnText.textContent = 'Updating...';

        const { error } = await supabase.auth.updateUser({ password: newPwd });

        if (error) {
          throw new Error(error.message || 'Failed to update authentication password.');
        }

        showToast('Password updated securely. New credentials are now active.', 'success');
        if (newPasswordInput) newPasswordInput.value = '';
        if (confirmPasswordInput) confirmPasswordInput.value = '';
        updatePasswordValidationUI();
      } catch (err) {
        console.error('[Profile] Password update error:', err);
        showToast(err?.message || 'Unable to update password.', 'error');
      } finally {
        updatePasswordBtn.disabled = false;
        if (updatePasswordBtnText) updatePasswordBtnText.textContent = 'Update Password';
      }
    });
  }

  // Profile save button handler
  const profileForm = document.getElementById('profile-form');
  const profileSaveBtn = document.getElementById('profile-save-btn');
  const profileSaveBtnText = document.getElementById('profile-save-btn-text');
  const profileCancelBtn = document.getElementById('profile-cancel-btn');

  async function handleProfileSave(e) {
    if (e) e.preventDefault();
    const nameInput = document.getElementById('profile-name');
    const specInput = document.getElementById('profile-specialization');
    const displayName = String(nameInput?.value || '').trim();
    const specialization = String(specInput?.value || '').trim();

    if (!displayName) {
      showToast('Display name cannot be empty.', 'error');
      nameInput?.focus();
      return;
    }

    const { firstName, lastName } = parseNameParts(displayName);
    const currentUser = sessionStore.getUser() || {};
    const isDoctor = isDoctorRole(currentUser.role);

    try {
      if (profileSaveBtn) {
        profileSaveBtn.disabled = true;
        if (profileSaveBtnText) profileSaveBtnText.textContent = 'Saving...';
      }

      let saveSucceeded = false;
      let returnedProfile = null;

      // 1. Primary method: invoke update_my_staff_profile RPC
      try {
        const rpcPayload = {
          p_display_name: firstName,
          p_last_name: lastName || null,
          p_username: displayName,
          p_doctor_specialization: isDoctor && specialization ? specialization : null
        };
        const { data, error } = await supabase.rpc('update_my_staff_profile', rpcPayload);

        if (!error && !data?.error) {
          saveSucceeded = true;
          returnedProfile = data?.profile || null;
        } else if (data?.error) {
          console.warn('[Profile] update_my_staff_profile returned note:', data.error);
        }
      } catch (rpcErr) {
        console.warn('[Profile] RPC error, will attempt direct staff table update:', rpcErr);
      }

      // 2. Direct database update fallback if RPC didn't succeed (e.g. local dev, custom role)
      if (!saveSucceeded) {
        const updatePayload = {
          first_name: firstName,
          last_name: lastName || null,
          username: displayName,
          ...(isDoctor ? { doctor_specialization: specialization || null } : {})
        };

        let query = supabase.from('staff').update(updatePayload);
        if (currentUser.id) {
          query = query.eq('id', currentUser.id);
        } else if (currentUser.email) {
          query = query.ilike('email', currentUser.email);
        }

        const { data: directData, error: directErr } = await query.select().maybeSingle();
        if (directErr) {
          console.warn('[Profile] Direct staff update warning:', directErr);
        } else {
          saveSucceeded = true;
          returnedProfile = directData || null;
        }
      }

      // 3. Keep Supabase Auth user metadata updated in sync
      try {
        await supabase.auth.updateUser({
          data: {
            first_name: firstName,
            last_name: lastName || '',
            full_name: displayName,
            username: displayName
          }
        });
      } catch (authMetaErr) {
        console.warn('[Profile] Supabase auth.updateUser metadata sync warning:', authMetaErr);
      }

      // 4. Update session store and persistence with clean name parts and username
      const updatedUser = {
        ...currentUser,
        first_name: firstName,
        last_name: lastName || '',
        username: displayName,
        doctor_specialization: isDoctor ? specialization : (currentUser.doctor_specialization || null),
        ...(returnedProfile || {})
      };

      // Guarantee clean updated fields on updatedUser
      updatedUser.first_name = firstName;
      updatedUser.last_name = lastName || '';
      updatedUser.username = displayName;
      if (isDoctor) {
        updatedUser.doctor_specialization = specialization;
      }

      sessionStore.setUser(updatedUser);
      sessionAuth.setAuthSessionMeta({
        username: displayName,
        firstName: firstName,
        first_name: firstName,
        lastName: lastName || '',
        last_name: lastName || '',
        doctor_specialization: updatedUser.doctor_specialization
      });
      sessionStorage.setItem('ukonek_staff_name', displayName);

      applyRoleAccess(updatedUser);
      populateProfile(updatedUser);

      showToast('Profile updated successfully.', 'success');
    } catch (err) {
      console.error('[Profile] Save error:', err);
      showToast(err?.message || 'Failed to save profile.', 'error');
    } finally {
      if (profileSaveBtn) {
        profileSaveBtn.disabled = false;
        if (profileSaveBtnText) profileSaveBtnText.textContent = 'Save Changes';
      }
    }
  }

  if (profileForm) {
    profileForm.addEventListener('submit', handleProfileSave);
  }
  if (profileSaveBtn && profileSaveBtn.type !== 'submit') {
    profileSaveBtn.addEventListener('click', handleProfileSave);
  }

  // Reset button
  if (profileCancelBtn) {
    profileCancelBtn.addEventListener('click', (e) => {
      e.preventDefault();
      const currentUser = sessionStore.getUser();
      if (currentUser) populateProfile(currentUser);
      showToast('Profile form reset.', 'info');
    });
  }
}
