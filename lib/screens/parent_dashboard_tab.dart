import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/parent_message_history_section.dart';
import 'blocked_apps_screen.dart';
import 'children_management_screen.dart';
import 'content_library_screen.dart';
import 'sleep_lock_screen.dart';

/// Parent Dashboard: Stack + gradient, GENET (English), יומי card, GridView of 3 cards, green banner.
class ParentDashboardTab extends StatefulWidget {
  const ParentDashboardTab({super.key});

  @override
  State<ParentDashboardTab> createState() => _ParentDashboardTabState();
}

class _ParentDashboardTabState extends State<ParentDashboardTab> {
  int _messageRefreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF006064),
                  Color(0xFF00838F),
                  Color(0xFF0D47A1),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Icon(
              Icons.landscape,
              size: 120,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              top: 24,
              left: 20,
              right: 20,
              bottom: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'GENET',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                _YomiCard(),
                const SizedBox(height: 16),
                _ManagementButton(
                  onChildrenUpdated:
                      () => setState(() => _messageRefreshKey++),
                ),
                const SizedBox(height: 16),
                ParentMessageHistorySection(
                  refreshKeyValue: _messageRefreshKey,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _GridCard(
                        title: 'אפליקציות נעולות',
                        icon: Icons.lock_rounded,
                        iconColor: Colors.red.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedAppsScreen(),
                          ),
                        ),
                      ),
                      _GridCard(
                        title: 'שעות מס ושינה',
                        icon: Icons.schedule_rounded,
                        iconColor: AppTheme.primaryBlue,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SleepLockScreen(),
                          ),
                        ),
                      ),
                      _GridCard(
                        title: 'תכנים חיוביים',
                        icon: Icons.school_rounded,
                        iconColor: Colors.orange.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContentLibraryScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YomiCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: 0.5,
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 28,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'יומי',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                SizedBox(height: 4),
                Text(
                  'מתוזמן',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementButton extends StatelessWidget {
  const _ManagementButton({this.onChildrenUpdated});

  final VoidCallback? onChildrenUpdated;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChildrenManagementScreen(),
            ),
          ).then((_) => onChildrenUpdated?.call());
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_rounded, color: AppTheme.primaryBlue, size: 24),
              const SizedBox(width: 10),
              const Text(
                'ניהול ילדים',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _GridCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
