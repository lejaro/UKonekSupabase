/**
 * Personnel & Citizen Directory Controller
 * Manages staff accounts, citizen profiles, role administration,
 * account creation, edit modals, and staff password resets.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as staffService from '../services/staffService.js';
import { showToast, renderTableSkeleton, swapContainer } from '../utils/uiHelpers.js';
import { attachDetailRow, openDataDetail, sanitizeText, formatDetailValue } from '../utils/dataDetailModal.js';
import { openDialogModal, toTitleCase, navigateToSection } from './navigationController.js';
import { updateRegisteredCitizensMetric } from './telemetryController.js';
import { cleanNone, formatPhysicalExam } from '../utils/clinicalFormatters.js';

export const storedAccounts = new Map();
export let latestStaffList = [];
export let latestPatientsList = [];
let citizenActiveFilter = 'all';
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
    renderTableSkeleton(accountsTbody, 4, 4);
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
        tr.innerHTML = '<td class="table-cell" colspan="4" style="text-align:center; padding:32px 16px; color:#94a3b8;">No registered staff accounts found.</td>';
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
      .select('id, firstname, surname, username, email, contact_number, complete_address, age, date_of_birth, sex, emergency_contact_complete_name, emergency_contact_contact_number, relation, created_at')
      .order('created_at', { ascending: false })
      .limit(200);

    if (!error && Array.isArray(data)) {
      patients = data;
    }
  } catch (err) {
    console.warn('Error fetching citizens:', err);
  }

  latestPatientsList = Array.isArray(patients) ? [...patients] : [];
  updateRegisteredCitizensMetric(latestPatientsList.length);

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
        const regDate = citizen.created_at ? new Date(citizen.created_at).toLocaleDateString() : '—';
        const address = citizen.complete_address || '—';
        const age = citizen.age ? `${citizen.age} yrs` : '—';

        const tr = document.createElement('tr');
        tr.className = 'citizen-row';
        tr.dataset.createdAt = citizen.created_at || '';
        tr.innerHTML = `
          <td class="table-cell">
            <strong style="font-size:13px; color:#0f172a;">${sanitizeText(fullName)}</strong>
            <div style="font-size:11px; color:#64748b;">ID: #${citizen.id}</div>
          </td>
          <td class="table-cell" style="color:#475569;">${sanitizeText(email)}</td>
          <td class="table-cell" style="color:#475569;">${sanitizeText(contact)}</td>
          <td class="table-cell" style="color:#64748b;">${sanitizeText(regDate)}</td>
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

  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  rows.forEach((row) => {
    const text = row.textContent ? row.textContent.toLowerCase() : '';
    const matchesQuery = !query || text.includes(query);

    let matchesFilter = true;
    if (citizenActiveFilter === 'recent') {
      const createdRaw = row.dataset.createdAt;
      if (createdRaw) {
        const created = new Date(createdRaw);
        matchesFilter = created >= thirtyDaysAgo;
      } else {
        matchesFilter = false;
      }
    }

    row.style.display = matchesQuery && matchesFilter ? '' : 'none';
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

export function switchUsersPane(paneId = 'registered-pane') {
  const tabStaff = document.getElementById('tab-btn-staff');
  const tabCitizens = document.getElementById('tab-btn-citizens');
  const registeredPane = document.getElementById('registered-pane');
  const citizensPane = document.getElementById('citizens-pane');
  const accountsPane = document.getElementById('accounts-pane');
  const registrationPane = document.getElementById('registration-pane');
  const mgmtTitle = document.getElementById('user-mgmt-title');

  if (accountsPane) accountsPane.classList.remove('hidden');
  if (registrationPane) registrationPane.classList.add('hidden');

  const isCitizens = paneId === 'citizens-pane';

  if (tabStaff) tabStaff.classList.toggle('is-active', !isCitizens);
  if (tabCitizens) tabCitizens.classList.toggle('is-active', isCitizens);

  if (registeredPane) registeredPane.classList.toggle('hidden', isCitizens);
  if (citizensPane) citizensPane.classList.toggle('hidden', !isCitizens);

  if (mgmtTitle) {
    mgmtTitle.textContent = isCitizens ? 'Citizen Resident Directory' : 'Personnel & Citizens Registry';
  }

  if (isCitizens && latestPatientsList.length === 0) {
    loadPatientData();
  }
}

export async function openCitizenHealthModal(citizen) {
  const modal = document.getElementById('citizen-health-modal');
  if (!modal || !citizen) return;

  // Reset tabs to Consultations
  modal.querySelectorAll('.chr-tab').forEach((t, i) => {
    const active = i === 0;
    t.style.color = active ? '#16a34a' : '#64748b';
    t.style.borderBottomColor = active ? '#16a34a' : 'transparent';
    t.classList.toggle('active', active);
  });
  modal.querySelectorAll('.chr-tab-content').forEach((c, i) => {
    c.style.display = i === 0 ? '' : 'none';
  });

  const fullName = [citizen.firstname, citizen.surname].filter(Boolean).join(' ') || citizen.username || 'Citizen Resident';
  const nameEl = document.getElementById('chr-name');
  const metaEl = document.getElementById('chr-meta');
  if (nameEl) nameEl.textContent = fullName;
  if (metaEl) metaEl.textContent = citizen.email || `Citizen ID #${citizen.id}`;

  const profileEl = document.getElementById('chr-profile');
  if (profileEl) {
    const profileFields = [
      { label: 'Sex', value: citizen.sex || '—' },
      { label: 'Age', value: citizen.age ? `${citizen.age} yrs` : '—' },
      { label: 'Date of Birth', value: citizen.date_of_birth ? new Date(citizen.date_of_birth).toLocaleDateString() : '—' },
      { label: 'Contact', value: citizen.contact_number || '—' },
      { label: 'Address', value: citizen.complete_address || '—' },
      { label: 'Emergency Contact', value: citizen.emergency_contact_complete_name || '—' },
      { label: 'Emergency Phone', value: citizen.emergency_contact_contact_number || '—' },
      { label: 'Relation', value: citizen.relation || '—' }
    ];
    profileEl.innerHTML = profileFields.map(f => `
      <div>
        <div style="font-size:11px;color:#94a3b8;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;">${sanitizeText(f.label)}</div>
        <div style="font-size:13px;color:#1e293b;margin-top:2px;">${sanitizeText(String(f.value))}</div>
      </div>
    `).join('');
  }

  const setTabLoading = (id) => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = '<div style="padding:24px;text-align:center;color:#94a3b8;font-size:13px;">Loading clinical records...</div>';
  };
  ['chr-consultations-body', 'chr-vitals-body', 'chr-prescriptions-body', 'chr-laborders-body'].forEach(setTabLoading);

  modal.classList.remove('hidden');

  try {
    const citizenId = Number(citizen.id);
    const [consultRes, vitalsRes, rxRes, labRes] = await Promise.all([
      supabase.from('consultations')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .or(`patient_citizen_id.eq.${citizenId},patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId}`)
        .order('consulted_at', { ascending: false })
        .limit(50),
      supabase.from('vital_signs')
        .select('*, nurse:staff!nurse_id(first_name,last_name)')
        .eq('citizen_id', citizenId)
        .order('created_at', { ascending: false })
        .limit(50),
      supabase.from('prescription_headers')
        .select('id,issued_at,patient_identifier,doctor_staff_id,doctor:staff!doctor_staff_id(first_name,last_name),items:prescription_items(*)')
        .or(`patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId}`)
        .order('issued_at', { ascending: false })
        .limit(50),
      supabase.from('lab_orders')
        .select('*, doctor:staff!doctor_staff_id(first_name,last_name)')
        .or(`patient_citizen_id.eq.${citizenId},patient_identifier.eq.CIT-${citizenId},patient_identifier.eq.${citizenId}`)
        .order('created_at', { ascending: false })
        .limit(50)
    ]);

    // Render Consultations
    const consultEl = document.getElementById('chr-consultations-body');
    if (consultEl) {
      const rows = consultRes.data || [];
      if (!rows.length) {
        consultEl.innerHTML = '<div style="padding:24px;text-align:center;color:#94a3b8;font-size:13px;">No consultation records found.</div>';
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
          const docName = r.doctor ? [r.doctor.first_name, r.doctor.last_name].filter(Boolean).join(' ') : 'Doctor';
          tr.innerHTML = `
            <td class="table-cell" style="white-space:nowrap;">${r.consulted_at ? new Date(r.consulted_at).toLocaleDateString() : '—'}</td>
            <td class="table-cell"><strong>${sanitizeText(r.diagnosis || '—')}</strong></td>
            <td class="table-cell" style="white-space:nowrap;">${sanitizeText(docName)}</td>
          `;
          tr.addEventListener('click', () => {
            openDataDetail({
              title: 'Consultation Record',
              subtitle: r.consulted_at ? new Date(r.consulted_at).toLocaleString() : 'Record',
              tag: 'Clinical EHR',
              items: [
                { label: 'Attending Doctor', value: docName },
                { label: 'Diagnosis', value: cleanNone(r.diagnosis) },
                { label: 'Chief Complaint', value: cleanNone(r.chief_complaint || r.symptoms) },
                { label: 'Clinical Notes', value: cleanNone(r.notes) },
                { label: 'Physical Exam', value: formatPhysicalExam(r.physical_exam) }
              ]
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
        vitalsEl.innerHTML = '<div style="padding:24px;text-align:center;color:#94a3b8;font-size:13px;">No vital assessment records found.</div>';
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
          const nurseName = r.nurse ? [r.nurse.first_name, r.nurse.last_name].filter(Boolean).join(' ') : 'Nurse';
          tr.innerHTML = `
            <td class="table-cell" style="white-space:nowrap;">${r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'}</td>
            <td class="table-cell">BP: ${sanitizeText(r.blood_pressure || '—')} | Temp: ${sanitizeText(r.temperature || '—')}°C | HR: ${sanitizeText(r.heart_rate || '—')} bpm</td>
            <td class="table-cell" style="white-space:nowrap;">${sanitizeText(nurseName)}</td>
          `;
          tbody.appendChild(tr);
        });
      }
    }

    // Render Prescriptions
    const rxEl = document.getElementById('chr-prescriptions-body');
    if (rxEl) {
      const rows = rxRes.data || [];
      if (!rows.length) {
        rxEl.innerHTML = '<div style="padding:24px;text-align:center;color:#94a3b8;font-size:13px;">No prescription records found.</div>';
      } else {
        rxEl.innerHTML = rows.map(rx => {
          const items = (rx.items || []).map(it =>
            `<li style="font-size:12px;color:#374151;">${sanitizeText(it.medicine_name)} — ${it.quantity} ${sanitizeText(it.unit || '')} ${it.dosage ? `(${sanitizeText(it.dosage)})` : ''} ${it.frequency || ''}</li>`
          ).join('');
          const doc = rx.doctor ? [rx.doctor.first_name, rx.doctor.last_name].filter(Boolean).join(' ') : 'Attending Doctor';
          const date = rx.issued_at ? new Date(rx.issued_at).toLocaleDateString() : '—';
          return `
            <div style="border:1px solid #e2e8f0;border-radius:10px;padding:14px 16px;margin-bottom:10px;">
              <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-size:13px;font-weight:600;color:#1e293b;">${date}</span>
                <span style="font-size:12px;color:#64748b;">${sanitizeText(doc)}</span>
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
        labEl.innerHTML = '<div style="padding:24px;text-align:center;color:#94a3b8;font-size:13px;">No lab orders found.</div>';
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
              const doc = r.doctor ? [r.doctor.first_name, r.doctor.last_name].filter(Boolean).join(' ') : 'Doctor';
              return `<tr>
                <td class="table-cell" style="white-space:nowrap;">${r.created_at ? new Date(r.created_at).toLocaleDateString() : '—'}</td>
                <td class="table-cell"><strong>${sanitizeText(r.test_name || '—')}</strong></td>
                <td class="table-cell"><span class="${statusClass}">${sanitizeText(r.status || '—')}</span></td>
                <td class="table-cell" style="white-space:nowrap;">${sanitizeText(doc)}</td>
              </tr>`;
            }).join('')}</tbody>
          </table>`;
      }
    }
  } catch (err) {
    console.warn('Error loading citizen EHR:', err);
  }
}

export function initUsersSection() {
  const tabStaff = document.getElementById('tab-btn-staff');
  const tabCitizens = document.getElementById('tab-btn-citizens');
  const staffFinderInput = document.getElementById('staff-finder-input');
  const roleFilterInput = document.getElementById('role-filter');
  const citizensFinderInput = document.getElementById('citizens-finder-input');
  const refreshAccountsBtn = document.getElementById('refresh-accounts-btn');
  const staffRegisterBtn = document.getElementById('staff-register-btn');
  const regBackBtn = document.getElementById('registration-back-btn');
  const backToDashBtn = document.getElementById('back-to-dashboard-btn');
  const accountModalCloseBtn = document.getElementById('modal-close-btn');
  const chrModal = document.getElementById('citizen-health-modal');
  const chrCloseBtn = document.getElementById('chr-close-btn');

  // Segmented In-Page Tab Switching
  if (tabStaff) tabStaff.addEventListener('click', () => switchUsersPane('registered-pane'));
  if (tabCitizens) tabCitizens.addEventListener('click', () => switchUsersPane('citizens-pane'));

  // Registration Pane navigation
  if (staffRegisterBtn) {
    staffRegisterBtn.addEventListener('click', () => {
      const accountsPane = document.getElementById('accounts-pane');
      const regPane = document.getElementById('registration-pane');
      if (accountsPane) accountsPane.classList.add('hidden');
      if (regPane) regPane.classList.remove('hidden');
    });
  }

  if (regBackBtn) {
    regBackBtn.addEventListener('click', () => {
      const accountsPane = document.getElementById('accounts-pane');
      const regPane = document.getElementById('registration-pane');
      if (accountsPane) accountsPane.classList.remove('hidden');
      if (regPane) regPane.classList.add('hidden');
    });
  }

  if (backToDashBtn) {
    backToDashBtn.addEventListener('click', () => navigateToSection('dashboard-section'));
  }

  if (staffFinderInput) staffFinderInput.addEventListener('input', applyStaffFinder);
  if (roleFilterInput) roleFilterInput.addEventListener('change', applyStaffFinder);
  if (citizensFinderInput) citizensFinderInput.addEventListener('input', applyCitizensFinder);

  // Filter Chips for Citizens
  document.querySelectorAll('#citizen-filter-chips .ph-filter-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('#citizen-filter-chips .ph-filter-chip').forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      citizenActiveFilter = chip.getAttribute('data-filter') || 'all';
      applyCitizensFinder();
    });
  });

  // Role Chips for Staff
  document.querySelectorAll('#staff-role-chips .ph-filter-chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('#staff-role-chips .ph-filter-chip').forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      const roleFilter = document.getElementById('role-filter');
      if (roleFilter) roleFilter.value = chip.getAttribute('data-role') || '';
      applyStaffFinder();
    });
  });

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

  // Citizen Health Record Modal Listeners
  if (chrCloseBtn && chrModal) {
    chrCloseBtn.addEventListener('click', () => chrModal.classList.add('hidden'));
  }
  if (chrModal) {
    chrModal.addEventListener('click', (e) => {
      if (e.target === chrModal) chrModal.classList.add('hidden');
    });

    chrModal.querySelectorAll('.chr-tab').forEach((tab) => {
      tab.addEventListener('click', () => {
        const targetId = tab.dataset.chrTab;
        chrModal.querySelectorAll('.chr-tab').forEach((t) => {
          const isTarget = t === tab;
          t.classList.toggle('active', isTarget);
          t.style.color = isTarget ? '#16a34a' : '#64748b';
          t.style.borderBottomColor = isTarget ? '#16a34a' : 'transparent';
        });
        chrModal.querySelectorAll('.chr-tab-content').forEach((pane) => {
          pane.style.display = pane.id === targetId ? '' : 'none';
        });
      });
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

export const initUsersController = initUsersSection;
export const loadStaffDirectory = loadStaffData;
export const loadCitizenDirectory = loadPatientData;


