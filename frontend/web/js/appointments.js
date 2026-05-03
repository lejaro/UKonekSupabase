// Queue Management Module

const appointments = (() => {
  const COMPLETED_PURGE_GRACE_SECONDS = 10;

  let supabaseClientPromise = null;
  let pendingUndo = null;
  let currentQueueTickets = [];
  let currentlyViewedTicketId = null;
  // Map of ticketId -> true for tickets that already have a vital assessment
  const assessedTicketIds = new Set();

  const init = async () => {
    const queueSection = document.getElementById('queue-section');
    if (!queueSection) return;

    setupEventListeners();
    setupTicketModalHandlers();
    setupLaneDropZones();
    await loadQueueTickets();
    setupRealtimeListener();
  };

  const setupLaneDropZones = () => {
    const lanes = ['queue-waiting-list', 'queue-oncall-list', 'queue-serving-list'];
    lanes.forEach(id => {
      const container = document.getElementById(id);
      if (!container) return;

      container.addEventListener('dragover', (e) => {
        e.preventDefault();
        container.classList.add('drag-over');
      });

      container.addEventListener('dragleave', () => {
        container.classList.remove('drag-over');
      });

      container.addEventListener('drop', async (e) => {
        e.preventDefault();
        container.classList.remove('drag-over');
        const ticketId = e.dataTransfer.getData('text/plain');
        if (!ticketId) return;

        const targetLane = container.getAttribute('data-lane');
        if (targetLane) {
          await moveTicketToLane(ticketId, targetLane);
        }
      });
    });
  };

  const setupRealtimeListener = async () => {
    try {
      const supabase = await getSupabaseClient();
      supabase
        .channel('public:queue_tickets_changes')
        .on('postgres_changes', { 
          event: '*', 
          schema: 'public', 
          table: 'queue_tickets' 
        }, (payload) => {
          console.log('Queue updated via realtime:', payload);
          loadQueueTickets();
        })
        .subscribe();
    } catch (err) {
      console.error('Failed to setup realtime listener:', err);
    }
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

    const tvViewBtn = document.getElementById('open-tv-view-btn');
    tvViewBtn?.addEventListener('click', () => {
      window.open('tv-view.html', '_blank');
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
        return;
      }

      const moveBtn = event.target.closest('[data-action="ticket-move"]');
      if (moveBtn) {
        const ticketId = Number(moveBtn.getAttribute('data-ticket-id'));
        const targetLane = String(moveBtn.getAttribute('data-target-lane') || '').trim();
        if (Number.isFinite(ticketId) && targetLane) {
          await moveTicketToLane(ticketId, targetLane);
        }
        return;
      }

      const vitalBtn = event.target.closest('[data-action="ticket-vital"]');
      if (vitalBtn) {
        const ticketId = Number(vitalBtn.getAttribute('data-ticket-id'));
        const ticket = currentQueueTickets.find((item) => Number(item.id) === ticketId);
        if (ticket) await openVitalAssessmentModal(ticket);
        return;
      }
    });
  };

  const setupTicketModalHandlers = () => {
    const modal = document.getElementById('queue-ticket-detail-modal');
    const closeBtn = document.getElementById('queue-ticket-detail-close');

    closeBtn?.addEventListener('click', closeTicketDetailModal);
    modal?.addEventListener('click', (event) => {
      if (event.target === modal) closeTicketDetailModal();
    });

    const deleteBtn = document.getElementById('queue-ticket-delete-btn');
    deleteBtn?.addEventListener('click', async () => {
      if (Number.isFinite(currentlyViewedTicketId)) {
        await deleteQueueTicket(currentlyViewedTicketId);
      }
    });

    setupVitalAssessmentModal();
  };

  const loadQueueTickets = async () => {
    try {
      await purgeCompletedTickets();

      const today = getTodayDateText();
      const supabase = await getSupabaseClient();
      
      const queryStr = `
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
        citizen:citizens(id, firstname, surname, email, date_of_birth, sex)
      `;

      let { data, error } = await supabase
        .from('queue_tickets')
        .select(queryStr)
        .eq('queue_date', today)
        .not('status', 'in', '("cancelled","completed")')
        .order('queue_number', { ascending: true });

      if (!error && (!data || data.length === 0)) {
        const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
        console.log('No tickets for today, attempting fallback to recent active tickets (last 24h)...');
        const fb = await supabase
          .from('queue_tickets')
          .select(queryStr)
          .not('status', 'in', '("cancelled","completed")')
          .gt('created_at', twentyFourHoursAgo)
          .order('created_at', { ascending: false })
          .limit(100);
        
        if (!fb.error && fb.data && fb.data.length > 0) {
          data = fb.data;
        }
      }

      if (error) {
        console.error('Error loading queue tickets:', error);
        showToast('Failed to load queue: ' + error.message, 'error');
        return;
      }

      currentQueueTickets = data || [];
      await refreshAssessedTicketIds(supabase);
      renderQueue();
      document.dispatchEvent(new CustomEvent('ukonek:queue-updated'));
    } catch (err) {
      console.error('Error loading queue tickets:', err);
      showToast('Failed to load queue', 'error');
    }
  };

  const refreshAssessedTicketIds = async (supabase) => {
    try {
      const onCallIds = currentQueueTickets
        .filter((t) => String(t?.status || '').trim().toLowerCase() === 'on_call')
        .map((t) => Number(t.id));

      assessedTicketIds.clear();
      if (onCallIds.length === 0) return;

      const { data, error } = await supabase
        .from('vital_signs')
        .select('queue_ticket_id')
        .in('queue_ticket_id', onCallIds);

      if (!error && Array.isArray(data)) {
        data.forEach((row) => {
          if (row.queue_ticket_id) assessedTicketIds.add(Number(row.queue_ticket_id));
        });
      }
    } catch (_) {
      // Non-critical — badge will just show "Start Vitals" on failure
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

    renderLaneCards('queue-waiting-list', buckets.waiting, 'No waiting tickets.', 'waiting');
    renderLaneCards('queue-oncall-list', buckets.onCall, 'No on-call tickets.', 'on_call');
    renderLaneCards('queue-serving-list', buckets.serving, 'No one is currently serving.', 'serving', true);
    updateLaneCount('queue-waiting-count', buckets.waiting.length);
    updateLaneCount('queue-oncall-count', buckets.onCall.length);
    updateLaneCount('queue-serving-count', buckets.serving.length);
    updateCurrentServingBadge(buckets.serving);
    updateSummaryBadge(buckets.waiting.length, buckets.onCall.length);
  };

  const getLaneActionButtons = (lane, ticketId) => {
    if (lane === 'waiting') {
      return `
        <button class="queue-ticket-btn" type="button" data-action="ticket-move" data-target-lane="on_call" data-ticket-id="${ticketId}">On Call</button>
        <button class="queue-ticket-btn" type="button" data-action="ticket-move" data-target-lane="serving" data-ticket-id="${ticketId}">Serve Now</button>
      `;
    }

    if (lane === 'on_call') {
      const assessed = assessedTicketIds.has(Number(ticketId));
      const vitalBadgeOrBtn = assessed
        ? `<span class="queue-vital-done-badge" title="Vital assessment recorded">&#10003; Vitals Done</span>`
        : `<button class="queue-ticket-btn btn-vital" type="button" data-action="ticket-vital" data-ticket-id="${ticketId}">&#9829; Start Vitals</button>`;
      return `
        ${vitalBadgeOrBtn}
        <button class="queue-ticket-btn" type="button" data-action="ticket-move" data-target-lane="waiting" data-ticket-id="${ticketId}">Back</button>
        <button class="queue-ticket-btn" type="button" data-action="ticket-move" data-target-lane="serving" data-ticket-id="${ticketId}">Serve Now</button>
      `;
    }

    if (lane === 'serving') {
      return `
        <button class="queue-ticket-btn" type="button" data-action="ticket-move" data-target-lane="on_call" data-ticket-id="${ticketId}">Back to On Call</button>
      `;
    }

    return '';
  };

  const renderLaneCards = (containerId, tickets, emptyText, lane, allowComplete = false) => {
    const container = document.getElementById(containerId);
    if (!container) return;

    const sorted = tickets.slice().sort((a, b) => Number(a?.queue_number || 0) - Number(b?.queue_number || 0));

    const fragment = document.createDocumentFragment();

    if (sorted.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'queue-ticket-empty';
      empty.textContent = emptyText;
      fragment.appendChild(empty);
    } else {
      sorted.forEach((ticket) => {
        const queueNumber = Number(ticket.queue_number || 0);
        const ticketCode = String(ticket.ticket_code || '').trim() || 'N/A';
        const citizenName = formatCitizenName(ticket.citizen);
        const serviceLabel = String(ticket.service_label || '').trim() || 'General Consultation';
        const citizenType = formatCitizenType(ticket.citizen_type);
        const laneActions = getLaneActionButtons(lane, ticket.id);

        const card = document.createElement('div');
        card.className = 'queue-ticket-card';
        card.draggable = true;
        card.dataset.ticketId = ticket.id;
        card.dataset.currentLane = lane;
        card.innerHTML = `
          <div class="queue-ticket-top">
            <span class="queue-ticket-queue">#${queueNumber > 0 ? String(queueNumber).padStart(3, '0') : '-'}</span>
            <span class="queue-ticket-code">${ticketCode}</span>
          </div>
          <div class="queue-ticket-name">${citizenName}</div>
          <div class="queue-ticket-meta">${serviceLabel} • ${citizenType}</div>
          <div class="queue-ticket-actions">
            ${laneActions}
            <button class="queue-ticket-btn" type="button" data-action="ticket-info" data-ticket-id="${ticket.id}">Info</button>
            ${allowComplete ? `<button class="queue-ticket-btn" type="button" data-action="ticket-complete" data-ticket-id="${ticket.id}">Complete</button>` : ''}
          </div>
        `;

        card.addEventListener('dragstart', (e) => {
          card.classList.add('dragging');
          e.dataTransfer.setData('text/plain', card.getAttribute('data-ticket-id'));
        });
        card.addEventListener('dragend', () => {
          card.classList.remove('dragging');
        });
        card.addEventListener('click', (event) => {
          const actionBtn = event.target.closest('[data-action]');
          if (actionBtn) return;
          const ticketId = Number(card.getAttribute('data-ticket-id'));
          const t = currentQueueTickets.find((item) => Number(item.id) === ticketId);
          if (t) openTicketDetailModal(t);
        });

        fragment.appendChild(card);
      });
    }

    container.replaceChildren(fragment);
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
    // Auto-open vital assessment modal for this ticket
    const updatedTicket = currentQueueTickets.find((t) => Number(t.id) === Number(ticket.id));
    if (updatedTicket) await openVitalAssessmentModal(updatedTicket);
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
    currentlyViewedTicketId = Number(ticket?.id) || null;
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
    currentlyViewedTicketId = null;
    const modal = document.getElementById('queue-ticket-detail-modal');
    if (modal) modal.classList.add('hidden');
  };

  const deleteQueueTicket = async (ticketId) => {
    const proceed = await confirmAction({
      title: 'Delete Queue Ticket',
      message: 'Are you sure you want to delete this ticket? This will remove it from the system entirely.',
      confirmText: 'Delete',
      cancelText: 'Cancel'
    });
    if (!proceed) return;

    const supabase = await getSupabaseClient();
    const { error } = await supabase
      .from('queue_tickets')
      .delete()
      .eq('id', Number(ticketId));

    if (error) {
      showToast('Failed to delete ticket: ' + error.message, 'error');
      return;
    }

    showToast('Ticket deleted successfully.', 'success');
    closeTicketDetailModal();
    
    // Immediate UI Update: Remove from local state and re-render
    currentQueueTickets = currentQueueTickets.filter(t => Number(t.id) !== Number(ticketId));
    renderQueue();
    
    // Background sync
    await loadQueueTickets();
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

  // ── Vital Assessment Modal ───────────────────────────────────────────────

  const setupVitalAssessmentModal = () => {
    const modal   = document.getElementById('vital-assessment-modal');
    const form    = document.getElementById('vital-assessment-form');
    const cancelBtn = document.getElementById('va-cancel-btn');

    if (!modal || !form) return;

    const closeModal = () => {
      modal.classList.add('hidden');
      form.reset();
      const errEl = document.getElementById('va-form-error');
      if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
      const badge = document.getElementById('vital-modal-existing-badge');
      if (badge) badge.style.display = 'none';
    };

    cancelBtn?.addEventListener('click', closeModal);
    modal.addEventListener('click', (e) => { if (e.target === modal) closeModal(); });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      await submitVitalAssessment(closeModal);
    });
  };

  const openVitalAssessmentModal = async (ticket) => {
    const modal     = document.getElementById('vital-assessment-modal');
    const form      = document.getElementById('vital-assessment-form');
    const banner    = document.getElementById('vital-modal-patient-banner');
    const nameEl    = document.getElementById('vital-modal-patient-name');
    const metaEl    = document.getElementById('vital-modal-patient-meta');
    const badgeEl   = document.getElementById('vital-modal-existing-badge');
    const ticketHid = document.getElementById('va-queue-ticket-id');
    const citizenHid = document.getElementById('va-citizen-id');
    if (!modal || !form) return;

    // Reset form
    form.reset();
    const errEl = document.getElementById('va-form-error');
    if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

    const citizenId = ticket?.citizen?.id ? Number(ticket.citizen.id) : null;
    const firstName = String(ticket?.citizen?.firstname || '').trim();
    const lastName  = String(ticket?.citizen?.surname  || '').trim();
    const fullName  = `${firstName} ${lastName}`.trim() || 'Unknown Patient';
    const gender    = String(ticket?.citizen?.sex          || '').trim();
    const birthday  = ticket?.citizen?.date_of_birth;
    const service   = String(ticket?.service_label || '').trim() || 'General Consultation';
    const qNum      = String(ticket?.queue_number || '').padStart(3, '0');

    let ageText = '';
    if (birthday) {
      const birthDate = new Date(birthday);
      const ageDiff = Date.now() - birthDate.getTime();
      const age = Math.floor(ageDiff / (1000 * 60 * 60 * 24 * 365.25));
      if (Number.isFinite(age) && age >= 0) ageText = `, ${age} yrs`;
    }

    if (nameEl) nameEl.textContent = fullName;
    if (metaEl) metaEl.textContent = `#${qNum} · ${service}${gender ? ` · ${gender}` : ''}${ageText}`;
    if (banner) banner.style.display = 'block';

    if (ticketHid)  ticketHid.value  = String(ticket.id);
    if (citizenHid) citizenHid.value = citizenId ? String(citizenId) : '';

    // Pre-fill chief complaint from ticket reason/symptoms
    const complaintEl = document.getElementById('va-chief-complaint');
    if (complaintEl) {
      const reason   = String(ticket?.reason   || '').trim();
      const symptoms = String(ticket?.symptoms || '').trim();
      complaintEl.value = symptoms || reason || '';
    }

    // Check for existing assessment and pre-fill if found
    if (badgeEl) badgeEl.style.display = 'none';
    try {
      const supabase = await getSupabaseClient();
      const { data: existing } = await supabase
        .from('vital_signs')
        .select('chief_complaint, blood_pressure, heart_rate, temperature, respiratory_rate, oxygen_saturation, current_medications, notes')
        .eq('queue_ticket_id', Number(ticket.id))
        .maybeSingle();

      if (existing) {
        if (badgeEl) badgeEl.style.display = 'block';
        if (complaintEl && existing.chief_complaint) complaintEl.value = existing.chief_complaint;
        const set = (id, val) => { const el = document.getElementById(id); if (el && val != null) el.value = val; };
        set('va-bp',    existing.blood_pressure);
        set('va-hr',    existing.heart_rate);
        set('va-temp',  existing.temperature);
        set('va-rr',    existing.respiratory_rate);
        set('va-spo2',  existing.oxygen_saturation);
        set('va-meds',  existing.current_medications);
        set('va-notes', existing.notes);
      }
    } catch (_) {
      // Non-critical prefill failure — form stays empty
    }

    modal.classList.remove('hidden');
  };

  const submitVitalAssessment = async (closeModal) => {
    const submitBtn  = document.getElementById('va-submit-btn');
    const errEl      = document.getElementById('va-form-error');
    const ticketId   = Number(document.getElementById('va-queue-ticket-id')?.value  || 0);
    const citizenId  = Number(document.getElementById('va-citizen-id')?.value       || 0);
    const complaint  = String(document.getElementById('va-chief-complaint')?.value  || '').trim();
    const bp         = String(document.getElementById('va-bp')?.value    || '').trim() || null;
    const hr         = Number(document.getElementById('va-hr')?.value)    || null;
    const temp       = parseFloat(document.getElementById('va-temp')?.value) || null;
    const rr         = Number(document.getElementById('va-rr')?.value)   || null;
    const spo2       = Number(document.getElementById('va-spo2')?.value) || null;
    const meds       = String(document.getElementById('va-meds')?.value  || '').trim() || null;
    const notes      = String(document.getElementById('va-notes')?.value || '').trim() || null;

    const showErr = (msg) => {
      if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
    };

    if (!ticketId || !citizenId) { showErr('Unable to identify ticket or patient.'); return; }
    if (!complaint)              { showErr('Chief complaint is required.'); return; }

    if (submitBtn) { submitBtn.disabled = true; submitBtn.querySelector('.btn-label').textContent = 'Saving…'; }
    if (errEl)     { errEl.style.display = 'none'; errEl.textContent = ''; }

    try {
      const supabase = await getSupabaseClient();
      const { data: result, error } = await supabase.rpc('upsert_vital_assessment', {
        p_queue_ticket_id:    ticketId,
        p_citizen_id:         citizenId,
        p_chief_complaint:    complaint,
        p_blood_pressure:     bp,
        p_heart_rate:         Number.isFinite(hr)   ? hr   : null,
        p_temperature:        Number.isFinite(temp) ? temp : null,
        p_respiratory_rate:   Number.isFinite(rr)   ? rr   : null,
        p_oxygen_saturation:  Number.isFinite(spo2) ? spo2 : null,
        p_current_medications: meds,
        p_notes:              notes,
      });

      if (error) throw new Error(error.message);
      if (result?.error) throw new Error(result.error);

      assessedTicketIds.add(ticketId);
      renderQueue();
      closeModal();
      if (typeof showToast === 'function') showToast('Vital assessment saved successfully.', 'success');
    } catch (err) {
      showErr(err.message || 'Failed to save assessment. Please try again.');
    } finally {
      if (submitBtn) { submitBtn.disabled = false; submitBtn.querySelector('.btn-label').textContent = 'Save Assessment'; }
    }
  };

  // ─────────────────────────────────────────────────────────────────────────

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
