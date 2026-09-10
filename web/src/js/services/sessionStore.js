import { eventBus } from '../utils/eventBus.js';

/**
 * Unified Staff Session Store
 * Manages the active authenticated staff profile and provides role-based permission helpers.
 */
class SessionStore {
  constructor() {
    this._user = null;
  }

  /**
   * Get the currently cached staff user profile.
   * @returns {Object|null}
   */
  getUser() {
    return this._user;
  }

  /**
   * Set the currently active staff user profile.
   * @param {Object} user
   */
  setUser(user) {
    this._user = user || null;
    eventBus.emit('session:set', this._user);
  }

  /**
   * Clear the active session on logout.
   */
  clear() {
    this._user = null;
    eventBus.emit('session:cleared', null);
  }

  /**
   * Check if user is an Administrator.
   * @param {Object} [user]
   * @returns {boolean}
   */
  isAdmin(user = this._user) {
    const role = String(user?.role || '').trim().toLowerCase();
    return role === 'admin';
  }

  /**
   * Check if user is a Doctor.
   * @param {Object} [user]
   * @returns {boolean}
   */
  isDoctor(user = this._user) {
    const role = String(user?.role || '').trim().toLowerCase();
    return role === 'doctor';
  }

  /**
   * Check if user is a Nurse.
   * @param {Object} [user]
   * @returns {boolean}
   */
  isNurse(user = this._user) {
    const role = String(user?.role || '').trim().toLowerCase();
    return role === 'nurse';
  }

  /**
   * Check if user is a Pharmacist.
   * @param {Object} [user]
   * @returns {boolean}
   */
  isPharmacist(user = this._user) {
    const role = String(user?.role || '').trim().toLowerCase();
    return role === 'pharmacist';
  }

  /**
   * Check if user has permission to modify user accounts.
   * Nurses and regular staff are strictly prohibited.
   * @param {Object} [user]
   * @returns {boolean}
   */
  canModifyAccounts(user = this._user) {
    if (!user) return false;
    const role = String(user?.role || '').trim().toLowerCase();
    if (role === 'nurse' || role === 'staff') return false;
    return role === 'admin';
  }

  /**
   * Subscribe to session state changes.
   * @param {Function} callback
   * @returns {Function} Unsubscribe function
   */
  onSessionChange(callback) {
    const offSet = eventBus.on('session:set', callback);
    const offClear = eventBus.on('session:cleared', () => callback(null));
    return () => {
      offSet();
      offClear();
    };
  }
}

export const sessionStore = new SessionStore();

export const getSessionUser = () => sessionStore.getUser();
export const setSessionUser = (user) => sessionStore.setUser(user);
export const clearSessionUser = () => sessionStore.clear();
export const isAdminUser = (user) => sessionStore.isAdmin(user);
export const isDoctorUser = (user) => sessionStore.isDoctor(user);
export const isNurseUser = (user) => sessionStore.isNurse(user);
export const isPharmacistUser = (user) => sessionStore.isPharmacist(user);
export const canModifyAccounts = (user) => sessionStore.canModifyAccounts(user);
