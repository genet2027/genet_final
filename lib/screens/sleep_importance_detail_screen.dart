import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// למה שינה חשובה? – הסבר על שינה, מוח, שרירים וביצועים.
class SleepImportanceDetailScreen extends StatelessWidget {
  const SleepImportanceDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('למה שינה חשובה?'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'המוח והגוף נבנים בשינה',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 16),
            Text(
              'בזמן שאתה ישן, המוח שומר ומעבד את מה שלמדת ביום – במתמטיקה, בעברית ובכל מקצוע. גם השרירים מתחזקים ומתאוששים אחרי אימון בכדורגל או בכדורסל.',
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 16),
            Text(
              'שינה טובה עוזרת לך להתרכז בכיתה, לשחק טוב יותר במגרש ולזכור את החומר למבחן. כשאתה ישן מספיק שעות, אתה מרגיש רענן ומוכן ליום חדש.',
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.grey.shade800,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.lightBlue.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'שינה טובה = ביצועים טובים יותר במגרש ובכיתה!',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppTheme.darkBlue,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
