import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bootstrap/app_bootstrap.dart';
import 'debug_firebase_state.dart';
import 'core/config/genet_config.dart';
import 'core/user_role.dart';
import 'l10n/app_localizations.dart';
import 'repositories/children_repository.dart';
import 'repositories/parent_child_sync_repository.dart';
import 'providers/language_provider.dart';
import 'screens/permission_recovery_screen.dart';
import 'services/installed_apps_bridge.dart';
import 'services/json_translations.dart';
import 'services/night_mode_service.dart';
import 'theme/app_theme.dart';
import 'package:genet_final/screens/figma_login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GenetStartupGate());
}

/// Runs Firebase bootstrap before showing [GenetApp]; shows retry UI on failure.
class GenetStartupGate extends StatefulWidget {
  const GenetStartupGate({super.key});

  @override
  State<GenetStartupGate> createState() => _GenetStartupGateState();
}

class _GenetStartupGateState extends State<GenetStartupGate> {
  NightModeService? _nightModeService;
  bool _ready = false;
  bool _failed = false;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _runStartup();
  }

  Future<void> _runStartup() async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    try {
      await initializeAppBootstrap();
      final user = FirebaseAuth.instance.currentUser;
      debugPrint(
        '[GENET][MAIN] startup_user='
        '${user?.uid} '
        'anonymous=${user?.isAnonymous}',
      );
      if (kDebugMode) {
        debugFirebaseState();
      }
      await JsonTranslations.ensureLoaded();
      if (kDebugMode && Platform.isAndroid) {
        unawaited(InstalledAppsBridge.debugPrintSample());
      }
      await ensureDefaultChild();
      await clearChildLinkedPrefsIfSavedCanonicalInactive();
      GenetConfig.syncToNative();
      final nightModeService = NightModeService();
      nightModeService.load();
      if (!mounted) return;
      setState(() {
        _nightModeService = nightModeService;
        _ready = true;
        _failed = false;
      });
    } catch (e, st) {
      debugPrint('[GENET][BOOTSTRAP][ERROR] startup_failed: $e');
      debugPrint('[GENET][BOOTSTRAP][ERROR] $st');
      if (!mounted) return;
      setState(() {
        _ready = false;
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onRetry() {
    debugPrint('[GENET][BOOTSTRAP][RETRY]');
    _runStartup();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready && _nightModeService != null) {
      return GenetApp(nightModeService: _nightModeService!);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _failed
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'בעיה בחיבור לאינטרנט',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.darkBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _starting ? null : _onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            minimumSize: const Size(160, 48),
                          ),
                          child: _starting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('נסה שוב'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(color: AppTheme.primaryBlue),
            ),
          ),
        ),
      ),
    );
  }
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkPermissionRecovery(),
    );
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
        ChangeNotifierProvider<NightModeService>.value(
          value: widget.nightModeService,
        ),
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
            home: const FigmaLoginScreen(),
          );
        },
      ),
    );
  }
}
