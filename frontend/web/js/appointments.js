// Queue Management Module (drag-and-drop board)

const appointments = (() => {
  const COMPLETED_PURGE_GRACE_SECONDS = 10;

  let supabaseClientPromise = null;
  let pendingUndo = null;
  let currentQueueTickets = [];

  const init = async () => {
    const queueSection = document.getElementById('queue-section');
    if (!queueSection) return;

    setupEventListeners();
    setupDragDropHandlers();
    setupTicketModalHandlers();
    await loadQueueTickets();
  };

  const getSupabaseClient = async () => {
    if (!supabaseClientPromise) {
      supabaseClientPromise = import('./supabase-config.js')
        .then((module) => module.supabase)
        .catch((error) => {
          supabaseClientPromise = null;
          throw error;
        });
    }
    return supabaseClientPromise;
  };

  const getTodayDateText = () => {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, '0');
    const d = String(now.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  };

  const setupEventListeners = () => {
    const refreshBtn = document.getElementById('queue-refresh-btn');

    refreshBtn?.addEventListener('click', async () => {
      refreshBtn.disabled = true;
      refreshBtn.textContent = 'Loading...';
      try {
        await loadQueueTickets();
      } finally {
        refreshBtn.disabled = false;
        refreshBtn.textContent = 'Refresh';
      }
    });

    document.addEventListener('click', async (event) => {
      const infoBtn = event.target.closest('[data-action="ticket-info"]');
      if (infoBtn) {
        const ticketId = Number(infoBtn.getAttribute('data-ticket-id'));
        const ticket = currentQueueTickets.find((item) => Number(item.id) === ticketId);
        if (ticket) openTicketDetailModal(ticket);
        return;
      }

      const completeBtn = event.target.closest('[data-action="ticket-complete"]');
      if (completeBtn) {
        const ticketId = Number(completeBtn.getAttribute('data-ticket-id'));
        if (Number.isFinite(ticketId)) {
          await markServingCompleted(ticketId);
        }
      }
    });
  };

  const setupDragDropHandlers = () => {
    document.querySelectorAll('.queue-card-list[data-lane]').forEach((laneElement) => {
      laneElement.addEventListener('dragover', (event) => {
        event.preventDefault();
        laneElement.classList.add('is-drop-target');
      });

      laneElement.addEventListener('dragleave', () => {
        laneElement.classList.remove('is-drop-target');
      });

      laneElement.addEventListener('drop', async (event) => {
        event.preventDefault();
        laneElement.classList.remove('is-drop-target');

        const ticketId = Number(event.dataTransfer?.getData('text/plain') || 0);
        const targetLane = String(laneElement.dataset.lane || '').trim();
        if (!ticketId || !targetLane) return;
        await moveTicketToLane(ticketId, targetLane);
      });
    });
  };

  const setupTicketModalHandlers = () => {
    const modal = document.getElementById('queue-ticket-detail-modal');
    const closeBtn = document.getElementById('queue-ticket-detail-close');

    closeBtn?.addEventListener('click', closeTicketDetailModal);
    modal?.addEventListener('click', (event) => {
      if (event.target === modal) closeTicketDetailModal();
    });
  };

  const loadQueueTickets = async () => {
    try {
      await purgeCompletedTickets();

      const today = getTodayDateText();
      const supabase = await getSupabaseClient();
      const response = await supabase
        .from('queue_tickets')
        .select(`
          id,
          queue_date,
          service_key,
          reason,
          symptoms,
          queue_number,
          ticket_code,
          service_label,
          citizen_type,
          status,
          created_at,
          served_at,
          completed_at,
          citizen:citizens(id, firstname, surname, email)
        `)
        .eq('queue_date', today)
        .order('queue_number', { ascending: true });

      if (response.error) {
        console.error('Error loading queue tickets:', response.error);
        showToast('Failed to load queue: ' + response.error.message, 'error');
        return;
      }

      currentQueueTickets = response.data || [];
      renderQueue();
      document.dispatchEvent(new CustomEvent('ukonek:queue-updated'));
    } catch (err) {
      console.error('Error loading queue tickets:', err);
      showToast('Failed to load queue', 'error');
    }
  };

  const purgeCompletedTickets = async () => {
    const today = getTodayDateText();
    const supabase = await getSupabaseClient();
    const response = await supabase.rpc('purge_completed_queue_tickets', {
      p_queue_date: today,
      p_service_key: null,
      p_grace_seconds: COMPLETED_PURGE_GRACE_SECONDS
    });

    if (response.error) {
      console.warn('Unable to auto-remove completed queue tickets:', response.error.message);
    }
  };

  const getScopedQueueTickets = () => {
    return currentQueueTickets;
  };

  const categorizeTickets = (tickets) => {
    const normalizedStatus = (ticket) => String(ticket?.status || '').trim().toLowerCase();

    return {
      waiting: tickets.filter((ticket) => normalizedStatus(ticket) === 'waiting'),
      onCall: tickets.filter((ticket) => normalizedStatus(ticket) === 'on_call'),
      serving: tickets.filter((ticket) => normalizedStatus(ticket) === 'serving')
    };
  };

  const renderQueue = () => {
    const scoped = getScopedQueueTickets();
    const buckets = categorizeTickets(scoped);

    renderLaneCards('queue-waiting-list', buckets.waiting, 'No waiting tickets.');
    renderLaneCards('queue-oncall-list', buckets.onCall, 'No on-call tickets.');
    renderLaneCards('queue-serving-list', buckets.serving, 'No one is currently serving.', true);
    updateLaneCount('queue-waiting-count', buckets.waiting.length);
    updateLaneCount('queue-oncall-count', buckets.onCall.length);
    updateLaneCount('queue-serving-count', buckets.serving.length);
    updateCurrentServingBadge(buckets.serving);
    updateSummaryBadge(buckets.waiting.length, buckets.onCall.length);
  };

  const renderLaneCards = (containerId, tickets, emptyText, allowComplete = false) => {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (tickets.length === 0) {
      container.innerHTML = `<div class="queue-ticket-empty">${emptyText}</div>`;
      return;
    }

    container.innerHTML = tickets
      .sort((a, b) => Number(a?.queue_number || 0) - Number(b?.queue_number || 0))
      .map((ticket) => {
        const queueNumber = Number(ticket.queue_number || 0);
        const ticketCode = String(ticket.ticket_code || '').trim() || 'N/A';
        const citizenName = formatCitizenName(ticket.citizen);
        const serviceLabel = String(ticket.service_label || '').trim() || 'General Consultation';
        const citizenType = formatCitizenType(ticket.citizen_type);
        return `
          <div class="queue-ticket-card" draggable="true" data-ticket-id="${ticket.id}">
            <div class="queue-ticket-top">
              <span class="queue-ticket-queue">#${queueNumber > 0 ? String(queueNumber).padStart(3, '0') : '-'}</span>
              <span class="queue-ticket-code">${ticketCode}</span>
            </div>
            <div class="queue-ticket-name">${citizenName}</div>
            <div class="queue-ticket-meta">${serviceLabel} • ${citizenType}</div>
            <div class="queue-ticket-actions">
              <button class="queue-ticket-btn" type="button" data-action="ticket-info" data-ticket-id="${ticket.id}">Info</button>
              ${allowComplete ? `<button class="queue-ticket-btn" type="button" data-action="ticket-complete" data-ticket-id="${ticket.id}">Complete</button>` : ''}
            </div>
          </div>
        `;
      })
      .join('');

    container.querySelectorAll('.queue-ticket-card').forEach((card) => {
      card.addEventListener('dragstart', (event) => {
        const ticketId = String(card.getAttribute('data-ticket-id') || '');
        event.dataTransfer?.setData('text/plain', ticketId);
      });

      card.addEventListener('click', (event) => {
        const actionBtn = event.target.closest('[data-action]');
        if (actionBtn) return;
        const ticketId = Number(card.getAttribute('data-ticket-id'));
        const ticket = currentQueueTickets.find((item) => Number(item.id) === ticketId);
        if (ticket) openTicketDetailModal(ticket);
      });
    });
  };

  const updateLaneCount = (id, count) => {
    const element = document.getElementById(id);
    if (element) element.textContent = String(count);
  };

  const updateCurrentServingBadge = (servingTickets) => {
    const badge = document.getElementById('queue-current-serving-badge');
    if (!badge) return;

    const sorted = [...servingTickets].sort((a, b) => Number(a?.queue_number || 0) - Number(b?.queue_number || 0));
    const current = sorted[0];
    const queueNumber = Number(current?.queue_number || 0);
    const label = String(current?.service_label || '').trim();

    if (queueNumber > 0) {
      badge.textContent = `Current serving: #${String(queueNumber).padStart(3, '0')}${label ? ` (${label})` : ''}`;
      badge.style.background = '#e0f2fe';
      badge.style.color = '#0369a1';
    } else {
      badge.textContent = 'Current serving: none';
      badge.style.background = '#f1f5f9';
      badge.style.color = '#475569';
    }
  };

  const updateSummaryBadge = (waitingCount, onCallCount) => {
    const badge = document.getElementById('queue-summary-badge');
    if (!badge) return;
    badge.textContent = `Waiting: ${waitingCount} | On Call: ${onCallCount}`;
  };

  const moveTicketToLane = async (ticketId, targetLane) => {
    const ticket = currentQueueTickets.find((item) => Number(item.id) === Number(ticketId));
    if (!ticket) return;

    if (targetLane === 'waiting') {
      await moveTicketToWaiting(ticket);
      return;
    }

    if (targetLane === 'on_call') {
      await moveTicketToOnCall(ticket);
      return;
    }

    if (targetLane === 'serving') {
      await setCurrentServing(ticket.id, { confirm: false });
    }
  };

  const moveTicketToWaiting = async (ticket) => {
    const status = String(ticket?.status || '').trim().toLowerCase();
    if (status === 'serving' || status === 'on_call') {
      const updated = await updateTicketStatus(ticket.id, 'waiting');
      if (!updated) return;
      showToast('Ticket moved to Waiting.', 'success');
      await loadQueueTickets();
      return;
    }
    renderQueue();
  };

  const moveTicketToOnCall = async (ticket) => {
    const status = String(ticket?.status || '').trim().toLowerCase();
    if (status === 'serving') {
      const updated = await updateTicketStatus(ticket.id, 'on_call');
      if (!updated) return;
    } else if (status === 'waiting') {
      const updated = await updateTicketStatus(ticket.id, 'on_call');
      if (!updated) return;
    } else if (status !== 'on_call') {
      showToast('Only waiting/serving tickets can be moved to On Call.', 'warning');
      return;
    }

    showToast('Ticket moved to On Call.', 'success');
    await loadQueueTickets();
  };

  const updateTicketStatus = async (ticketId, status) => {
    const supabase = await getSupabaseClient();
    const payload = { status };
    if (status === 'completed') payload.completed_at = new Date().toISOString();
    if (status === 'waiting') payload.completed_at = null;

    const response = await supabase
      .from('queue_tickets')
      .update(payload)
      .eq('id', Number(ticketId));

    if (response.error) {
      showToast('Failed to update queue ticket: ' + response.error.message, 'error');
      return false;
    }
    return true;
  };

  const setCurrentServing = async (queueTicketId, options = {}) => {
    const silent = options?.silent === true;
    const requireConfirm = options?.confirm !== false;

    if (requireConfirm && !silent) {
      const proceed = await confirmAction({
        title: 'Set Current Serving',
        message: 'Set this citizen as the current serving ticket?',
        confirmText: 'Set Serving',
        cancelText: 'Cancel'
      });
      if (!proceed) return false;
    }

    const supabase = await getSupabaseClient();
    const response = await supabase.rpc('set_queue_current_serving', {
      p_queue_ticket_id: Number(queueTicketId)
    });

    if (response.error) {
      if (!silent) showToast('Failed to set current serving: ' + response.error.message, 'error');
      return false;
    }

    const result = response.data || {};
    if (result.ok === false) {
      if (!silent) showToast(result.error || 'Unable to set current serving.', 'warning');
      return false;
    }

    await loadQueueTickets();
    if (!silent) {
      const current = Number(result.current_queue_number || 0);
      if (current > 0) showToast(`Now serving #${String(current).padStart(3, '0')}`, 'success');
    }
    return true;
  };

  const markServingCompleted = async (queueTicketId) => {
    const proceed = await confirmAction({
      title: 'Complete Ticket',
      message: 'Mark this serving ticket as completed?',
      confirmText: 'Complete',
      cancelText: 'Cancel'
    });
    if (!proceed) return;

    const updated = await updateTicketStatus(queueTicketId, 'completed');
    if (!updated) return;

    await loadQueueTickets();
    registerUndoWindow(Number(queueTicketId));
    showToast(`Ticket completed. Undo available for ${COMPLETED_PURGE_GRACE_SECONDS}s.`, 'success');
  };

  const registerUndoWindow = (queueTicketId) => {
    if (pendingUndo?.timer) clearTimeout(pendingUndo.timer);

    const timer = setTimeout(async () => {
      pendingUndo = null;
      removeUndoBanner();
      await loadQueueTickets();
    }, COMPLETED_PURGE_GRACE_SECONDS * 1000);

    pendingUndo = { queueTicketId, timer };
    showUndoBanner(queueTicketId);
  };

  const showUndoBanner = (queueTicketId) => {
    removeUndoBanner();

    const banner = document.createElement('div');
    banner.id = 'queue-undo-banner';
    banner.style.position = 'fixed';
    banner.style.right = '20px';
    banner.style.bottom = '20px';
    banner.style.zIndex = '1600';
    banner.style.background = '#0f172a';
    banner.style.color = '#f8fafc';
    banner.style.padding = '10px 12px';
    banner.style.borderRadius = '10px';
    banner.style.display = 'flex';
    banner.style.alignItems = 'center';
    banner.style.gap = '10px';
    banner.style.boxShadow = '0 10px 24px rgba(15, 23, 42, 0.25)';
    banner.innerHTML = `
      <span>Completed ticket removed from queue.</span>
      <button id="queue-undo-btn" type="button" style="background:#e2e8f0;color:#0f172a;border:none;border-radius:8px;padding:6px 10px;cursor:pointer;font-weight:700;">Undo</button>
    `;

    document.body.appendChild(banner);

    const undoBtn = document.getElementById('queue-undo-btn');
    undoBtn?.addEventListener('click', async () => {
      await undoCompletedTicket(queueTicketId);
    });
  };

  const removeUndoBanner = () => {
    const existing = document.getElementById('queue-undo-banner');
    existing?.remove();
  };

  const undoCompletedTicket = async (queueTicketId) => {
    const updated = await updateTicketStatus(queueTicketId, 'waiting');
    if (!updated) return;

    if (pendingUndo?.timer) clearTimeout(pendingUndo.timer);
    pendingUndo = null;
    removeUndoBanner();
    await loadQueueTickets();
    showToast('Ticket restored to waiting queue.', 'success');
  };

  const openTicketDetailModal = (ticket) => {
    const modal = document.getElementById('queue-ticket-detail-modal');
    const body = document.getElementById('queue-ticket-detail-body');
    if (!modal || !body) return;

    const queueNumber = Number(ticket?.queue_number || 0);
    const citizenName = formatCitizenName(ticket?.citizen);
    const serviceLabel = String(ticket?.service_label || '').trim() || 'General Consultation';
    const ticketCode = String(ticket?.ticket_code || '').trim() || 'N/A';
    const citizenType = formatCitizenType(ticket?.citizen_type);
    const status = String(ticket?.status || '').trim() || 'N/A';
    const createdAt = formatDateTime(ticket?.created_at);

    body.innerHTML = `
      <div class="modal-group"><label class="modal-label">Citizen</label><p class="modal-text">${citizenName}</p></div>
      <div class="modal-group"><label class="modal-label">Queue Number</label><p class="modal-text">${queueNumber > 0 ? `#${String(queueNumber).padStart(3, '0')}` : '-'}</p></div>
      <div class="modal-group"><label class="modal-label">Ticket Code</label><p class="modal-text">${ticketCode}</p></div>
      <div class="modal-group"><label class="modal-label">Service</label><p class="modal-text">${serviceLabel}</p></div>
      <div class="modal-group"><label class="modal-label">Citizen Type</label><p class="modal-text">${citizenType}</p></div>
      <div class="modal-group"><label class="modal-label">Status</label><p class="modal-text">${status}</p></div>
      <div class="modal-group"><label class="modal-label">Joined</label><p class="modal-text">${createdAt}</p></div>
    `;

    modal.classList.remove('hidden');
  };

  const closeTicketDetailModal = () => {
    const modal = document.getElementById('queue-ticket-detail-modal');
    if (modal) modal.classList.add('hidden');
  };

  const confirmAction = async ({
    title = 'Confirm Action',
    message = 'Are you sure?',
    confirmText = 'Confirm',
    cancelText = 'Cancel'
  } = {}) => {
    if (typeof openDialogModal === 'function') {
      const result = await openDialogModal({ title, message, confirmText, cancelText });
      return Boolean(result?.confirmed);
    }
    return false;
  };

  const formatDateTime = (value) => {
    const text = String(value || '').trim();
    if (!text) return 'N/A';
    const date = new Date(text);
    if (Number.isNaN(date.getTime())) return text;
    return date.toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    });
  };

  const formatCitizenName = (citizen) => {
    const first = String(citizen?.firstname || '').trim();
    const last = String(citizen?.surname || '').trim();
    const email = String(citizen?.email || '').trim();
    const fullName = `${first} ${last}`.trim();
    if (fullName) return fullName;
    if (email) return email;
    return 'Unknown Citizen';
  };

  const formatCitizenType = (citizenType) => {
    const normalized = String(citizenType || '').trim().toLowerCase();
    if (normalized === 'pwd') return 'PWD';
    if (normalized === 'pregnant') return 'Pregnant';
    if (normalized === 'regular') return 'Regular';
    return normalized || 'Regular';
  };

  return {
    init,
    loadQueueTickets,
    setCurrentServing,
    markServingCompleted
  };
})();

document.addEventListener('DOMContentLoaded', () => {
  appointments.init();
});
