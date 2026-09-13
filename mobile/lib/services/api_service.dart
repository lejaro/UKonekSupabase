import 'dart:async';
import '../utils/formatters.dart' as fmt;
import '../models/models.dart';
import '../core/network/api_cache.dart';
import 'announcement_service.dart';
import 'auth_service.dart';
import 'citizen_profile_service.dart';
import 'clinical_records_service.dart';
import 'doctor_schedule_service.dart';
import 'feedback_service.dart';
import 'prescription_service.dart';
import 'queue_service.dart';

// Re-export domain models & services so all existing consumers maintain 100% backwards compatibility
export '../models/models.dart';
export 'announcement_service.dart';
export 'auth_service.dart';
export 'citizen_profile_service.dart';
export 'clinical_records_service.dart';
export 'doctor_schedule_service.dart';
export 'feedback_service.dart';
export 'prescription_service.dart';
export 'queue_service.dart';

/// Facade for mobile data services providing a single unified API surface
/// while delegating specific domain concerns to dedicated service modules.
class ApiService {
  ApiService._();

  /// Formats a doctor's name cleanly, stripping redundant 'Dr.', 'Dr', 'Doctor' prefixes
  /// and returning a single standardized 'Dr. [Clean Name]'.
  static String formatDoctorName(String? raw) => fmt.formatDoctorName(raw);

  /// Clear all cached data (call on sign-out or manual refresh).
  static void clearAllCaches() {
    ApiCache.clear();
    CitizenProfileService.clearCitizenProfileCache();
  }

  // ── Authentication & Onboarding ──────────────────────────────────
  static Future<void> requestCitizenPreAuthOtp({required Map<String, dynamic> payload}) =>
      AuthService.requestCitizenPreAuthOtp(payload: payload);

  static Future<void> verifyCitizenPreAuthOtp({required String email, required String otp}) =>
      AuthService.verifyCitizenPreAuthOtp(email: email, otp: otp);

  static Future<void> completeCitizenPreAuthSignup({
    required String email,
    required String username,
    required String password,
  }) =>
      AuthService.completeCitizenPreAuthSignup(email: email, username: username, password: password);

  static Future<void> requestCitizenOtp({required String email, required String purpose}) =>
      AuthService.requestCitizenOtp(email: email, purpose: purpose);

  static Future<void> verifyCitizenEmailOtp({required String email, required String otp}) =>
      AuthService.verifyCitizenEmailOtp(email: email, otp: otp);

  static bool hasVerifiedSessionForEmail(String email) =>
      AuthService.hasVerifiedSessionForEmail(email);

  static Future<void> startCitizenEmailVerification({required Map<String, dynamic> payload}) =>
      AuthService.startCitizenEmailVerification(payload: payload);

  static Future<void> completeCitizenRegistration({required Map<String, dynamic> payload}) =>
      AuthService.completeCitizenRegistration(payload: payload);

  static Future<Map<String, dynamic>> loginCitizen({
    required String identifier,
    required String password,
  }) =>
      AuthService.loginCitizen(identifier: identifier, password: password);

  static Future<void> registerCitizen({required Map<String, dynamic> payload}) =>
      AuthService.registerCitizen(payload: payload);

  static Future<void> requestPasswordReset({required String email}) =>
      AuthService.requestPasswordReset(email: email);

  static Future<void> resetCitizenPassword({required String password}) =>
      AuthService.resetCitizenPassword(password: password);

  static Future<void> signOut() => AuthService.signOut();

  // ── Doctor Schedules ─────────────────────────────────────────────
  static Future<List<DoctorStatus>> listDoctorStatus({bool forceRefresh = false}) =>
      DoctorScheduleService.listDoctorStatus(forceRefresh: forceRefresh);

  static Future<List<DoctorSchedule>> listAvailableDoctorSchedules({
    DateTime? from,
    DateTime? to,
    bool forceRefresh = false,
  }) =>
      DoctorScheduleService.listAvailableDoctorSchedules(
        from: from,
        to: to,
        forceRefresh: forceRefresh,
      );

  static void invalidateDoctorCache() =>
      DoctorScheduleService.invalidateDoctorCache();

  // ── Queue Management ─────────────────────────────────────────────
  static Future<List<QueueServiceOption>> listAvailableQueueServices({DateTime? date}) =>
      QueueService.listAvailableQueueServices(date: date);

  static Future<QueueTicket> joinQueue(QueueJoinRequest request) =>
      QueueService.joinQueue(request);

  static Future<QueueDashboardSnapshot> getMyQueueDashboard() =>
      QueueService.getMyQueueDashboard();

  static Future<QueueLimiterStatus> getQueueLimiterStatus() =>
      QueueService.getQueueLimiterStatus();

  static Future<bool> cancelMyQueue() => QueueService.cancelMyQueue();

  static Future<Map<String, dynamic>?> getTicketStatus(int ticketId) =>
      QueueService.getTicketStatus(ticketId);

  static Future<Map<String, dynamic>?> getCompletedQueueTicket({int? ticketId}) =>
      QueueService.getCompletedQueueTicket(ticketId: ticketId);

  static Future<Map<String, dynamic>> getTvQueueDisplay() =>
      QueueService.getTvQueueDisplay();

  // ── Citizen Profile ──────────────────────────────────────────────
  static void clearCitizenProfileCache() =>
      CitizenProfileService.clearCitizenProfileCache();

  static Future<Map<String, dynamic>> fetchMyCitizenProfile({bool force = false}) =>
      CitizenProfileService.fetchMyCitizenProfile(force: force);

  static Future<void> updateMyCitizenProfile(Map<String, dynamic> data) =>
      CitizenProfileService.updateMyCitizenProfile(data);

  // ── Clinical Records ─────────────────────────────────────────────
  static Future<List<VitalSigns>> fetchVitalSigns({int limit = 50}) =>
      ClinicalRecordsService.fetchVitalSigns(limit: limit);

  static Future<List<Consultation>> fetchConsultations({int limit = 50}) =>
      ClinicalRecordsService.fetchConsultations(limit: limit);

  // ── Prescriptions & Medicine Intake ──────────────────────────────
  static Future<List<PrescribedMedicine>> getMyPrescribedMedicines() =>
      PrescriptionService.getMyPrescribedMedicines();

  static Future<List<ScheduledMedicine>> getMedicineSchedule({int? citizenId}) =>
      PrescriptionService.getMedicineSchedule(citizenId: citizenId);

  static Future<List<PrescriptionRecord>> fetchPrescriptions({int limit = 50, int? citizenId}) =>
      PrescriptionService.fetchPrescriptions(limit: limit, citizenId: citizenId);

  static List<PrescriptionDispenseLog> synthesizeDispenseLogsFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) =>
      PrescriptionService.synthesizeDispenseLogsFromPrescriptions(prescriptions);

  static List<ScheduledMedicine> synthesizeScheduledMedicinesFromPrescriptions(
    List<PrescriptionRecord> prescriptions,
  ) =>
      PrescriptionService.synthesizeScheduledMedicinesFromPrescriptions(prescriptions);

  static List<ScheduledMedicine> deduplicateMedicines(
    List<ScheduledMedicine> primary, [
    List<ScheduledMedicine> secondary = const [],
  ]) =>
      PrescriptionService.deduplicateMedicines(primary, secondary);

  static Future<List<PrescriptionDispenseLog>> fetchPrescriptionDispenseLogs({
    int? prescriptionId,
    int limit = 50,
    int? citizenId,
  }) =>
      PrescriptionService.fetchPrescriptionDispenseLogs(
        prescriptionId: prescriptionId,
        limit: limit,
        citizenId: citizenId,
      );

  static Future<void> logMedicineIntake({
    required int prescriptionItemId,
    required String scheduledTime,
    required int doseIndex,
    int? citizenId,
    String? intakeDate,
  }) =>
      PrescriptionService.logMedicineIntake(
        prescriptionItemId: prescriptionItemId,
        scheduledTime: scheduledTime,
        doseIndex: doseIndex,
        citizenId: citizenId,
        intakeDate: intakeDate,
      );

  static Future<void> deleteMedicineIntakeLog({
    required int prescriptionItemId,
    required int doseIndex,
    required String intakeDate,
    int? citizenId,
  }) =>
      PrescriptionService.deleteMedicineIntakeLog(
        prescriptionItemId: prescriptionItemId,
        doseIndex: doseIndex,
        intakeDate: intakeDate,
        citizenId: citizenId,
      );

  static Future<List<Map<String, dynamic>>> getIntakeLogsForDate(
    DateTime date, {
    int? citizenId,
  }) =>
      PrescriptionService.getIntakeLogsForDate(date, citizenId: citizenId);

  static Future<NewPrescriptionAlert?> fetchLatestUnacknowledgedPrescription() =>
      PrescriptionService.fetchLatestUnacknowledgedPrescription();

  static Future<void> acknowledgePrescription(int prescriptionId) =>
      PrescriptionService.acknowledgePrescription(prescriptionId);

  // ── Announcements ────────────────────────────────────────────────
  static Future<List<Announcement>> fetchAnnouncements() =>
      AnnouncementService.fetchAnnouncements();

  // ── Citizen Feedback ─────────────────────────────────────────────
  static Future<void> submitCitizenFeedback(FeedbackSubmission submission) =>
      FeedbackService.submitCitizenFeedback(submission);
}
