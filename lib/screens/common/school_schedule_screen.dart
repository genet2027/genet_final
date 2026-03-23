import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// מערכת שעות למחר – מסך הילד.
class SchoolScheduleScreen extends StatelessWidget {
  const SchoolScheduleScreen({super.key});

  static const List<Map<String, String>> _schedule = [
    {'time': '08:00', 'subject': 'מתמטיקה'},
    {'time': '09:00', 'subject': 'עברית'},
    {'time': '10:00', 'subject': 'הפסקה'},
    {'time': '10:15', 'subject': 'אנגלית'},
    {'time': '11:15', 'subject': 'מדעים'},
    {'time': '12:15', 'subject': 'סיום'},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מערכת שעות למחר'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),
            ..._schedule.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Text(
                      item['time']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    title: Text(
                      item['subject']!,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
