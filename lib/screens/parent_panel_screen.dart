import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'blocked_apps_screen.dart';
import 'pin_login_screen.dart';
import 'sleep_lock_screen.dart';

// Mock data
const _childName = 'דניאל';
const _childAge = 9;
const _childGrade = 'ד׳';
const _blockedAttempts = [
  {'appName': 'Instagram', 'time': '22:14'},
  {'appName': 'TikTok', 'time': '22:32'},
  {'appName': 'YouTube', 'time': '06:41'},
];

/// פאנל ההורה - תפריט עם כל ההגדרות
class ParentPanelScreen extends StatelessWidget {
  const ParentPanelScreen({super.key});

  void _navigateAndPopToPanel(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PinLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('פאנל הורה - Genet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _MenuItemCard(
            icon: Icons.bedtime,
            title: 'Sleep Lock Mode',
            subtitle: 'הגדרת טווח שעות נעילה (למשל 22:00 עד 07:00)',
            onTap: () => _navigateAndPopToPanel(
              context,
              const SleepLockScreen(),
            ),
          ),
          const SizedBox(height: 12),
          _MenuItemCard(
            icon: Icons.block,
            title: 'רשימת אפליקציות חסומות',
            subtitle: 'בחר את האפליקציות שתיחסמנה',
            onTap: () => _navigateAndPopToPanel(
              context,
              const BlockedAppsScreen(),
            ),
          ),
          const SizedBox(height: 12),
          _ChildInfoCard(
            childName: _childName,
            childAge: _childAge,
            childGrade: _childGrade,
          ),
          const SizedBox(height: 12),
          _BlockedAttemptsCard(attempts: _blockedAttempts),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('יציאה'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: const BorderSide(color: AppTheme.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItemCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.lightBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class _ChildInfoCard extends StatelessWidget {
  final String childName;
  final int childAge;
  final String childGrade;

  const _ChildInfoCard({
    required this.childName,
    required this.childAge,
    required this.childGrade,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person, color: AppTheme.primaryBlue, size: 28),
                ),
                const SizedBox(width: 16),
                Text(
                  'פרטי הילד',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'שם', value: childName),
            _InfoRow(label: 'גיל', value: childAge.toString()),
            _InfoRow(label: 'כיתה', value: childGrade),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }
}

class _BlockedAttemptsCard extends StatelessWidget {
  final List<Map<String, String>> attempts;

  const _BlockedAttemptsCard({required this.attempts});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shield_moon, color: AppTheme.primaryBlue, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'שומר לילה',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'מעקב אחר ניסיונות פתיחה בשעות חסומות',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (attempts.isEmpty)
              Text(
                'אין ניסיונות כרגע',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              )
            else
              ...attempts.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e['appName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(e['time'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
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
