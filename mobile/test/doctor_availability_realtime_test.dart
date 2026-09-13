import 'package:flutter_test/flutter_test.dart';
import 'package:ukonekmobile/models/doctor_schedule.dart';
import 'package:ukonekmobile/core/network/api_cache.dart';

void main() {
  group('Doctor Availability & Realtime Model Tests', () {
    test('DoctorStatus copyWith updates availabilityStatus and preserves other fields', () {
      const original = DoctorStatus(
        id: 101,
        firstName: 'John',
        lastName: 'Doe',
        specialization: 'Internal Medicine',
        availabilityStatus: 'available',
      );

      final updated = original.copyWith(availabilityStatus: 'on_break');

      expect(updated.id, 101);
      expect(updated.firstName, 'John');
      expect(updated.lastName, 'Doe');
      expect(updated.specialization, 'Internal Medicine');
      expect(updated.availabilityStatus, 'on_break');
      expect(original.availabilityStatus, 'available');
    });

    test('DoctorSchedule copyWith updates availabilityStatus on schedule item', () {
      final original = DoctorSchedule(
        id: 55,
        doctorStaffId: 101,
        doctorName: 'Dr. John Doe',
        specialization: 'Internal Medicine',
        scheduleDate: DateTime(2026, 9, 13),
        startTime: '08:00:00',
        endTime: '17:00:00',
        notes: 'Clinic morning shift',
        availabilityStatus: 'available',
      );

      final updated = original.copyWith(availabilityStatus: 'unavailable');

      expect(updated.id, 55);
      expect(updated.doctorStaffId, 101);
      expect(updated.doctorName, 'Dr. John Doe');
      expect(updated.scheduleDate, DateTime(2026, 9, 13));
      expect(updated.availabilityStatus, 'unavailable');
    });

    test('ApiCache removeWhere properly purges doctor cache entries', () {
      ApiCache.set('doctor_status_list', ['doc1', 'doc2'], const Duration(minutes: 5));
      ApiCache.set('doctor_schedules_2026-09-13_2026-10-13', ['sched1'], const Duration(minutes: 5));
      ApiCache.set('unrelated_cache_key', 'some_data', const Duration(minutes: 5));

      expect(ApiCache.get<List<String>>('doctor_status_list'), isNotNull);
      expect(ApiCache.get<List<String>>('doctor_schedules_2026-09-13_2026-10-13'), isNotNull);
      expect(ApiCache.get<String>('unrelated_cache_key'), 'some_data');

      // Invalidate doctor caches
      ApiCache.remove('doctor_status_list');
      ApiCache.removeWhere((key) => key.startsWith('doctor_schedules_'));

      expect(ApiCache.get<List<String>>('doctor_status_list'), isNull);
      expect(ApiCache.get<List<String>>('doctor_schedules_2026-09-13_2026-10-13'), isNull);
      expect(ApiCache.get<String>('unrelated_cache_key'), 'some_data');
    });
  });
}
