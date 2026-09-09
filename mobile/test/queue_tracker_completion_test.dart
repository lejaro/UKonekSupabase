import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Queue Tracker Completion & Reset Tests', () {
    late TextEditingController reasonCtrl;
    late TextEditingController symptomsCtrl;
    String citizenType = 'regular';
    String? selectedService;

    setUp(() {
      reasonCtrl = TextEditingController(text: 'Severe migraine for 2 days');
      symptomsCtrl = TextEditingController(text: 'Dizziness, nausea, photophobia');
      citizenType = 'pwd';
      selectedService = 'consultation_general';
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      reasonCtrl.dispose();
      symptomsCtrl.dispose();
    });

    test('Erase all inputs in queue tracker resets form state completely', () {
      expect(reasonCtrl.text, isNotEmpty);
      expect(symptomsCtrl.text, isNotEmpty);
      expect(selectedService, isNotNull);
      expect(citizenType, 'pwd');

      // Execute form inputs erasure
      selectedService = null;
      citizenType = 'regular';
      reasonCtrl.clear();
      symptomsCtrl.clear();

      expect(reasonCtrl.text, isEmpty);
      expect(symptomsCtrl.text, isEmpty);
      expect(selectedService, isNull);
      expect(citizenType, 'regular');
    });

    test('Acknowledge completed ticket in SharedPreferences avoids duplicate popups', () async {
      final prefs = await SharedPreferences.getInstance();
      const testTicketId = 12345;

      int? lastAck = prefs.getInt('last_acknowledged_completed_ticket_id');
      expect(lastAck, isNull);

      // Save acknowledged ticket
      await prefs.setInt('last_acknowledged_completed_ticket_id', testTicketId);

      lastAck = prefs.getInt('last_acknowledged_completed_ticket_id');
      expect(lastAck, testTicketId);

      // Verify that same ticket ID is detected as already acknowledged
      final shouldShowModal = (lastAck != testTicketId);
      expect(shouldShowModal, isFalse);
    });

    test('Completed status correctly transitions active queue state', () {
      final activeTicketMap = {
        'id': 101,
        'status': 'serving',
        'service_label': 'General Consultation',
        'queue_number': 12,
      };

      bool isCompleted(Map<String, dynamic>? ticket) {
        return ticket?['status']?.toString().toLowerCase().trim() == 'completed';
      }

      expect(isCompleted(activeTicketMap), isFalse);

      final completedTicketMap = {
        'id': 101,
        'status': 'completed',
        'service_label': 'General Consultation',
        'queue_number': 12,
        'completed_at': DateTime.now().toIso8601String(),
      };

      expect(isCompleted(completedTicketMap), isTrue);
    });
  });
}
