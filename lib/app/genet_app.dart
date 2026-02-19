import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/ui/role_selection_screen.dart';
import '../features/child/ui/child_home_screen.dart';
import '../features/parent/ui/blocked_apps_screen.dart';
import '../features/parent/ui/parent_panel_screen.dart';
import '../features/parent/ui/parent_pin_screen.dart';
import '../features/parent/ui/security_settings_screen.dart';
import '../features/parent/ui/sleep_lock_screen.dart';

class GenetApp extends StatelessWidget {
  const GenetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GENET',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: RoleSelectionScreen.routeName,
      routes: {
        RoleSelectionScreen.routeName: (_) => const RoleSelectionScreen(),
        ChildHomeScreen.routeName: (_) => const ChildHomeScreen(),
        ParentPinScreen.routeName: (_) => const ParentPinScreen(),
        ParentPanelScreen.routeName: (_) => const ParentPanelScreen(),
        SleepLockScreen.routeName: (_) => const SleepLockScreen(),
        BlockedAppsScreen.routeName: (_) => const BlockedAppsScreen(),
        SecuritySettingsScreen.routeName: (_) => const SecuritySettingsScreen(),
      },
    );
  }
}

