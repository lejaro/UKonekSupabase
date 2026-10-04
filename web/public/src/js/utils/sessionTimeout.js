/**
 * Healthcare Session Idle & Inactivity Security Manager
 * Implements HIPAA Security Rule § 164.312(a)(2)(iii) - Automatic Logoff.
 * 
 * Automatically terminates authenticated clinical sessions after 15 minutes
 * of inactivity across all browser tabs to prevent unauthorized access to PHI
 * on unattended workstations.
 */

import { supabase } from '../lib/supabaseClient.js';
import { setStaffPresence } from '../services/authService.js';

const DEFAULT_IDLE_TIMEOUT_MS = 15 * 60 * 1000; // 15 minutes
const LAST_ACTIVE_STORAGE_KEY = 'ukonek_last_active_ts';
const THROTTLE_INTERVAL_MS = 4000; // Throttle storage writes to every 4s

let timerInterval = null;
let lastActiveLocal = Date.now();
let lastStorageWrite = 0;
let isTerminating = false;

const ACTIVITY_EVENTS = [
  'mousemove',
  'mousedown',
  'keydown',
  'touchstart',
  'scroll',
  'click'
];

/**
 * Record user activity and synchronize across open tabs.
 */
function recordActivity() {
  const now = Date.now();
  lastActiveLocal = now;

  if (now - lastStorageWrite >= THROTTLE_INTERVAL_MS) {
    lastStorageWrite = now;
    try {
      localStorage.setItem(LAST_ACTIVE_STORAGE_KEY, String(now));
    } catch (_) {
      // Storage unavailable / quota
    }
  }
}

/**
 * Retrieve the latest activity timestamp across all open tabs.
 */
function getLatestActivity() {
  try {
    const stored = localStorage.getItem(LAST_ACTIVE_STORAGE_KEY);
    const storedNum = stored ? parseInt(stored, 10) : 0;
    return Math.max(lastActiveLocal, isNaN(storedNum) ? 0 : storedNum);
  } catch (_) {
    return lastActiveLocal;
  }
}

/**
 * Securely terminate the session and redirect to the login screen.
 */
export async function terminateInactiveSession(reason = 'timeout') {
  if (isTerminating) return;
  isTerminating = true;

  console.warn(`[Security] Session terminated due to ${reason} (15-minute inactivity rule).`);

  stopIdleTimer();

  // 1. Mark presence offline (best-effort)
  try {
    await setStaffPresence(false).catch(() => {});
  } catch (_) {}

  // 2. Sign out of Supabase
  try {
    await supabase.auth.signOut().catch(() => {});
  } catch (_) {}

  // 3. Clear all cached session state
  try {
    sessionStorage.clear();
    localStorage.removeItem(LAST_ACTIVE_STORAGE_KEY);
  } catch (_) {}

  // 4. Show timeout notice and redirect
  const redirectTarget = `./index.html?reason=${encodeURIComponent(reason)}`;
  window.location.replace(redirectTarget);
}

/**
 * Initialize the 15-minute inactivity tracker.
 * 
 * @param {Object} options
 * @param {number} [options.timeoutMs=900000] - Inactivity duration (default: 15 minutes)
 * @param {Function} [options.onTimeout] - Optional custom timeout callback
 */
export function startIdleTimer(options = {}) {
  const timeoutMs = options.timeoutMs || DEFAULT_IDLE_TIMEOUT_MS;
  const onTimeout = options.onTimeout || terminateInactiveSession;

  // Initialize activity timestamp
  const now = Date.now();
  lastActiveLocal = now;
  try {
    localStorage.setItem(LAST_ACTIVE_STORAGE_KEY, String(now));
  } catch (_) {}

  // Register throttled activity listeners
  ACTIVITY_EVENTS.forEach((eventName) => {
    window.addEventListener(eventName, recordActivity, { passive: true });
  });

  // Cross-tab storage listener to react if another tab logged out
  window.addEventListener('storage', (e) => {
    if (e.key === LAST_ACTIVE_STORAGE_KEY && !e.newValue) {
      // Key was removed by another tab logging out
      onTimeout('logged_out');
    }
  });

  // Check every 10 seconds for idle timeout
  if (timerInterval) clearInterval(timerInterval);
  timerInterval = setInterval(() => {
    const elapsed = Date.now() - getLatestActivity();
    if (elapsed >= timeoutMs) {
      console.warn(`[Security] Inactivity threshold reached: ${Math.round(elapsed / 1000)}s >= ${Math.round(timeoutMs / 1000)}s`);
      onTimeout('timeout');
    }
  }, 10000);

  console.log(`[Security] 15-minute idle timeout guard active (${timeoutMs / 60000} mins).`);
}

/**
 * Stop the idle timer (e.g. on manual logout or page tear-down).
 */
export function stopIdleTimer() {
  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
  ACTIVITY_EVENTS.forEach((eventName) => {
    window.removeEventListener(eventName, recordActivity);
  });
}
