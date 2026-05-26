import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../core/firebase_auth_guard.dart';
import '../core/user_role.dart';
import '../l10n/app_localizations.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import 'auth_screen.dart';
import 'child_home_screen.dart';
import 'child_link_screen.dart';
import 'child_self_identify_screen.dart';
import 'parent_shell.dart';

/// מסך בחירת תפקיד: הורה או ילד. כניסה ראשית לאפליקציה.
class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  bool _childRouteBusy = false;
  bool _parentRouteBusy = false;

  Future<void> _onParentRoleTap(BuildContext context) async {
    if (_parentRouteBusy) return;
    setState(() => _parentRouteBusy = true);
    try {
      debugPrint('[GENET][ONBOARDING_FLOW] selectedRole=parent');
      await GenetConfig.commitUserRole(kUserRoleParent);
      if (!mounted || !context.mounted) return;

      if (firebaseUserIsAuthenticated()) {
        final parentId = await getOrCreateParentId();
        final profile = await getParentProfile(parentId);
        if (!mounted || !context.mounted) return;
        final hasCompletedProfile = isParentProfileComplete(profile);
        debugPrint(
          '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasCompletedProfile',
        );
        if (hasCompletedProfile) {
          debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentShell');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ParentShell()),
          );
          return;
        }
      }

      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=AuthScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(role: kUserRoleParent),
        ),
      );
    } finally {
      if (mounted) setState(() => _parentRouteBusy = false);
    }
  }

  Future<void> _onChildRoleTap(BuildContext context) async {
    if (_childRouteBusy) return;
    setState(() => _childRouteBusy = true);
    try {
      debugPrint('[GENET][ONBOARDING_FLOW] selectedRole=child');
      await GenetConfig.commitUserRole(kUserRoleChild);
      if (!mounted || !context.mounted) return;

      final verified = await hasVerifiedChildCanonicalConnection();
      if (!mounted || !context.mounted) return;

      if (verified) {
        debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=true');
        debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildHomeScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ChildHomeScreen(),
          ),
        );
        return;
      }

      if (firebaseUserIsAuthenticated()) {
        final hasProfile = await hasChildSelfProfile();
        if (!mounted || !context.mounted) return;
        debugPrint(
          '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasProfile',
        );
        if (hasProfile) {
          debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildLinkScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const ChildLinkScreen(),
            ),
          );
          return;
        }
        debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildSelfIdentifyScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ChildSelfIdentifyScreen(),
          ),
        );
        return;
      }

      debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=false');
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=AuthScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(role: kUserRoleChild),
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
                    onPressed: _parentRouteBusy
                        ? null
                        : () => _onParentRoleTap(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: _parentRouteBusy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryBlue,
                            ),
                          )
                        : const Text('הורה'),
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
