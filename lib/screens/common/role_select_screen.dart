import 'package:flutter/material.dart';

import '../../core/config/genet_config.dart';
import '../../core/user_role.dart';
import '../../l10n/app_localizations.dart';
import '../../repositories/children_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/language_switcher.dart';
import '../child_home_screen.dart';
import '../child/child_self_identify_screen.dart';
import 'pin_login_screen.dart';

/// מסך בחירת תפקיד: הורה או ילד. כניסה ראשית לאפליקציה.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryBlue, AppTheme.darkBlue],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 60),
                const Text(
                  'Genet',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'בחר תפקיד',
                  style: TextStyle(fontSize: 20, color: Colors.white70),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await GenetConfig.commitUserRole(kUserRoleParent);
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PinLoginScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text('הורה'),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                    child: OutlinedButton(
                    onPressed: () async {
                      await GenetConfig.commitUserRole(kUserRoleChild);
                      final linkedId = await getLinkedChildId();
                      if (linkedId != null && linkedId.isNotEmpty) {
                        if (!context.mounted) return;
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChildHomeScreen(),
                          ),
                        );
                        return;
                      }
                      final hasProfile = await hasChildSelfProfile();
                      if (!context.mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => hasProfile
                              ? const ChildHomeScreen()
                              : const ChildSelfIdentifyScreen(),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text('ילד'),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => LanguageSwitcher.showPicker(context),
        tooltip: AppLocalizations.of(context)!.buttonSelectLanguage,
        child: const Icon(Icons.language),
      ),
    );
  }
}
