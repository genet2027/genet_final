import 'package:flutter/material.dart';

import '../widgets/rounded_card.dart';
import 'backup_support_screen.dart';
import 'night_mode_settings_screen.dart';
import 'pin_login_screen.dart';

/// Settings tab content: entries to Night Mode, Backup & Support, and Logout.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NightModeSettingsScreen(),
            ),
          ),
          icon: Icons.bedtime_rounded,
          title: 'מצב לילה (חופשת שינה)',
          subtitle: 'שעות שינה ורמת התנהגות',
        ),
        const SizedBox(height: 12),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BackupSupportScreen(),
            ),
          ),
          icon: Icons.backup_rounded,
          title: 'גיבוי ותמיכה',
          subtitle: 'ייצוא/ייבוא גיבוי, דיווח בעיה, צור קשר',
        ),
        const SizedBox(height: 32),
        RoundedCard(
          onTap: () => _logout(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.logout_rounded,
                    color: Colors.red.shade400, size: 28),
                const SizedBox(width: 16),
                Text(
                  'יציאה',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      (route) => false,
    );
  }
}
