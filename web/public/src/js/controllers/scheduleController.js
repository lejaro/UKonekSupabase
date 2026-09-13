/**
 * Schedule & Availability Controller
 * Manages doctor consultation schedules, roster availability statuses,
 * calendar slots CRUD, and Realtime availability updates.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import * as scheduleService from '../services/scheduleService.js';
import { showToast, swapContainer, withTimeout } from '../utils/uiHelpers.js';
import { attachDetailRow } from '../utils/dataDetailModal.js';
import { openDialogModal, toTitleCase, getDoctorDisplayName, isDoctorRole, isScheduleRole } from './navigationController.js';

export const AVAILABILITY_LABELS = {
  available: 'Available',
  on_break: 'On Break',
  unavailable: 'Unavailable'
};

export let cachedScheduleStaff = [];
export let cachedScheduleDoctors = [];
export let cachedScheduleEntries = [];
let staffAvailabilityChannel = null;

export function normalizeAvailabilityStatus(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (raw === 'available' || raw === 'on_duty' || raw === 'onduty') return 'available';
  if (raw === 'on break' || raw === 'on_break' || raw === 'break') return 'on_break';
  if (raw === 'unavailable' || raw === 'off duty' || raw === 'off_duty' || raw === 'offduty') return 'unavailable';
  return 'unavailable';
}

export function normalizeTimeHHMM(value) {
  const text = String(value || '').trim();
  const match = text.match(/^(\d{1,2}):(\d{2})/);
  if (!match) return '';
  const hours = String(Math.min(23, Math.max(0, Number(match[1])))).padStart(2, '0');
  const minutes = String(Math.min(59, Math.max(0, Number(match[2])))).padStart(2, '0');
  return `${hours}:${minutes}`;
}

export function formatScheduleTime(value) {
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
    const parts = String(item.time).split('-').map(it => normalizeTimeHHMM(it));
    start = parts[0] || '';
    if (!end) end = parts[1] || '';
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

function isScheduleExpired(entry) {
  const scheduleDate = String(entry?.schedule_date || entry?.date || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(scheduleDate)) return false;
  if (scheduleDate < getTodayScheduleDateKey()) return true;

  const today = getTodayScheduleDateKey();
  if (scheduleDate !== today) return false;

  const end = normalizeTimeHHMM(entry?.end_time || '');
  if (!end) return false;

  const [endHour, endMinute] = end.split(':').map(Number);
  if (!Number.isFinite(endHour) || !Number.isFinite(endMinute)) return false;

  const now = new Date();
  const nowMinutes = (now.getHours() * 60) + now.getMinutes();
  const endMinutes = (endHour * 60) + endMinute;
  return endMinutes < nowMinutes;
}

async function purgePastSchedules(records, user) {
  const normalized = Array.isArray(records) ? records : [];
  const activeRecords = normalized.filter((entry) => !isScheduleExpired(entry));
  const expired = normalized.filter((entry) => isScheduleExpired(entry));

  if (!expired.length) return activeRecords;

  const expiredIds = expired
    .map((entry) => entry?.id)
    .filter((id) => id !== null && id !== undefined && String(id).trim() !== '');

  if (!expiredIds.length || !sessionStore.isAdmin(user)) {
    return activeRecords;
  }

  try {
    await supabase.from('doctor_schedules').delete().in('id', expiredIds);
  } catch (error) {
    console.warn('Auto-delete past schedules warning:', error);
  }

  return activeRecords;
}

export function hasScheduleConflict({ doctorStaffId, scheduleDate, startTime, endTime, excludeId }) {
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

export function renderCardsSkeleton(container, count = 2) {
  if (!container) return;
  let html = '';
  for (let i = 0; i < count; i++) {
    html += `
      <div class="staff-station-card skeleton-row" style="padding:16px; border:1px solid #e2e8f0; border-radius:12px;">
        <div style="display:flex; align-items:center; gap:12px;">
          <div class="skeleton-shimmer" style="width:42px; height:42px; border-radius:50%;"></div>
          <div style="flex:1;">
            <div class="skeleton-shimmer skeleton-text" style="width:60%; height:14px; margin-bottom:6px;"></div>
            <div class="skeleton-shimmer skeleton-text" style="width:40%; height:11px;"></div>
          </div>
        </div>
      </div>
    `;
  }
  container.innerHTML = html;
}

export async function updateStaffAvailabilityById(staffId, status) {
  if (!staffId) throw new Error('Missing staff id.');
  const normalized = normalizeAvailabilityStatus(status);

  const { error } = await supabase.rpc('set_staff_availability', {
    p_target_staff_id: Number(staffId),
    p_status: normalized
  });

  if (error) {
    throw new Error(error.message || 'Unable to update availability status.');
  }

  updateAvailabilityInCaches(staffId, normalized);
  return true;
}

export function updateAvailabilityInCaches(staffId, status, newRow = null) {
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
}

export async function handleAvailabilityToggle(staff, nextStatus, toggleGroup) {
  if (!staff || !toggleGroup) return;
  const user = sessionStore.getUser();

  const staffId = staff.id;
  const isSelf = user && (
    String(staffId) === String(user.id) || 
    (staff.email && user.email && String(staff.email).toLowerCase() === String(user.email).toLowerCase())
  );
  if (!isSelf && !sessionStore.isAdmin(user) && !sessionStore.isDoctor(user) && !sessionStore.isNurse(user)) {
    showToast('You can only update your own availability.', 'error');
    return;
  }
  const prevStatus = normalizeAvailabilityStatus(staff?.availability_status);
  const normalizedNext = normalizeAvailabilityStatus(nextStatus);
  if (prevStatus === normalizedNext) return;

  applyAvailabilityToggleState(toggleGroup, normalizedNext);
  updateAvailabilityInCaches(staffId, normalizedNext);

  try {
    await updateStaffAvailabilityById(staffId, normalizedNext);
    const statusNode = toggleGroup.closest('.staff-station-card')?.querySelector('.station-status-pill');
    if (statusNode) {
      statusNode.className = `station-status-pill status-${normalizedNext}`;
      const label = AVAILABILITY_LABELS[normalizedNext] || (normalizedNext === 'on_break' ? 'On Break' : 'Off Duty');
      statusNode.innerHTML = `<span class="pill-dot"></span> ${label}`;
    }
  } catch (error) {
    updateAvailabilityInCaches(staffId, prevStatus);
    applyAvailabilityToggleState(toggleGroup, prevStatus);
    showToast(error?.message || 'Unable to update availability.', 'error');
  }
}

function applyAvailabilityToggleState(toggleGroup, status) {
  if (!toggleGroup) return;
  const normalized = normalizeAvailabilityStatus(status);
  toggleGroup.querySelectorAll('button').forEach((btn) => {
    const btnStatus = normalizeAvailabilityStatus(btn.dataset.status);
    btn.classList.toggle('is-active', btnStatus === normalized);
  });

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
}

export function renderScheduleDoctors(staffList, user) {
  const doctorGrid = document.getElementById('schedule-doctors-grid') || document.getElementById('schedule-doctors-tbody');
  const nurseGrid = document.getElementById('schedule-nurses-grid') || document.getElementById('schedule-nurses-tbody');
  if (!doctorGrid || !nurseGrid) return;

  const doctors = (staffList || []).filter((s) => isDoctorRole(s?.role));
  const nurses = (staffList || []).filter((s) => {
    const r = String(s?.role || '').toLowerCase();
    return r === 'nurse' || r === 'staff';
  });

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
      const availabilityStatus = normalizeAvailabilityStatus(staff?.availability_status || staff?.availabilityStatus);
      const isSelf = user && (
        String(staff.id) === String(user.id) ||
        (staff.email && user.email && String(staff.email).toLowerCase() === String(user.email).toLowerCase())
      );
      const canEditAvailability = isSelf || sessionStore.isAdmin(user) || sessionStore.isDoctor(user) || sessionStore.isNurse(user);

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
            <span class="staff-card-actions-label">${isSelf ? 'Your Shift Control' : (sessionStore.isAdmin(user) ? 'Shift Control (Admin)' : 'Shift Control')}</span>
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

export function renderSchedules(schedules, user, doctors = []) {
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
    if (sessionStore.isAdmin(user)) {
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
          loadSchedules(sessionStore.getUser());
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

export function populateScheduleDoctorSelect(selectedDoctorId = null) {
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

export async function loadSchedules(user) {
  const doctorGrid = document.getElementById('schedule-doctors-grid') || document.getElementById('schedule-doctors-tbody');
  const nurseGrid = document.getElementById('schedule-nurses-grid') || document.getElementById('schedule-nurses-tbody');
  if (doctorGrid) renderCardsSkeleton(doctorGrid, 2);
  if (nurseGrid) renderCardsSkeleton(nurseGrid, 2);

  let schedules = [];
  let staffRoster = [];
  let doctors = [];

  try {
    const staffRpc = await supabase.rpc('list_staff_accounts');
    const staff = !staffRpc.error
      ? (Array.isArray(staffRpc.data) ? staffRpc.data : [])
      : [];
    staffRoster = staff;
    doctors = staffRoster.filter((item) => isDoctorRole(item?.role));

    const scheduleRpc = await supabase.rpc('list_doctor_schedules');
    if (!scheduleRpc.error) {
      schedules = Array.isArray(scheduleRpc.data) ? scheduleRpc.data : [];
    } else {
      const { data } = await supabase
        .from('doctor_schedules')
        .select('*')
        .order('schedule_date', { ascending: true })
        .order('start_time', { ascending: true });
      schedules = data || [];
    }
  } catch (err) {
    console.error('Error loading schedules:', err);
  }

  schedules = (Array.isArray(schedules) ? schedules : []).map(normalizeScheduleRecord);
  schedules = await purgePastSchedules(schedules, user);
  cachedScheduleEntries = [...schedules];

  cachedScheduleStaff = Array.isArray(staffRoster) ? staffRoster.filter((item) => isScheduleRole(item?.role)) : [];
  cachedScheduleDoctors = Array.isArray(doctors) ? [...doctors] : [];

  populateScheduleDoctorSelect();
  renderScheduleDoctors(cachedScheduleStaff, user);
  renderSchedules(schedules, user, cachedScheduleDoctors);
}

export async function upsertScheduleRecord({ id, doctorId, doctorName, date, startTime, endTime, notes }) {
  const rpcPayload = {
    p_id: id ? Number(id) : null,
    p_doctor_staff_id: Number(doctorId),
    p_schedule_date: date,
    p_start_time: startTime,
    p_end_time: endTime,
    p_notes: notes || null
  };

  const rpcResult = await supabase.rpc('upsert_doctor_schedule_admin', rpcPayload);
  if (!rpcResult.error) return true;

  const payload = {
    doctor_staff_id: Number(doctorId),
    doctor_name: doctorName,
    schedule_date: date,
    start_time: startTime,
    end_time: endTime,
    notes: notes || null,
    created_by_staff_id: Number(sessionStore.getUser()?.id) || null
  };

  let result;
  if (id) {
    result = await supabase.from('doctor_schedules').update(payload).eq('id', id);
  } else {
    result = await supabase.from('doctor_schedules').insert(payload);
  }

  if (result.error) throw result.error;
  return true;
}

export async function deleteScheduleRecordById(id) {
  const rpcResult = await supabase.rpc('delete_doctor_schedule_admin', {
    p_id: Number(id)
  });
  if (!rpcResult.error) return true;

  const { error } = await supabase.from('doctor_schedules').delete().eq('id', id);
  if (error) throw error;
  return true;
}

export function openScheduleModal(mode = 'create', schedule = null) {
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

  if (errorNode) errorNode.textContent = '';
  populateScheduleDoctorSelect(schedule?.doctor_staff_id || null);

  if (mode === 'edit' && schedule) {
    idInput.value = schedule.id || '';
    doctorInput.value = schedule.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    dateInput.value = schedule.schedule_date || schedule.date || '';
    startInput.value = normalizeTimeHHMM(schedule.start_time || schedule.time || '');
    endInput.value = normalizeTimeHHMM(schedule.end_time || '');
    if (notesInput) notesInput.value = schedule.notes || '';
    if (deleteBtn) deleteBtn.classList.remove('hidden');
  } else {
    idInput.value = '';
    doctorInput.value = schedule?.doctor_staff_id ? String(schedule.doctor_staff_id) : '';
    dateInput.value = '';
    startInput.value = '';
    endInput.value = '';
    if (notesInput) notesInput.value = '';
    if (deleteBtn) deleteBtn.classList.add('hidden');
  }

  modal.classList.remove('hidden');
}

export function closeScheduleModal() {
  const modal = document.getElementById('schedule-editor-modal');
  if (modal) modal.classList.add('hidden');
}

export function teardownStaffAvailability() {
  if (staffAvailabilityChannel) {
    try {
      supabase.removeChannel(staffAvailabilityChannel);
      console.log('[Schedule] Staff availability realtime unsubscribed.');
    } catch (_) {}
    staffAvailabilityChannel = null;
  }
}

export function subscribeToStaffAvailability() {
  if (staffAvailabilityChannel) return;

  try {
    staffAvailabilityChannel = supabase
      .channel('staff-availability')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'staff'
      }, (payload) => {
        const updated = payload?.new;
        if (!updated || !updated.id) return;
        if (!isScheduleRole(updated.role)) return;
        updateAvailabilityInCaches(updated.id, updated.availability_status, updated);
        if (!document.getElementById('schedule-section')?.classList.contains('hidden')) {
          renderScheduleDoctors(cachedScheduleStaff, sessionStore.getUser());
        }
      })
      .subscribe();
  } catch (error) {
    console.warn('Realtime availability subscription failed:', error);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', teardownStaffAvailability);
}

export function initSchedule() {
  const schedForm = document.getElementById('schedule-form');
  if (schedForm) {
    schedForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const id = document.getElementById('sched-id')?.value;
      const doctorId = String(document.getElementById('sched-doctor-id')?.value || '').trim();
      const date = document.getElementById('sched-date')?.value;
      const startTime = String(document.getElementById('sched-start-time')?.value || '').trim();
      const endTime = String(document.getElementById('sched-end-time')?.value || '').trim();
      const notes = String(document.getElementById('sched-notes')?.value || '').trim();
      const errorNode = document.getElementById('sched-form-error');
      if (errorNode) errorNode.textContent = '';

      if (!doctorId || !date || !startTime || !endTime) {
        if (errorNode) errorNode.textContent = 'Doctor, date, start time, and end time are required.';
        return;
      }

      if (startTime >= endTime) {
        if (errorNode) errorNode.textContent = 'End time must be after start time.';
        return;
      }

      if (hasScheduleConflict({
        doctorStaffId: doctorId,
        scheduleDate: date,
        startTime,
        endTime,
        excludeId: id || null
      })) {
        if (errorNode) errorNode.textContent = 'This doctor already has an overlapping schedule on that date.';
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
        loadSchedules(sessionStore.getUser());
        showToast(id ? 'Schedule updated.' : 'Schedule created successfully.', 'success');
      } catch (err) {
        console.error(err);
        if (errorNode) errorNode.textContent = err.message || 'Network error';
      }
    });
  }

  const schedCancelBtn = document.getElementById('sched-cancel-btn');
  if (schedCancelBtn) schedCancelBtn.addEventListener('click', closeScheduleModal);

  const createScheduleBtn = document.getElementById('create-schedule-btn');
  if (createScheduleBtn) {
    createScheduleBtn.addEventListener('click', () => openScheduleModal('create'));
  }

  const schedDeleteBtn = document.getElementById('sched-delete-btn');
  if (schedDeleteBtn) {
    schedDeleteBtn.addEventListener('click', async () => {
      const id = document.getElementById('sched-id')?.value;
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
        loadSchedules(sessionStore.getUser());
      } catch (err) {
        console.error(err);
        showToast('Unable to delete schedule', 'error');
      }
    });
  }

  subscribeToStaffAvailability();
}

export const initScheduleController = initSchedule;

export async function loadDoctorSchedules(user = sessionStore.getUser()) {
  return loadSchedules(user);
}

