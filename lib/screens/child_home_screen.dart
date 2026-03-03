import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/child_model.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import 'blocked_apps_times_screen.dart';
import 'content_library_screen.dart';
import 'role_select_screen.dart';
import 'school_schedule_screen.dart';

/// Child home: menu with cards. Displays configured child info (read-only) when available.
class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.childHomeTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backToRoleSelect,
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const RoleSelectScreen(),
              ),
              (route) => false,
            );
          },
        ),
        actions: const [
          LanguageSwitcher(),
        ],
      ),
      body: FutureBuilder<ChildModel?>(
        future: ChildModel.load(),
        builder: (context, snapshot) {
          final child = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (child != null && (child.name.isNotEmpty || child.age > 0 || child.grade.isNotEmpty || child.schoolCode.isNotEmpty)) ...[
                _ChildInfoCard(model: child),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              _MenuCard(
                title: l10n.scheduleTomorrow,
                icon: Icons.calendar_today_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SchoolScheduleScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.blockedAppsAndTimes,
                icon: Icons.block_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlockedAppsTimesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.contentLibraryTitle,
                icon: Icons.menu_book_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const ContentLibraryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _ChildInfoCard extends StatelessWidget {
  const _ChildInfoCard({required this.model});
  final ChildModel model;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'פרטי משתמש',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'שם', value: model.name),
            _InfoRow(label: 'גיל', value: model.age > 0 ? model.age.toString() : ''),
            _InfoRow(label: 'כיתה', value: model.grade),
            _InfoRow(label: 'קוד בית ספר', value: model.schoolCode),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
