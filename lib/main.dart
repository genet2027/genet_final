import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/genet_config.dart';
import 'core/user_role.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'repositories/children_repository.dart';
import 'providers/language_provider.dart';
import 'screens/permission_recovery_screen.dart';
import 'screens/role_select_screen.dart';
import 'services/installed_apps_bridge.dart';
import 'services/json_translations.dart';
import 'services/night_mode_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await JsonTranslations.ensureLoaded();
  // Step 1 temporary: full installed-apps bridge dump (remove or gate when done verifying).
  if (kDebugMode && Platform.isAndroid) {
    unawaited(InstalledAppsBridge.debugPrintSample());
  }
  await ensureDefaultChild();
  GenetConfig.syncToNative();
  final nightModeService = NightModeService();
  nightModeService.load();
  runApp(GenetApp(nightModeService: nightModeService));
}

/// Role Selection Screen (Parent/Child) is the permanent initial route (home).
/// Content Library is not a main screen; Parent Dashboard is reached after PIN login.
class GenetApp extends StatefulWidget {
  const GenetApp({super.key, required this.nightModeService});
  final NightModeService nightModeService;

  @override
  State<GenetApp> createState() => _GenetAppState();
}

class _GenetAppState extends State<GenetApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissionRecovery());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    GenetConfig.applyNativeChildModeFromSavedRole();
    // Child device: re-push Firestore-backed prefs to native after backgrounding.
    GenetConfig.syncToNativeAfterRemoteChildDoc();
    _checkPermissionRecovery();
  }

  Future<void> _checkPermissionRecovery() async {
    final role = await getUserRole();
    if (role != kUserRoleChild) return;
    final show = await GenetConfig.shouldShowPermissionRecovery();
    if (!show || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.push<void>(
        MaterialPageRoute(builder: (_) => const PermissionRecoveryScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NightModeService>.value(value: widget.nightModeService),
        ChangeNotifierProvider<LanguageProvider>(
          create: (_) => LanguageProvider(),
        ),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'Genet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: languageProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: RoleSelectScreen(),
          );
        },
      ),
    );
  }
}
