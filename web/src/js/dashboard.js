/**
 * UKonek Clinical Dashboard - Modular ES Entry Point & Orchestrator
 * Coordinates domain controllers, session authentication, and view navigation.
 */

import { supabase } from './lib/supabaseClient.js';
import { sessionStore } from './services/sessionStore.js';
import * as authService from './services/authService.js';
import * as staffService from './services/staffService.js';
import * as sessionAuth from './services/sessionAuth.js';
import {
  showToast,
  dismissPagePreloader,
  setLoading
} from './utils/uiHelpers.js';
import {
  openDataDetail,
  closeDataDetail
} from './utils/dataDetailModal.js';
import {
  openDialogModal,
  closeDialogModal
} from './utils/dialogModal.js';
import { startIdleTimer, stopIdleTimer } from './utils/sessionTimeout.js';
import {
  initNavigation,
  showSection,
  navigateToSection,
  registerSectionHooks,
  getSectionFromHash,
  setSectionHash,
  DEFAULT_SECTION_ID,
  applyRoleAccess,
  populateProfile,
  switchProfileSubpane
} from './controllers/navigationController.js';
import {
  initTelemetryController,
  refreshAdminDashboard,
  bindLaunchpadActions
} from './controllers/telemetryController.js';
import {
  initScheduleController,
  loadDoctorSchedules
} from './controllers/scheduleController.js';
import {
  initUsersController,
  loadStaffDirectory,
  loadCitizenDirectory,
  switchUsersPane
} from './controllers/usersController.js';
import {
  initTriageSection,
  evaluateVitalsRisk
} from './controllers/triageController.js';
import {
  initConsultationSection,
  loadConsultationData,
  loadTriagedWaitingPatients,
  initLabSection,
  openConsultationModal,
  closeConsultationModal,
  updateLabOrderStatus
} from './controllers/consultationController.js';
import {
  initPharmacyModule,
  loadMedicinesCatalog
} from './controllers/pharmacyController.js';
import {
  initPrescriptionController,
  openPrescriptionModalForPatient,
  closePrescriptionModal
} from './controllers/prescriptionController.js';
import {
  initQueueController,
  loadQueueTickets,
  openVitalAssessmentModal,
  closeVitalAssessmentModal
} from './controllers/queueController.js';
import {
  initPromoPosterController,
  loadPromoPosters
} from './controllers/promoPosterController.js';
import {
  initReportsHubController,
  switchReportsHubPane,
  refreshActiveReportsHubPane,
  loadFeedback,
  renderClinicalStats
} from './controllers/reportsHubController.js';

function withTimeout(promise, timeoutMs, timeoutMessage) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs);
    })
  ]);
}

export async function ensureAuthenticatedSession(force = false) {
  const cached = sessionStore.getUser();
  if (!force && cached) {
    return cached;
  }

  console.log('[Dashboard] Validating staff session with Supabase...');

  try {
    const profile = await withTimeout(
      authService.getAuthenticatedStaffProfile(),
      5000,
      'Session validation timed out'
    );

    if (!profile) {
      console.warn('[Dashboard] No valid authenticated profile from Supabase. Redirecting to login...');
      window.location.replace('./index.html');
      return null;
    }

    const role = String(profile.role || '').toLowerCase();
    const validRoles = ['doctor', 'nurse', 'pharmacist', 'admin'];
    if (!validRoles.includes(role)) {
      console.warn(`[Dashboard] Unauthorized role '${role}'. Redirecting...`);
      window.location.replace('./index.html');
      return null;
    }

    // Role redirection if wrong dashboard
    if (role === 'admin') {
      window.location.replace('./dashboard-admin.html');
      return null;
    }
    if (role === 'pharmacist') {
      window.location.replace('./dashboard-pharmacist.html');
      return null;
    }

    sessionStore.setUser(profile);
    const resolvedUsername = (profile.username && !profile.username.includes('@'))
      ? profile.username
      : (profile.first_name || 'Staff');

    sessionAuth.setAuthSessionMeta({
      role,
      userId: profile.id || null,
      email: profile.email || null,
      username: resolvedUsername,
      firstName: profile.first_name || null,
      first_name: profile.first_name || null,
      lastName: profile.last_name || null,
      last_name: profile.last_name || null
    });
    sessionStorage.setItem('ukonek_staff_name', resolvedUsername);
    sessionStorage.setItem('ukonek_role', role);
    console.log('[Dashboard] Authenticated staff profile loaded:', profile.username || profile.email, `(${role})`);
    return profile;
  } catch (error) {
    console.error('[Dashboard] Session validation failure:', error?.message || error);
    window.location.replace('./index.html');
    return null;
  }
}

// Global backwards-compatibility exports for sibling scripts (health-records.js, reports-ui.js, csv-import.js)
if (typeof window !== 'undefined') {
  window.supabase = supabase;
  window.showToast = showToast;
  window.openDataDetail = openDataDetail;
  window.closeDataDetail = closeDataDetail;
  window.openDialogModal = openDialogModal;
  window.closeDialogModal = closeDialogModal;
  window.showSection = showSection;
  window.loadQueueTickets = loadQueueTickets;
  window.openConsultationModal = openConsultationModal;
  window.closeConsultationModal = closeConsultationModal;
  window.loadTriagedWaitingPatients = loadTriagedWaitingPatients;
  window.openVitalAssessmentModal = openVitalAssessmentModal;
  window.closeVitalAssessmentModal = closeVitalAssessmentModal;
  window.updateLabOrderStatus = updateLabOrderStatus;
  window.evaluateVitalsRisk = evaluateVitalsRisk;
  window.ensureAuthenticatedSession = ensureAuthenticatedSession;
  window.openPrescriptionModalForPatient = openPrescriptionModalForPatient;
  window.closePrescriptionModal = closePrescriptionModal;
  window.loadPromoPosters = loadPromoPosters;
  window.switchReportsHubPane = switchReportsHubPane;
  window.refreshActiveReportsHubPane = refreshActiveReportsHubPane;
  window.loadFeedback = loadFeedback;
  window.renderClinicalStats = renderClinicalStats;

  // Polyfill dynamic module promises if legacy callers invoke them
  window.loadSupabaseModule = async () => ({ supabase });
  window.loadAuthServiceModule = async () => authService;
  window.loadStaffServiceModule = async () => staffService;
  window.loadAuthSessionModule = async () => sessionAuth;
}

/**
 * Bootstrap the application, register section hooks, and initialize controllers.
 */
async function bootstrapDashboard() {
  console.log('[Dashboard] Bootstrap starting...');
  try {
    // 1. Authenticate user session strictly against Supabase
    const user = await ensureAuthenticatedSession();
    if (!user) return;

    // Reveal page once session is verified
    document.body.classList.remove('auth-cloak');

    // Activate 15-minute idle timeout guard (HIPAA compliance)
    startIdleTimer();

    applyRoleAccess(user);

    // 2. Register lifecycle hooks for navigation transitions
    registerSectionHooks({
      'dashboard-section': () => {
        refreshAdminDashboard();
        bindLaunchpadActions();
      },
      'queue-section': () => loadQueueTickets(),
      'schedule-section': () => loadDoctorSchedules(),
      'consultation-section': () => {
        loadConsultationData();
        initLabSection();
        loadTriagedWaitingPatients();
      },
      'users-section': (options = {}) => {
        loadStaffDirectory();
        loadCitizenDirectory();
        if (options?.pane) {
          switchUsersPane(options.pane);
        }
      },
      'medicine-section': () => loadMedicinesCatalog(),
      'vitals-section': () => initTriageSection(),
      'reports-section': (options = {}) => {
        if (options?.pane) {
          switchReportsHubPane(options.pane);
        } else {
          refreshActiveReportsHubPane();
        }
      },
      'profile-section': (options = {}) => {
        const currentUser = sessionStore.getUser();
        if (currentUser) populateProfile(currentUser);
        if (options?.pane) {
          switchProfileSubpane(options.pane);
        } else {
          switchProfileSubpane('profile-pane-details');
        }
      }
    });

    // 3. Initialize domain controllers
    initNavigation();
    initTelemetryController();
    initScheduleController();
    initUsersController();
    initTriageSection();
    initConsultationSection();
    initPharmacyModule();
    initPrescriptionController();
    initPromoPosterController();
    initReportsHubController();
    
    // Non-blocking queue controller init so realtime setup does not delay navigation
    initQueueController().catch(e => console.warn('[Dashboard] Queue controller init warning:', e));

    // Parallel background pre-load of directories so counters and metrics are immediately populated
    Promise.all([
      loadStaffDirectory().catch(e => console.warn('[Dashboard] Staff directory load warning:', e)),
      loadCitizenDirectory().catch(e => console.warn('[Dashboard] Citizen directory load warning:', e))
    ]);

    // 4. Resolve and display initial section based on URL hash or default
    const initialSection = getSectionFromHash() || DEFAULT_SECTION_ID;
    console.log('[Dashboard] Navigating to initial section:', initialSection);
    navigateToSection(initialSection);
  } catch (err) {
    console.error('[Dashboard] Bootstrap error:', err);
    showToast('Failed to initialize dashboard. Please refresh the page.', 'error');
  } finally {
    dismissPagePreloader();
    console.log('[Dashboard] Bootstrap complete.');
  }
}

let bootstrapStarted = false;
function runBootstrapOnce() {
  if (bootstrapStarted) return;
  bootstrapStarted = true;
  bootstrapDashboard();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', runBootstrapOnce);
}

if (document.readyState !== 'loading') {
  runBootstrapOnce();
} else {
  // Guaranteed failsafe in case DOMContentLoaded was already dispatched
  setTimeout(runBootstrapOnce, 800);
}
