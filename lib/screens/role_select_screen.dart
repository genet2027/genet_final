import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import '../l10n/app_localizations.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import 'child_home_screen.dart';
import 'child_self_identify_screen.dart';
import 'pin_login_screen.dart';

/// מסך בחירת תפקיד: הורה או ילד. כניסה ראשית לאפליקציה.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  bool _childRouteBusy = false;

  Future<void> _onChildRoleTap(BuildContext context) async {
    if (_childRouteBusy) return;
    setState(() => _childRouteBusy = true);
    try {
      await GenetConfig.commitUserRole(kUserRoleChild);
      final linkedId = await getLinkedChildId();
      if (!mounted || !context.mounted) return;

      if (linkedId != null && linkedId.isNotEmpty) {
        final preflight = await preflightSavedChildCanonicalLink();
        if (!mounted || !context.mounted) return;
        switch (preflight) {
          case SavedChildLinkPreflightResult.verifiedConnected:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const ChildHomeScreen(),
              ),
            );
            return;
          case SavedChildLinkPreflightResult.verifiedInvalidOrStale:
            await clearChildLinkedPrefsKeepLocalIdentity();
            GenetConfig.syncToNative();
            if (!mounted || !context.mounted) return;
            final hasProfile = await hasChildSelfProfile();
            if (!mounted || !context.mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => hasProfile
                    ? const ChildHomeScreen()
                    : const ChildSelfIdentifyScreen(),
              ),
            );
            return;
          case SavedChildLinkPreflightResult.unverifiedTransient:
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const ChildHomeScreen(
                  canonicalStartupPreflightUnverified: true,
                ),
              ),
            );
            return;
        }
      }

      final hasProfile = await hasChildSelfProfile();
      if (!mounted || !context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => hasProfile
              ? const ChildHomeScreen()
              : const ChildSelfIdentifyScreen(),
        ),
      );
    } finally {
      if (mounted) setState(() => _childRouteBusy = false);
    }
  }

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
                    onPressed: _childRouteBusy ? null : () => _onChildRoleTap(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _childRouteBusy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ילד'),
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
