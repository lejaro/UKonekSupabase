/**
 * Personnel & Citizen Directory Controller
 * Manages staff accounts, citizen profiles, role administration,
 * account creation, edit modals, and staff password resets.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as staffService from '../services/staffService.js';
import { showToast, renderTableSkeleton, swapContainer } from '../utils/uiHelpers.js';
import { attachDetailRow, sanitizeText, formatDetailValue } from '../utils/dataDetailModal.js';
import { openDialogModal, toTitleCase } from './navigationController.js';

export const storedAccounts = new Map();
export let latestStaffList = [];
export let latestPatientsList = [];
const citizenDetailCache = new Map();

export function getStaffPresenceStatus(user) {
  const isOnline = user?.is_online || false;
  const status = String(user?.availability_status || user?.status || '').toLowerCase();
  if (status === 'on_break' || status === 'break') return 'On Break';
  if (isOnline || status === 'available' || status === 'active' || status === 'on_duty') return 'On Duty';
  return 'Off Duty';
}

export function isSelfUser(user) {
  const current = sessionStore.getUser();
  if (!user || !current) return false;
  if (user.id && current.id && String(user.id) === String(current.id)) return true;
  if (user.email && current.email && String(user.email).toLowerCase() === String(current.email).toLowerCase()) return true;
  if (user.username && current.username && String(user.username).toLowerCase() === String(current.username).toLowerCase()) return true;
  return false;
}

export async function listStaffFromSupabase() {
  const rpcResult = await supabase.rpc('list_staff_accounts');
  if (!rpcResult.error) {
    return Array.isArray(rpcResult.data) ? rpcResult.data : [];
  }
  const staff = await staffService.listStaff();
  return Array.isArray(staff) ? staff : [];
}

export async function loadStaffData() {
  const accountsTbody = document.getElementById('accounts-tbody');
  if (accountsTbody) {
    renderTableSkeleton(accountsTbody, 4, 5);
  }

  let staffList = [];
  try {
    staffList = await listStaffFromSupabase();
  } catch (error) {
    console.error('Error loading staff:', error);
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

      latestStaffList.forEach((user) => {
        const identifier = String(user.id || user.username || user.employee_id || '');
        storedAccounts.set(identifier, user);
        if (user.username) storedAccounts.set(String(user.username), user);
        if (user.id) storedAccounts.set(String(user.id), user);
        if (user.employee_id) storedAccounts.set(String(user.employee_id), user);

        const roleValue = user.role ? String(user.role).toLowerCase() : 'staff';
        const roleLabel = roleValue.charAt(0).toUpperCase() + roleValue.slice(1);
        const statusValue = getStaffPresenceStatus(user);
        const isDuty = statusValue.toLowerCase().includes('duty');
        const isBreak = statusValue.toLowerCase().includes('break');
        const dutyClass = isDuty ? 'on-duty' : (isBreak ? 'break' : 'off-duty');

        const initials = (user.username || 'ST').substring(0, 2).toUpperCase();
        const fullName = [user.firstname || user.first_name, user.surname || user.last_name].filter(Boolean).join(' ') || user.username || 'Medical Staff';
        const isSelf = isSelfUser(user);
        const youBadge = isSelf
          ? ` <span class="self-account-badge" style="display:inline-flex; align-items:center; gap:3px; font-size:10.5px; font-weight:700; color:#059669; background:#ecfdf5; border:1px solid #a7f3d0; padding:1px 7px; border-radius:9999px; margin-left:4px; vertical-align:middle;">You</span>`
          : '';

        const row = document.createElement('tr');
        row.className = 'account-row';
        row.setAttribute('data-role', roleValue);
        row.setAttribute('data-id', identifier);
        row.innerHTML = `
          <td class="table-cell">
            <div class="user-avatar-cell">
              <div class="avatar-circle">${initials}</div>
              <div>
                <strong style="font-size:13.5px; color:#0f172a;">${sanitizeText(fullName)}</strong>${youBadge}
                <div style="font-size:11.5px; color:#64748b;">@${sanitizeText(user.username || '—')}</div>
              </div>
            </div>
          </td>
          <td class="table-cell"><span class="employee-badge">${sanitizeText(user.employee_id || 'EMP-—')}</span></td>
          <td class="table-cell"><span class="staff-role-badge role-${roleValue}">${sanitizeText(roleLabel)}</span></td>
          <td class="table-cell">
            <span class="duty-status-badge ${dutyClass}">
              <span class="duty-dot ${dutyClass}"></span>
              ${sanitizeText(statusValue)}
            </span>
          </td>
          <td class="table-cell" style="text-align:right;">
            <button type="button" class="btn small outline" data-action="view-staff" data-id="${sanitizeText(identifier)}" style="padding:3px 10px; font-size:11.5px; border-radius:9999px;">View Profile</button>
          </td>
        `;

        fragment.appendChild(row);

        attachDetailRow(row, () => ({
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
          actions: sessionStore.isAdmin() ? [
            {
              label: 'Edit Account',
              onClick: () => openAccountModal(user)
            }
          ] : []
        }));

        row.querySelector('[data-action="view-staff"]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          openAccountModal(user);
        });
      });
    });

    applyStaffFinder();
    updateUsersSectionTelemetry();
  }
}

export async function loadPatientData() {
  const citizensTbody = document.getElementById('citizens-tbody');
  if (citizensTbody) {
    renderTableSkeleton(citizensTbody, 5, 5);
  }

  let patients = [];
  try {
    const { data, error } = await supabase
      .from('citizens')
      .select('id, firstname, surname, username, email, contact_number, complete_address, age, date_of_birth, created_at')
      .order('created_at', { ascending: false })
      .limit(100);

    if (!error && Array.isArray(data)) {
      patients = data;
    }
  } catch (err) {
    console.warn('Error fetching citizens:', err);
  }

  latestPatientsList = Array.isArray(patients) ? [...patients] : [];

  if (citizensTbody) {
    swapContainer(citizensTbody, (fragment) => {
      if (latestPatientsList.length === 0) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td class="table-cell" colspan="5" style="text-align:center; padding:32px 16px; color:#94a3b8;">No registered citizens found.</td>';
        fragment.appendChild(tr);
        return;
      }

      latestPatientsList.forEach((citizen) => {
        const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || citizen.username || 'Citizen';
        const contact = citizen.contact_number || '—';
        const email = citizen.email || '—';
        const age = citizen.age ? `${citizen.age} yrs` : '—';
        const address = citizen.complete_address || '—';

        const tr = document.createElement('tr');
        tr.className = 'citizen-row';
        tr.innerHTML = `
          <td class="table-cell">
            <strong style="font-size:13px; color:#0f172a;">${sanitizeText(fullName)}</strong>
            <div style="font-size:11px; color:#64748b;">ID: #${citizen.id}</div>
          </td>
          <td class="table-cell">${sanitizeText(age)}</td>
          <td class="table-cell">${sanitizeText(contact)}</td>
          <td class="table-cell" title="${sanitizeText(address)}">${sanitizeText(address)}</td>
          <td class="table-cell" style="text-align:right;">
            <button type="button" class="btn small outline" data-action="view-ehr" style="padding:3px 10px; font-size:11px; border-radius:9999px;">View EHR</button>
          </td>
        `;

        fragment.appendChild(tr);

        attachDetailRow(tr, () => ({
          tag: 'Citizen Record',
          title: fullName,
          subtitle: `Citizen ID #${citizen.id}`,
          items: [
            { label: 'Full Name', value: fullName },
            { label: 'Age', value: age },
            { label: 'Contact Number', value: contact },
            { label: 'Email', value: email },
            { label: 'Complete Address', value: address },
            { label: 'Registration Date', value: citizen.created_at ? new Date(citizen.created_at) : '—' }
          ]
        }));

        tr.querySelector('[data-action="view-ehr"]')?.addEventListener('click', (e) => {
          e.stopPropagation();
          openCitizenHealthModal(citizen);
        });
      });
    });

    applyCitizensFinder();
    updateUsersSectionTelemetry();
  }
}

export function applyStaffFinder() {
  const staffFinderInput = document.getElementById('staff-finder-input');
  const roleFilterInput = document.getElementById('role-filter');
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

export function applyCitizensFinder() {
  const citizensFinderInput = document.getElementById('citizens-finder-input');
  const query = String(citizensFinderInput?.value || '').trim().toLowerCase();
  const rows = document.querySelectorAll('#citizens-tbody tr.citizen-row');
  rows.forEach((row) => {
    const text = row.textContent ? row.textContent.toLowerCase() : '';
    row.style.display = !query || text.includes(query) ? '' : 'none';
  });
}

export function updateUsersSectionTelemetry() {
  const staffCount = latestStaffList.length;
  const onDutyCount = latestStaffList.filter(u => getStaffPresenceStatus(u).toLowerCase().includes('duty')).length;
  const citizenCount = latestPatientsList.length;

  const staffEl = document.getElementById('users-stat-staff');
  const dutyEl = document.getElementById('users-stat-onduty');
  const citizenEl = document.getElementById('users-stat-citizens');
  const tabStaffCount = document.getElementById('tab-count-staff');
  const tabCitizenCount = document.getElementById('tab-count-citizens');

  if (staffEl) staffEl.textContent = String(staffCount);
  if (dutyEl) dutyEl.textContent = String(onDutyCount);
  if (citizenEl) citizenEl.textContent = String(citizenCount);
  if (tabStaffCount) tabStaffCount.textContent = String(staffCount);
  if (tabCitizenCount) tabCitizenCount.textContent = String(citizenCount);
}

let currentAccountData = null;

export function openAccountModal(user) {
  if (!user) return;
  const modal = document.getElementById('account-modal');
  if (!modal) return;

  currentAccountData = { ...user };
  setAccountEditMode(false);
  fillAccountEditForm(user);

  const firstName = String(user.first_name || user.firstname || '').trim();
  const lastName = String(user.last_name || user.surname || '').trim();
  const fullName = `${firstName} ${lastName}`.trim() || user.username || 'Staff Profile';

  const modalTitle = document.getElementById('modal-name');
  const modalEmail = document.getElementById('modal-email');
  const modalRole = document.getElementById('modal-role');
  const modalEmpId = document.getElementById('modal-contact');
  const modalBday = document.getElementById('modal-bday');

  if (modalTitle) modalTitle.textContent = fullName;
  if (modalEmail) modalEmail.textContent = user.email || '—';
  if (modalRole) modalRole.textContent = toTitleCase(user.role);
  if (modalEmpId) modalEmpId.textContent = user.employee_id || '—';
  if (modalBday) modalBday.textContent = user.birthday ? new Date(user.birthday).toLocaleDateString() : '—';

  modal.classList.remove('hidden');
}

export function closeAccountModal() {
  const modal = document.getElementById('account-modal');
  if (modal) modal.classList.add('hidden');
  currentAccountData = null;
}

function setAccountEditMode(isEditing) {
  const viewElements = document.querySelectorAll('#account-modal .modal-view-mode');
  const editElements = document.querySelectorAll('#account-modal .modal-edit-mode');
  viewElements.forEach(el => el.classList.toggle('hidden', isEditing));
  editElements.forEach(el => el.classList.toggle('hidden', !isEditing));
}

function fillAccountEditForm(user) {
  const fn = document.getElementById('modal-edit-first-name');
  const mn = document.getElementById('modal-edit-middle-name');
  const ln = document.getElementById('modal-edit-last-name');
  const un = document.getElementById('modal-edit-username');
  const em = document.getElementById('modal-edit-email');
  const id = document.getElementById('modal-edit-employee-id');
  const ro = document.getElementById('modal-edit-role');
  const bd = document.getElementById('modal-edit-birthday');

  if (fn) fn.value = user.first_name || user.firstname || '';
  if (mn) mn.value = user.middle_name || '';
  if (ln) ln.value = user.last_name || user.surname || '';
  if (un) un.value = user.username || '';
  if (em) em.value = user.email || '';
  if (id) id.value = user.employee_id || '';
  if (ro) ro.value = (user.role || 'nurse').toLowerCase();
  if (bd) bd.value = user.birthday || '';
}

export function openCitizenHealthModal(citizen) {
  const modal = document.getElementById('citizen-health-modal');
  if (!modal || !citizen) return;

  const nameEl = document.getElementById('chr-patient-name');
  const idEl = document.getElementById('chr-patient-id');
  const ageEl = document.getElementById('chr-patient-age');
  const phoneEl = document.getElementById('chr-patient-phone');
  const addrEl = document.getElementById('chr-patient-address');

  const fullName = `${citizen.firstname || ''} ${citizen.surname || ''}`.trim() || citizen.username;
  if (nameEl) nameEl.textContent = fullName;
  if (idEl) idEl.textContent = `CITIZEN #${citizen.id}`;
  if (ageEl) ageEl.textContent = citizen.age ? `${citizen.age} yrs old` : 'Age: —';
  if (phoneEl) phoneEl.textContent = citizen.contact_number || 'No contact number';
  if (addrEl) addrEl.textContent = citizen.complete_address || 'No registered address';

  modal.classList.remove('hidden');
}

export function initUsersSection() {
  const staffFinderInput = document.getElementById('staff-finder-input');
  const roleFilterInput = document.getElementById('role-filter');
  const citizensFinderInput = document.getElementById('citizens-finder-input');
  const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');
  const staffRegisterBtn = document.getElementById('staff-register-btn');
  const accountModalCloseBtn = document.getElementById('modal-close-btn');
  const chrCloseBtn = document.getElementById('chr-modal-close');

  if (staffFinderInput) staffFinderInput.addEventListener('input', applyStaffFinder);
  if (roleFilterInput) roleFilterInput.addEventListener('change', applyStaffFinder);
  if (citizensFinderInput) citizensFinderInput.addEventListener('input', applyCitizensFinder);

  if (refreshAccountsBtn) {
    refreshAccountsBtn.addEventListener('click', async () => {
      refreshAccountsBtn.disabled = true;
      try {
        await Promise.all([loadStaffData(), loadPatientData()]);
        showToast('Accounts directory refreshed.', 'success');
      } finally {
        refreshAccountsBtn.disabled = false;
      }
    });
  }

  if (accountModalCloseBtn) accountModalCloseBtn.addEventListener('click', closeAccountModal);
  if (chrCloseBtn) {
    chrCloseBtn.addEventListener('click', () => {
      const modal = document.getElementById('citizen-health-modal');
      if (modal) modal.classList.add('hidden');
    });
  }

  // Registration Form
  const registerForm = document.getElementById('register-form');
  if (registerForm) {
    registerForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const first_name = document.getElementById('reg-first-name')?.value.trim();
      const middle_name = document.getElementById('reg-middle-name')?.value.trim();
      const last_name = document.getElementById('reg-last-name')?.value.trim();
      const birthday = document.getElementById('reg-birthday')?.value;
      const gender = document.getElementById('reg-gender')?.value;
      const username = document.getElementById('reg-username')?.value.trim();
      const email = document.getElementById('reg-email')?.value.trim();
      const password = document.getElementById('reg-password')?.value;
      const confirmPassword = document.getElementById('reg-confirm-password')?.value;
      const role = document.getElementById('reg-role')?.value;

      const submitBtn = document.getElementById('register-submit-btn');

      if (!first_name || !last_name || !username || !email || !role || !password) {
        showToast('Please fill in all required registration fields.', 'error');
        return;
      }

      if (password !== confirmPassword) {
        showToast('Passwords do not match.', 'error');
        return;
      }

      if (submitBtn) submitBtn.disabled = true;

      try {
        const { error } = await supabase.rpc('create_staff_account_admin', {
          p_first_name: first_name,
          p_middle_name: middle_name || null,
          p_last_name: last_name,
          p_birthday: birthday || null,
          p_gender: gender || null,
          p_username: username,
          p_email: email.toLowerCase(),
          p_role: role,
          p_password: password,
          p_consent_given: true,
          p_status: 'Active'
        });

        if (error) throw error;

        registerForm.reset();
        showToast('Staff account created successfully.', 'success');
        await loadStaffData();
      } catch (err) {
        console.error('Account creation error:', err);
        showToast(err.message || 'Failed to create staff account.', 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    });
  }
}
