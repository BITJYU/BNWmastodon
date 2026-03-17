const STORAGE_KEY = 'mastodon_stored_accounts';

// Strip all HTML tags from a string and trim whitespace
function stripHtml(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/<[^>]*>/g, '').trim();
}

// Safe JSON parse — returns fallback on any error
function safeParseAccounts() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/**
 * Returns all stored accounts.
 * Never throws. Returns [] on any error.
 * @returns {StoredAccount[]}
 */
export function getStoredAccounts() {
  return safeParseAccounts();
}

/**
 * Adds or updates an account in localStorage.
 * - Strips HTML from display_name before storing.
 * - Rejects credential-like fields.
 * - Updates in-place if id already exists, otherwise appends.
 * @param {{ id: string, acct: string, display_name: string, avatar: string, locked: boolean, unread_count: number }} account
 */
export function upsertStoredAccount(account) {
  if ('token' in account) {
    throw new Error('[stored_accounts] forbidden field is not allowed');
  }

  const accountId = String(account.id);
  const sanitized = {
    id: accountId,
    acct: String(account.acct ?? ''),
    display_name: stripHtml(account.display_name ?? ''),
    avatar: String(account.avatar ?? ''),
    locked: Boolean(account.locked),
    unread_count: Number(account.unread_count) || 0,
  };

  const accounts = safeParseAccounts();
  const index = accounts.findIndex(a => a.id === accountId);

  if (index >= 0) {
    accounts[index] = sanitized;
  } else {
    accounts.push(sanitized);
  }

  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(accounts));
  } catch {
    // localStorage quota exceeded or unavailable — fail silently
  }
}

/**
 * Removes a stored account by id.
 * No-op if the id is not found.
 * @param {string} id - Account ID to remove
 */
export function removeStoredAccount(id) {
  const accounts = safeParseAccounts().filter(a => a.id !== String(id));
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(accounts));
  } catch {
    // fail silently
  }
}

/**
 * Updates the unread_count for a specific stored account.
 * Used when switching away from an account — saves the last known count.
 * No-op if the id is not found.
 * @param {string} id - Account ID
 * @param {number} count - Unread notification count
 */
export function updateUnreadCount(id, count) {
  const accounts = safeParseAccounts();
  const index = accounts.findIndex(a => a.id === String(id));
  if (index < 0) return;

  accounts[index] = { ...accounts[index], unread_count: Number(count) || 0 };
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(accounts));
  } catch {
    // fail silently
  }
}

/**
 * Subscribes to cross-tab account list changes.
 * Calls callback with the updated accounts array when another tab modifies the list.
 * Returns a cleanup function — call it on component unmount.
 * @param {(accounts: StoredAccount[]) => void} callback
 * @returns {() => void} cleanup function
 */
export function syncStoredAccountsAcrossTabs(callback) {
  const handler = (event) => {
    if (event.key !== STORAGE_KEY) return;
    const updated = event.newValue ? (() => {
      try { return JSON.parse(event.newValue); } catch { return []; }
    })() : [];
    callback(Array.isArray(updated) ? updated : []);
  };

  window.addEventListener('storage', handler);
  return () => window.removeEventListener('storage', handler);
}
