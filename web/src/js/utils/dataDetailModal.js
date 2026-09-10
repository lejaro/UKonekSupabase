/**
 * Data Detail Modal Drawer Controller
 * Populates and controls the slide-over / modal details drawer (#data-detail-modal).
 * Exposes window.openDataDetail for legacy / sibling script compatibility.
 */

export function sanitizeText(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function getDetailInitials(name) {
  if (!name) return 'UK';
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function formatDetailValue(value) {
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

export function openDataDetail(config = {}) {
  const dataDetailModal = document.getElementById('data-detail-modal');
  if (!dataDetailModal) return;

  const dataDetailTitle = document.getElementById('data-detail-title');
  const dataDetailSubtitle = document.getElementById('data-detail-subtitle');
  const dataDetailCards = document.getElementById('data-detail-cards');
  const dataDetailTag = document.getElementById('data-detail-tag');
  const dataDetailAvatar = document.getElementById('data-detail-avatar');
  const dataDetailStatusPill = document.getElementById('data-detail-status-pill');
  const dataDetailActions = document.getElementById('data-detail-actions');

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
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #16a34a 0%, #15803d 100%)';
      dataDetailAvatar.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3v6a6 6 0 0 0 12 0V3"/><path d="M9 17v2a3 3 0 0 0 6 0v-2"/><circle cx="15" cy="17" r="1.5"/></svg>';
    } else if (titleLower.includes('vital') || tagLower.includes('vital')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #e11d48 0%, #be123c 100%)';
      dataDetailAvatar.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>';
    } else if (tagLower.includes('staff') || tagLower.includes('admin') || tagLower.includes('doctor')) {
      dataDetailAvatar.style.background = 'linear-gradient(135deg, #16a34a 0%, #15803d 100%)';
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

export function closeDataDetail() {
  const dataDetailModal = document.getElementById('data-detail-modal');
  if (dataDetailModal) dataDetailModal.classList.add('hidden');
}

export function attachDetailRow(tr, configProducer) {
  if (!tr) return;
  tr.style.cursor = 'pointer';
  tr.addEventListener('click', (e) => {
    // Avoid triggering when clicking buttons or inputs inside row
    if (e.target.closest('button, a, input, select, textarea')) return;
    const config = typeof configProducer === 'function' ? configProducer() : configProducer;
    if (config) openDataDetail(config);
  });
}

// Wire modal close buttons once DOM is available
if (typeof document !== 'undefined') {
  const closeBtn = document.getElementById('data-detail-close-btn');
  const dismissBtn = document.getElementById('data-detail-dismiss');
  const modal = document.getElementById('data-detail-modal');

  if (closeBtn) closeBtn.addEventListener('click', closeDataDetail);
  if (dismissBtn) dismissBtn.addEventListener('click', closeDataDetail);
  if (modal) {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeDataDetail();
    });
  }
}

if (typeof window !== 'undefined') {
  window.openDataDetail = openDataDetail;
}
