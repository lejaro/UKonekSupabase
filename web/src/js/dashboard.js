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
import {
  initNavigation,
  showSection,
  registerSectionHooks,
  getSectionFromHash,
  setSectionHash,
  DEFAULT_SECTION_ID,
  applyRoleAccess,
  populateProfile
} from './controllers/navigationController.js';
import {
  initTelemetryController,
  refreshAdminDashboard
} from './controllers/telemetryController.js';
import {
  initScheduleController,
  loadDoctorSchedules
} from './controllers/scheduleController.js';
import {
  initUsersController,
  loadStaffDirectory,
  loadCitizenDirectory
} from './controllers/usersController.js';
import {
  initTriageSection,
  evaluateVitalsRisk
} from './controllers/triageController.js';
import {
  initConsultationSection,
  loadConsultationData,
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
  initQueueController,
  loadQueueTickets,
  openVitalAssessmentModal,
  closeVitalAssessmentModal
} from './controllers/queueController.js';

export async function ensureAuthenticatedSession(force = false) {
  const cached = sessionStore.getUser();
  if (!force && cached) {
    return cached;
  }

  try {
    const profile = await authService.getAuthenticatedStaffProfile();
    if (!profile) {
      window.location.replace('./index.html');
      return null;
    }

    sessionStore.setUser(profile);
    const role = String(profile.role || 'nurse').toLowerCase();
    sessionAuth.setAuthSessionMeta({
      role,
      userId: profile.id || null,
      email: profile.email || null
    });
    return profile;
  } catch (error) {
    console.error('[Dashboard] Session validation error:', error);
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
  window.openVitalAssessmentModal = openVitalAssessmentModal;
  window.closeVitalAssessmentModal = closeVitalAssessmentModal;
  window.updateLabOrderStatus = updateLabOrderStatus;
  window.evaluateVitalsRisk = evaluateVitalsRisk;
  window.ensureAuthenticatedSession = ensureAuthenticatedSession;

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
  try {
    // 1. Authenticate user session
    const user = await ensureAuthenticatedSession();
    if (!user) return;

    applyRoleAccess(user);

    // 2. Register lifecycle hooks for navigation transitions
    registerSectionHooks({
      'dashboard-section': () => refreshAdminDashboard(),
      'queue-section': () => loadQueueTickets(),
      'schedule-section': () => loadDoctorSchedules(),
      'consultation-section': () => {
        loadConsultationData();
        initLabSection();
      },
      'users-section': () => {
        loadStaffDirectory();
        loadCitizenDirectory();
      },
      'medicine-section': () => loadMedicinesCatalog(),
      'vitals-section': () => initTriageSection(),
      'profile-section': () => {
        const currentUser = sessionStore.getUser();
        if (currentUser) populateProfile(currentUser);
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
    await initQueueController();

    // 4. Resolve and display initial section based on URL hash or default
    const initialSection = getSectionFromHash() || DEFAULT_SECTION_ID;
    showSection(initialSection);
  } catch (err) {
    console.error('[Dashboard] Bootstrap error:', err);
    showToast('Failed to initialize dashboard. Please refresh the page.', 'error');
  } finally {
    dismissPagePreloader();
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrapDashboard);
} else {
  bootstrapDashboard();
}
