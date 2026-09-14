/**
 * UKonek Promo Poster & Announcements Controller
 * Enables Doctors and Nurses to create, manage, and publish promo posters
 * with photo uploads and image URL links to the patient mobile app home screen.
 */

import { supabase } from '../lib/supabaseClient.js';
import { sessionStore } from '../services/sessionStore.js';
import { showToast } from '../utils/uiHelpers.js';
import { openModal, closeModal } from '../utils/dialogModal.js';

let _promoPosters = [];
let _activeFilter = 'all';
let _searchQuery = '';
let _selectedImageFile = null;
let _imageUrl = '';
let _isSubmitting = false;

/**
 * Check if the currently logged-in user is authorized to manage promo posters (doctor, nurse, admin).
 */
export function isAuthorizedToManagePromo() {
  const user = sessionStore.getUser();
  const role = (user?.role || sessionStorage.getItem('ukonek_role') || '').trim().toLowerCase();
  return ['doctor', 'nurse', 'admin'].includes(role);
}

/**
 * Initialize the promo poster controller, events, and UI bindings.
 */
export function initPromoPosterController() {
  console.log('[PromoPosters] Initializing controller...');
  setupActionButtons();
  setupModalEvents();
  setupFilterAndSearch();
  loadPromoPosters();
}

/**
 * Setup buttons in the toolbar (New Promo Poster).
 */
function setupActionButtons() {
  const newBtn = document.getElementById('create-announcement-topright');
  if (newBtn) {
    // Only show to doctor, nurse, admin
    if (isAuthorizedToManagePromo()) {
      newBtn.style.display = 'inline-flex';
      newBtn.addEventListener('click', (e) => {
        e.preventDefault();
        openPromoPosterModal();
      });
    } else {
      newBtn.style.display = 'none';
    }
  }
}

/**
 * Setup the creation modal events, tab toggles, file upload dropzone, and live previews.
 */
function setupModalEvents() {
  const modal = document.getElementById('promo-poster-modal');
  const closeBtn = document.getElementById('promo-close-modal-btn');
  const cancelBtn = document.getElementById('promo-cancel-btn');
  const form = document.getElementById('promo-poster-form');
  const submitBtn = document.getElementById('promo-submit-btn');

  if (closeBtn && modal) {
    closeBtn.addEventListener('click', () => closeModal(modal));
  }
  if (cancelBtn && modal) {
    cancelBtn.addEventListener('click', () => closeModal(modal));
  }

  // Image source tabs
  const tabUpload = document.getElementById('promo-tab-upload');
  const tabUrl = document.getElementById('promo-tab-url');
  const paneUpload = document.getElementById('promo-upload-pane');
  const paneUrl = document.getElementById('promo-url-pane');

  if (tabUpload && tabUrl && paneUpload && paneUrl) {
    tabUpload.addEventListener('click', () => {
      tabUpload.style.background = '#fff';
      tabUpload.style.color = '#0f172a';
      tabUpload.style.borderColor = '#cbd5e1';
      tabUpload.style.fontWeight = '700';

      tabUrl.style.background = 'transparent';
      tabUrl.style.color = '#64748b';
      tabUrl.style.borderColor = 'transparent';
      tabUrl.style.fontWeight = '600';

      paneUpload.classList.remove('hidden');
      paneUrl.classList.add('hidden');
    });

    tabUrl.addEventListener('click', () => {
      tabUrl.style.background = '#fff';
      tabUrl.style.color = '#0f172a';
      tabUrl.style.borderColor = '#cbd5e1';
      tabUrl.style.fontWeight = '700';

      tabUpload.style.background = 'transparent';
      tabUpload.style.color = '#64748b';
      tabUpload.style.borderColor = 'transparent';
      tabUpload.style.fontWeight = '600';

      paneUrl.classList.remove('hidden');
      paneUpload.classList.add('hidden');
    });
  }

  // File upload input & dropzone
  const fileInput = document.getElementById('promo-file-input');
  const dropzone = document.getElementById('promo-upload-pane');

  if (dropzone && fileInput) {
    dropzone.addEventListener('click', () => fileInput.click());

    dropzone.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropzone.style.borderColor = '#16a34a';
      dropzone.style.background = '#f0fdf4';
    });

    dropzone.addEventListener('dragleave', () => {
      dropzone.style.borderColor = '#cbd5e1';
      dropzone.style.background = '#f8fafc';
    });

    dropzone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropzone.style.borderColor = '#cbd5e1';
      dropzone.style.background = '#f8fafc';
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        handleImageFileSelected(e.dataTransfer.files[0]);
      }
    });

    fileInput.addEventListener('change', (e) => {
      if (e.target.files && e.target.files.length > 0) {
        handleImageFileSelected(e.target.files[0]);
      }
    });
  }

  // URL input change listener
  const urlInput = document.getElementById('promo-url-input');
  if (urlInput) {
    urlInput.addEventListener('input', () => {
      const val = urlInput.value.trim();
      if (val) {
        _imageUrl = val;
        _selectedImageFile = null;
        updateImagePreviewUI(val, 'Linked Web Image');
      } else {
        if (!_selectedImageFile) {
          clearImagePreviewUI();
        }
      }
    });
  }

  // Remove image button
  const removeImgBtn = document.getElementById('promo-remove-img-btn');
  if (removeImgBtn) {
    removeImgBtn.addEventListener('click', (e) => {
      e.preventDefault();
      clearImagePreviewUI();
    });
  }

  // Live text update listeners
  const titleInput = document.getElementById('promo-title');
  const contentInput = document.getElementById('promo-content');
  const liveTitle = document.getElementById('promo-live-title');
  const liveDesc = document.getElementById('promo-live-desc');

  if (titleInput && liveTitle) {
    titleInput.addEventListener('input', () => {
      liveTitle.textContent = titleInput.value.trim() || 'Your Promo Title';
    });
  }

  if (contentInput && liveDesc) {
    contentInput.addEventListener('input', () => {
      liveDesc.textContent = contentInput.value.trim() || 'Announcement details will be summarized here on the patient\'s phone.';
    });
  }

  // Submit button
  if (submitBtn) {
    submitBtn.addEventListener('click', (e) => {
      e.preventDefault();
      handleSubmitPromoPoster();
    });
  }
}

/**
 * Handles selecting an image file and creating an object URL preview.
 */
function handleImageFileSelected(file) {
  if (!file.type.startsWith('image/')) {
    showToast('Please select a valid image file (JPG, PNG, or WEBP).', 'error');
    return;
  }

  if (file.size > 10 * 1024 * 1024) {
    showToast('Image size exceeds 10MB limit.', 'error');
    return;
  }

  _selectedImageFile = file;
  const objectUrl = URL.createObjectURL(file);
  _imageUrl = objectUrl;

  // Clear url text input
  const urlInput = document.getElementById('promo-url-input');
  if (urlInput) urlInput.value = '';

  updateImagePreviewUI(objectUrl, file.name);
}

/**
 * Updates both the image preview box and the mini mobile mockup.
 */
function updateImagePreviewUI(src, labelText) {
  const container = document.getElementById('promo-image-preview-container');
  const thumb = document.getElementById('promo-preview-thumb');
  const label = document.getElementById('promo-preview-filename');
  const liveImg = document.getElementById('promo-live-img');
  const liveFallback = document.getElementById('promo-live-fallback-icon');

  if (container) container.classList.remove('hidden');
  if (thumb) thumb.src = src;
  if (label) label.textContent = labelText || 'Photo attached';

  if (liveImg && liveFallback) {
    liveImg.src = src;
    liveImg.style.display = 'block';
    liveFallback.style.display = 'none';
  }
}

/**
 * Resets the attached image preview.
 */
function clearImagePreviewUI() {
  _selectedImageFile = null;
  _imageUrl = '';

  const fileInput = document.getElementById('promo-file-input');
  if (fileInput) fileInput.value = '';

  const urlInput = document.getElementById('promo-url-input');
  if (urlInput) urlInput.value = '';

  const container = document.getElementById('promo-image-preview-container');
  if (container) container.classList.add('hidden');

  const liveImg = document.getElementById('promo-live-img');
  const liveFallback = document.getElementById('promo-live-fallback-icon');
  if (liveImg && liveFallback) {
    liveImg.src = '';
    liveImg.style.display = 'none';
    liveFallback.style.display = 'block';
  }
}

/**
 * Open the modal and clear old inputs.
 */
export function openPromoPosterModal() {
  if (!isAuthorizedToManagePromo()) {
    showToast('Only Doctors and Nurses have permissions to publish promo posters.', 'warning');
    return;
  }

  const modal = document.getElementById('promo-poster-modal');
  if (!modal) return;

  // Reset form inputs
  const titleInput = document.getElementById('promo-title');
  const contentInput = document.getElementById('promo-content');
  const visibilitySelect = document.getElementById('promo-visibility');
  const liveTitle = document.getElementById('promo-live-title');
  const liveDesc = document.getElementById('promo-live-desc');

  if (titleInput) titleInput.value = '';
  if (contentInput) contentInput.value = '';
  if (visibilitySelect) visibilitySelect.value = 'citizen';
  if (liveTitle) liveTitle.textContent = 'Your Promo Title';
  if (liveDesc) liveDesc.textContent = 'Announcement details will be summarized here on the patient\'s phone.';

  clearImagePreviewUI();
  openModal(modal);
}

/**
 * Submits the promo poster to Supabase.
 */
async function handleSubmitPromoPoster() {
  if (_isSubmitting) return;

  const titleInput = document.getElementById('promo-title');
  const contentInput = document.getElementById('promo-content');
  const visibilitySelect = document.getElementById('promo-visibility');

  const title = titleInput?.value.trim() || '';
  const content = contentInput?.value.trim() || '';
  const visibility = visibilitySelect?.value || 'citizen';

  if (!title) {
    showToast('Please enter a promo title.', 'error');
    titleInput?.focus();
    return;
  }

  if (!content) {
    showToast('Please enter the announcement details.', 'error');
    contentInput?.focus();
    return;
  }

  const submitBtn = document.getElementById('promo-submit-btn');
  const spinner = document.getElementById('promo-submit-spinner');
  const label = document.getElementById('promo-submit-label');

  try {
    _isSubmitting = true;
    if (submitBtn) submitBtn.disabled = true;
    if (spinner) spinner.style.display = 'inline-block';
    if (label) label.textContent = 'Publishing...';

    let finalImageUrl = null;

    // 1. If a local file was chosen, upload to Supabase Storage 'promo-banners'
    if (_selectedImageFile) {
      const ext = _selectedImageFile.name.split('.').pop() || 'jpg';
      const cleanName = _selectedImageFile.name.replace(/[^a-zA-Z0-9]/g, '_');
      const filePath = `promos/${Date.now()}_${cleanName}.${ext}`;

      console.log('[PromoPosters] Uploading image to storage bucket promo-banners:', filePath);
      const { error: uploadErr } = await supabase.storage
        .from('promo-banners')
        .upload(filePath, _selectedImageFile, {
          cacheControl: '3600',
          upsert: true,
          contentType: _selectedImageFile.type || 'image/jpeg'
        });

      if (uploadErr) {
        console.warn('[PromoPosters] Storage upload error, falling back to data URL:', uploadErr);
        // Fallback: Read as data URL if storage upload failed
        finalImageUrl = await readFileAsDataURL(_selectedImageFile);
      } else {
        const { data: publicUrlData } = supabase.storage
          .from('promo-banners')
          .getPublicUrl(filePath);
        finalImageUrl = publicUrlData?.publicUrl || null;
      }
    } else if (_imageUrl && _imageUrl.startsWith('http')) {
      finalImageUrl = _imageUrl;
    }

    // 2. Fetch current staff ID
    const user = sessionStore.getUser();
    let staffId = user?.id || null;

    if (!staffId) {
      // Try resolving staff id from Supabase auth user
      try {
        const { data: { user: authUser } } = await supabase.auth.getUser();
        if (authUser?.id) {
          const { data: staffRecord } = await supabase
            .from('staff')
            .select('id')
            .eq('auth_user_id', authUser.id)
            .maybeSingle();
          if (staffRecord?.id) staffId = staffRecord.id;
        }
      } catch (_) {}
    }

    // 3. Insert into announcements table
    const { error: insertErr } = await supabase
      .from('announcements')
      .insert({
        title,
        content,
        visibility,
        image_url: finalImageUrl,
        created_by_staff_id: staffId
      });

    if (insertErr) {
      throw insertErr;
    }

    showToast('Promo poster published successfully! It is now live on the mobile app.', 'success');
    const modal = document.getElementById('promo-poster-modal');
    if (modal) closeModal(modal);

    // Refresh promo list
    await loadPromoPosters();
  } catch (err) {
    console.error('[PromoPosters] Failed to publish promo poster:', err);
    showToast(`Failed to publish promo poster: ${err.message || err}`, 'error');
  } finally {
    _isSubmitting = false;
    if (submitBtn) submitBtn.disabled = false;
    if (spinner) spinner.style.display = 'none';
    if (label) label.textContent = 'Publish Promo Poster';
  }
}

/**
 * Helper to convert file to data URL fallback if bucket upload fails.
 */
function readFileAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

/**
 * Filter & search listeners for announcements table.
 */
function setupFilterAndSearch() {
  const searchInput = document.getElementById('announcements-search-input');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      _searchQuery = e.target.value.toLowerCase().trim();
      renderPromoPostersTable();
    });
  }

  const filterChips = document.getElementById('announcement-filter-chips');
  if (filterChips) {
    filterChips.addEventListener('click', (e) => {
      const chip = e.target.closest('.ph-filter-chip');
      if (!chip) return;
      filterChips.querySelectorAll('.ph-filter-chip').forEach(c => c.classList.remove('is-active'));
      chip.classList.add('is-active');
      _activeFilter = chip.getAttribute('data-filter') || 'all';
      renderPromoPostersTable();
    });
  }
}

/**
 * Fetch promo posters from announcements table with creator staff details.
 */
export async function loadPromoPosters() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;

  try {
    tbody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:32px; color:#64748b;">
          <div style="display:inline-flex; align-items:center; gap:8px;">
            <span class="btn-spinner" style="display:inline-block; border-color:#16a34a; border-top-color:transparent;" aria-hidden="true"></span>
            Loading promo posters & announcements...
          </div>
        </td>
      </tr>
    `;

    const { data, error } = await supabase
      .from('announcements')
      .select(`
        id,
        title,
        content,
        visibility,
        image_url,
        created_at,
        created_by_staff_id,
        staff:created_by_staff_id (
          id,
          first_name,
          last_name,
          role
        )
      `)
      .order('created_at', { ascending: false });

    if (error) throw error;

    _promoPosters = data || [];
    updateBadgeCounts();
    renderPromoPostersTable();
  } catch (err) {
    console.error('[PromoPosters] Error loading promo posters:', err);
    tbody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:24px; color:#ef4444;">
          Failed to load promo posters: ${err.message || err}
        </td>
      </tr>
    `;
  }
}

/**
 * Update tab and chip counts.
 */
function updateBadgeCounts() {
  const hubCount = document.getElementById('hub-count-announcements');
  const countAll = document.getElementById('ann-count-all');
  const countCitizens = document.getElementById('ann-count-citizens');
  const countPublic = document.getElementById('ann-count-public');

  const total = _promoPosters.length;
  const citizenCount = _promoPosters.filter(p => (p.visibility || '').toLowerCase() === 'citizen').length;
  const publicCount = _promoPosters.filter(p => (p.visibility || '').toLowerCase() === 'all' || (p.visibility || '').toLowerCase() === 'all_users').length;

  if (hubCount) hubCount.textContent = total;
  if (countAll) countAll.textContent = total;
  if (countCitizens) countCitizens.textContent = citizenCount;
  if (countPublic) countPublic.textContent = publicCount;
}

/**
 * Render the filtered and searched posters in the table.
 */
function renderPromoPostersTable() {
  const tbody = document.getElementById('announcements-tbody');
  if (!tbody) return;

  const canManage = isAuthorizedToManagePromo();

  let filtered = _promoPosters;

  // Filter chip
  if (_activeFilter === 'citizen') {
    filtered = filtered.filter(p => (p.visibility || '').toLowerCase() === 'citizen');
  } else if (_activeFilter === 'all_users') {
    filtered = filtered.filter(p => ['all', 'all_users'].includes((p.visibility || '').toLowerCase()));
  }

  // Search
  if (_searchQuery) {
    filtered = filtered.filter(p =>
      (p.title || '').toLowerCase().includes(_searchQuery) ||
      (p.content || '').toLowerCase().includes(_searchQuery)
    );
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="6" style="text-align:center; padding:36px 16px; color:#64748b;">
          <div style="font-size:14px; font-weight:700; color:#334155; margin-bottom:4px;">No promo posters found</div>
          <div style="font-size:12px;">${_searchQuery ? 'Try adjusting your search query or filter.' : 'Click "+ New Promo Poster" above to create one.'}</div>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(item => {
    const title = escapeHtml(item.title || 'Untitled');
    const content = escapeHtml(item.content || '');
    const imageUrl = item.image_url;
    const dateFormatted = item.created_at ? new Date(item.created_at).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    }) : '—';

    // Author
    let authorName = 'Clinic Staff';
    let authorRole = 'Staff';
    if (item.staff) {
      authorName = `${item.staff.first_name || ''} ${item.staff.last_name || ''}`.trim() || 'Staff';
      authorRole = (item.staff.role || 'Staff').toUpperCase();
    }

    // Audience badge
    const isCitizenOnly = (item.visibility || '').toLowerCase() === 'citizen';
    const audienceBadge = isCitizenOnly
      ? '<span style="display:inline-block; background:#dcfce7; color:#166534; font-size:11px; font-weight:800; padding:3px 8px; border-radius:6px;">CITIZENS (MOBILE)</span>'
      : '<span style="display:inline-block; background:#e0f2fe; color:#0369a1; font-size:11px; font-weight:800; padding:3px 8px; border-radius:6px;">ALL USERS</span>';

    // Thumbnail column
    const thumbnailHtml = imageUrl
      ? `<img src="${escapeHtml(imageUrl)}" alt="poster" style="width:48px; height:48px; object-fit:cover; border-radius:8px; border:1px solid #e2e8f0; display:block; margin:0 auto; cursor:pointer;" onclick="window.open('${escapeHtml(imageUrl)}', '_blank')" title="Click to view full image" />`
      : `<div style="width:44px; height:44px; border-radius:8px; background:#f1f5f9; display:flex; align-items:center; justify-content:center; margin:0 auto; color:#94a3b8;"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg></div>`;

    return `
      <tr class="table-data-row" style="border-bottom:1px solid #f1f5f9;">
        <td style="text-align:center; padding:10px 8px;">
          ${thumbnailHtml}
        </td>
        <td style="padding:12px 14px;">
          <div style="font-weight:800; font-size:13.5px; color:#0f172a; margin-bottom:3px;">${title}</div>
          <div style="font-size:11.5px; color:#64748b; line-height:1.35; max-width:460px; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden;">${content}</div>
        </td>
        <td style="text-align:center; padding:12px 8px;">
          ${audienceBadge}
        </td>
        <td style="text-align:center; padding:12px 8px;">
          <div style="font-size:12px; font-weight:700; color:#334155;">${escapeHtml(authorName)}</div>
          <div style="font-size:10px; color:#64748b; font-weight:600;">${escapeHtml(authorRole)}</div>
        </td>
        <td style="text-align:center; padding:12px 8px; font-size:11.5px; color:#64748b;">
          ${dateFormatted}
        </td>
        <td style="text-align:center; padding:12px 8px;">
          ${canManage ? `
            <button type="button" class="icon-btn promo-delete-btn" data-id="${item.id}" title="Delete Promo Poster" style="color:#ef4444; background:#fef2f2; border:1px solid #fecaca; border-radius:6px; width:30px; height:30px; cursor:pointer;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          ` : '—'}
        </td>
      </tr>
    `;
  }).join('');

  // Bind delete buttons
  if (canManage) {
    tbody.querySelectorAll('.promo-delete-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const id = btn.getAttribute('data-id');
        if (id) deletePromoPoster(id);
      });
    });
  }
}

/**
 * Delete a promo poster with user confirmation.
 */
async function deletePromoPoster(id) {
  if (!confirm('Are you sure you want to delete this promo poster? It will immediately be removed from the patient mobile app.')) {
    return;
  }

  try {
    const { error } = await supabase
      .from('announcements')
      .delete()
      .eq('id', id);

    if (error) throw error;

    showToast('Promo poster deleted successfully.', 'info');
    await loadPromoPosters();
  } catch (err) {
    console.error('[PromoPosters] Failed to delete promo poster:', err);
    showToast(`Failed to delete promo poster: ${err.message || err}`, 'error');
  }
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
