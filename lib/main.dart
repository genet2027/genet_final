import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/genet_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/language_provider.dart';
import 'screens/role_select_screen.dart';
import 'services/json_translations.dart';
import 'services/night_mode_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JsonTranslations.ensureLoaded();
  GenetConfig.syncToNative();
  final nightModeService = NightModeService();
  nightModeService.load();
  runApp(GenetApp(nightModeService: nightModeService));
}

/// Role Selection Screen (Parent/Child) is the permanent initial route (home).
/// Content Library is not a main screen; Parent Dashboard is reached after PIN login.
class GenetApp extends StatelessWidget {
  const GenetApp({super.key, required this.nightModeService});
  final NightModeService nightModeService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NightModeService>.value(value: nightModeService),
        ChangeNotifierProvider<LanguageProvider>(
          create: (_) => LanguageProvider(),
        ),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return MaterialApp(
            title: 'Genet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            locale: languageProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: RoleSelectScreen(),
          );
        },
      ),
    );
  }
}
