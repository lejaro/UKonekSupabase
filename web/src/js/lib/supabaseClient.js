import { createClient as createClientFromCdn } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { getOrCreateTabId } from '../services/sessionAuth.js';

const DEFAULT_SUPABASE_URL = 'https://dqjxpwbsbzagbjtulhue.supabase.co';
const DEFAULT_SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g';

const config = (typeof window !== 'undefined' && window.UKONEK_CONFIG) || {};
const supabaseUrl = String(config.SUPABASE_URL || DEFAULT_SUPABASE_URL).trim();
const supabaseAnonKey = String(config.SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY).trim();
const directSupabaseUrl = String(config.DIRECT_SUPABASE_URL || DEFAULT_SUPABASE_URL).trim();

const createClient = (typeof window !== 'undefined' && window.supabase?.createClient) || createClientFromCdn;

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
    return new URL(directSupabaseUrl).hostname.split('.')[0] || 'ukonek';
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
