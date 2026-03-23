import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/genet_config.dart';
import '../../core/user_role.dart';
import '../../repositories/parent_child_sync_repository.dart';
import '../../theme/app_theme.dart';
import '../common/settings_screen.dart';
import 'parent_dashboard_tab.dart';
import 'reports_tab.dart';
import '../required_permissions_screen.dart';

/// Parent-only shell with BottomNavigationBar: Dashboard | Reports | Settings.
class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _showingRequiredPermissions = false;
  Timer? _permissionCheckTimer;

  @override
  void initState() {
    super.initState();
    GenetConfig.commitUserRole(kUserRoleParent);
    getOrCreateParentId();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndShowIfNeeded();
    _permissionCheckTimer = Timer.periodic(const Duration(seconds: 45), (_) => _checkPermissionsAndShowIfNeeded());
  }

  @override
  void dispose() {
    _permissionCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissionsAndShowIfNeeded();
  }

  Future<void> _checkPermissionsAndShowIfNeeded() async {
    if (_showingRequiredPermissions || !mounted) return;
    final missing = await GenetConfig.getMissingPermissions();
    if (!mounted) return;
    final missingForMainFlow = missing.where((e) => e != 'accessibility').toList();
    if (missingForMainFlow.isEmpty) return;
    setState(() => _showingRequiredPermissions = true);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RequiredPermissionsScreen(
          onDismiss: () => setState(() => _showingRequiredPermissions = false),
        ),
      ),
    );
    if (mounted) setState(() => _showingRequiredPermissions = false);
  }

  static const List<_TabInfo> _tabs = [
    _TabInfo(icon: Icons.dashboard_rounded, label: 'הורה'),
    _TabInfo(icon: Icons.chat_rounded, label: 'דיווחים'),
    _TabInfo(icon: Icons.settings_rounded, label: 'הגדרות'),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('הורה'), elevation: 0),
        body: IndexedStack(
          index: _selectedIndex,
          children: const [
            ParentDashboardTab(),
            ReportsTab(),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _tabs.length,
                  (i) => _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    selected: _selectedIndex == i,
                    onTap: () => setState(() => _selectedIndex = i),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: selected ? AppTheme.primaryBlue : Colors.grey.shade600,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.primaryBlue : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
