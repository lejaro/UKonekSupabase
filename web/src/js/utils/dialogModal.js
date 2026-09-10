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

// Global browser window fallback for non-module scripts
if (typeof window !== 'undefined') {
  window.openModal = openModal;
  window.closeModal = closeModal;
}
