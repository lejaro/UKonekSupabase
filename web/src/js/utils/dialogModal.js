/**
 * Generic Dialog & Modal Controller Utility
 * Handles visibility, backdrop click dismiss, escape key listener, and focus management.
 */

let _previousFocusedElement = null;
const _escapeListeners = new Map();

/**
 * Open a modal overlay.
 * @param {HTMLElement|string} modal Target modal element or CSS selector
 * @param {object} [options]
 * @param {string} [options.hiddenClass='hidden'] Class to toggle visibility
 * @param {string} [options.activeClass=''] Optional active class to add
 * @param {boolean} [options.closeOnEscape=true] Whether ESC key closes modal
 * @param {boolean} [options.closeOnBackdrop=true] Whether clicking backdrop closes modal
 * @param {Function} [options.onClose] Callback executed when modal closes
 */
export function openModal(modal, options = {}) {
  const el = typeof modal === 'string' ? document.querySelector(modal) : modal;
  if (!el) return;

  const {
    hiddenClass = 'hidden',
    activeClass = '',
    closeOnEscape = true,
    closeOnBackdrop = true,
    onClose = null,
  } = options;

  _previousFocusedElement = document.activeElement;

  if (hiddenClass) el.classList.remove(hiddenClass);
  if (activeClass) el.classList.add(activeClass);
  el.setAttribute('aria-hidden', 'false');

  // Backdrop dismiss
  if (closeOnBackdrop) {
    const handleBackdrop = (e) => {
      if (e.target === el) {
        closeModal(el, options);
        if (typeof onClose === 'function') onClose();
      }
    };
    el.addEventListener('click', handleBackdrop, { once: true });
  }

  // Escape key dismiss
  if (closeOnEscape) {
    const handleKeydown = (e) => {
      if (e.key === 'Escape' || e.keyCode === 27) {
        closeModal(el, options);
        if (typeof onClose === 'function') onClose();
      }
    };
    document.addEventListener('keydown', handleKeydown);
    _escapeListeners.set(el, handleKeydown);
  }

  // Dispatch custom open event
  el.dispatchEvent(new CustomEvent('modal:open', { bubbles: true, detail: { modal: el } }));
}

/**
 * Close a modal overlay.
 * @param {HTMLElement|string} modal Target modal element or CSS selector
 * @param {object} [options]
 * @param {string} [options.hiddenClass='hidden'] Class to toggle visibility
 * @param {string} [options.activeClass=''] Optional active class to remove
 */
export function closeModal(modal, options = {}) {
  const el = typeof modal === 'string' ? document.querySelector(modal) : modal;
  if (!el) return;

  const {
    hiddenClass = 'hidden',
    activeClass = '',
  } = options;

  if (hiddenClass) el.classList.add(hiddenClass);
  if (activeClass) el.classList.remove(activeClass);
  el.setAttribute('aria-hidden', 'true');

  // Clean up escape listener
  if (_escapeListeners.has(el)) {
    document.removeEventListener('keydown', _escapeListeners.get(el));
    _escapeListeners.delete(el);
  }

  // Restore focus if possible
  if (_previousFocusedElement && typeof _previousFocusedElement.focus === 'function') {
    try {
      _previousFocusedElement.focus();
    } catch (_) {}
    _previousFocusedElement = null;
  }

  // Dispatch custom close event
  el.dispatchEvent(new CustomEvent('modal:close', { bubbles: true, detail: { modal: el } }));
}

let activeDialogResolver = null;

/**
 * Close the global confirmation dialog modal and resolve the pending promise.
 * @param {object} result
 * @param {boolean} result.confirmed
 * @param {Array<string>} [result.values]
 */
export function closeDialogModal(result = { confirmed: false, values: [] }) {
  const dialogModal = document.getElementById('dialog-modal');
  if (dialogModal) dialogModal.classList.add('hidden');
  if (activeDialogResolver) {
    activeDialogResolver(result);
    activeDialogResolver = null;
  }
}

/**
 * Open the global confirmation dialog modal with customizable inputs.
 * Returns a Promise that resolves when the user confirms or cancels.
 */
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

// Global browser window fallback for non-module scripts
if (typeof window !== 'undefined') {
  window.openModal = openModal;
  window.closeModal = closeModal;
  window.openDialogModal = openDialogModal;
  window.closeDialogModal = closeDialogModal;
}

