import 'package:flutter/material.dart';

// ── HEALTH RECORDS PAGE ──────────────────────────────────────────────────
class HealthRecordsPage extends StatelessWidget {
  const HealthRecordsPage({super.key});

  // Mock Data for the records
  final List<Map<String, dynamic>> records = const [
    {
      'date': 'Oct 12, 2025',
      'service': 'General Consultation',
      'doctor': 'Dr. Maria Santos',
      'diagnosis': 'Seasonal Flu',
      'status': 'Completed',
    },
    {
      'date': 'Aug 05, 2025',
      'service': 'Vaccination',
      'doctor': 'BHW Nurse Ramos',
      'diagnosis': 'Flu Shot (Annual)',
      'status': 'Completed',
    },
    {
      'date': 'May 20, 2025',
      'service': 'Check-up',
      'doctor': 'Dr. Ricardo Dela Cruz',
      'diagnosis': 'Routine Cleaning',
      'status': 'Completed',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        title: const Text(
          "My Health Records",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0A2E6E),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: records.length,
        itemBuilder: (context, index) {
          final item = records[index];
          return _buildRecordCard(item);
        },
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left Accent Color Strip
            Container(
              width: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item['date'],
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Icon(Icons.more_horiz, color: Colors.grey, size: 18),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['service'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2740),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Attended by: ${item['doctor']}",
                      style: const TextStyle(fontSize: 13, color: Color(0xFF8A93A0)),
                    ),
                    const Divider(height: 24, thickness: 0.5),
                    Row(
                      children: [
                        const Icon(Icons.assignment_outlined,
                            size: 14, color: Color(0xFF1565C0)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Diagnosis: ${item['diagnosis']}",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A2740),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "VIEW",
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}