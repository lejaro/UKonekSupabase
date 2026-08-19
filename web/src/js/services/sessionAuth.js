const AUTH_SESSION_KEY = 'ukonek.auth.session';
const TAB_ID_KEY = 'ukonek.auth.tab_id';

function safeSessionStorage() {
  try {
    if (typeof window === 'undefined' || !window.sessionStorage) return null;
    const probeKey = '__ukonek_ss_probe__';
    window.sessionStorage.setItem(probeKey, '1');
    window.sessionStorage.removeItem(probeKey);
    return window.sessionStorage;
  } catch (_) {
    return null;
  }
}

function readSession() {
  const storage = safeSessionStorage();
  if (!storage) return null;

  try {
    const raw = storage.getItem(AUTH_SESSION_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (_) {
    return null;
  }
}

export function getAuthSessionMeta() {
  return readSession();
}

export function setAuthSessionMeta(meta = {}) {
  const storage = safeSessionStorage();
  if (!storage) return;

  const current = readSession() || {};
  const next = {
    ...current,
    ...meta,
    updatedAt: new Date().toISOString()
  };

  storage.setItem(AUTH_SESSION_KEY, JSON.stringify(next));
}

export function clearAuthSessionMeta() {
  const storage = safeSessionStorage();
  if (!storage) return;
  storage.removeItem(AUTH_SESSION_KEY);
}

export function getOrCreateTabId() {
  const storage = safeSessionStorage();
  if (!storage) return 'fallback-tab';

  let tabId = storage.getItem(TAB_ID_KEY);
  if (tabId) return tabId;

  tabId = (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function')
    ? crypto.randomUUID()
    : `tab-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  storage.setItem(TAB_ID_KEY, tabId);
  return tabId;
}
