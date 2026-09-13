import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getOrCreateTabId } from '../services/sessionAuth.js';

const config = window.UKONEK_CONFIG || {};
const supabaseUrl = String(config.SUPABASE_URL || '').trim();
const supabaseAnonKey = String(config.SUPABASE_ANON_KEY || '').trim();

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase runtime config. Update web/src/js/runtime-config.js');
}

function getSessionStorageAdapter() {
  try {
    if (typeof window === 'undefined' || !window.sessionStorage) return undefined;
    const probeKey = '__ukonek_sb_probe__';
    window.sessionStorage.setItem(probeKey, '1');
    window.sessionStorage.removeItem(probeKey);
    return window.sessionStorage;
  } catch (_) {
    return undefined;
  }
}

const tabId = getOrCreateTabId();
const projectRef = (() => {
  try {
    return new URL(supabaseUrl).hostname.split('.')[0] || 'ukonek';
  } catch (_) {
    return 'ukonek';
  }
})();

const storage = getSessionStorageAdapter();
const storageKey = `sb-${projectRef}-auth-tab-${tabId}`;

// Fallback: If tab-scoped session is empty, check legacy default supabase key
if (storage && !storage.getItem(storageKey)) {
  try {
    const legacyKey = `sb-${projectRef}-auth-token`;
    const legacyVal = storage.getItem(legacyKey) || (typeof window !== 'undefined' && window.localStorage?.getItem(legacyKey));
    if (legacyVal) {
      storage.setItem(storageKey, legacyVal);
    }
  } catch (_) {}
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage,
    storageKey,
    persistSession: Boolean(storage),
    autoRefreshToken: true,
    detectSessionInUrl: false,
    lock: async (_name, _acquireTimeout, fn) => {
      // Direct lock execution prevents navigator.locks deadlocks during Live Server reloads
      return await fn();
    }
  }
});
