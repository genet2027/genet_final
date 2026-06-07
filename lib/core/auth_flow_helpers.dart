import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repositories/child_profile_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import '../screens/auth_screen.dart';
import '../screens/child_home_screen.dart';
import '../screens/child_link_screen.dart';
import '../screens/child_self_identify_screen.dart';
import '../screens/parent_profile_setup_screen.dart';
import '../screens/parent_shell.dart';
import '../screens/welcome_screen.dart';
import 'config/genet_config.dart';
import 'user_role.dart';

String authFlowHebrewPasswordResetError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'כתובת האימייל אינה תקינה.';
    case 'user-not-found':
      return 'לא נמצא חשבון עם אימייל זה.';
    case 'network-request-failed':
      return 'בעיית רשת. בדוק את החיבור לאינטרנט.';
    case 'too-many-requests':
      return 'יותר מדי ניסיונות. נסה שוב מאוחר יותר.';
    default:
      return 'לא ניתן לשלוח קישור לאיפוס סיסמה. נסה שוב.';
  }
}

String authFlowHebrewAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'כתובת האימייל אינה תקינה.';
    case 'user-disabled':
      return 'החשבון הושבת.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'אימייל או סיסמה שגויים.';
    case 'email-already-in-use':
      return 'כתובת האימייל כבר בשימוש.';
    case 'weak-password':
      return 'הסיסמה חלשה מדי. בחר סיסמה ארוכה יותר.';
    case 'network-request-failed':
      return 'בעיית רשת. בדוק את החיבור לאינטרנט.';
    case 'account-exists-with-different-credential':
      return 'כבר קיים חשבון עם אימייל זה. התחבר בשיטה המקורית.';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return 'ההתחברות עם Google בוטלה.';
    default:
      return 'שגיאת התחברות. נסה שוב.';
  }
}

Future<User?> authFlowReloadCurrentUser() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  await user.reload();
  return FirebaseAuth.instance.currentUser;
}

Future<void> completePostAuthNavigation(
  BuildContext context, {
  required String role,
  required bool isLoginMode,
  VoidCallback? onAuthenticated,
  bool popOnSuccess = false,
}) async {
  debugPrint(
    '[GENET][ONBOARDING_FLOW] isLoginMode=${isLoginMode ? "loginMode" : "registerMode"}',
  );
  await GenetConfig.commitUserRole(role);
  if (!context.mounted) return;
  if (onAuthenticated != null) {
    onAuthenticated();
    Navigator.pop(context, true);
    return;
  }
  if (popOnSuccess && Navigator.of(context).canPop()) {
    debugPrint('[GENET][AUTH_ROUTE] pop used (modal auth return)');
    Navigator.pop(context, true);
    return;
  }

  void go(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
      (route) => false,
    );
  }

  Future<void> routeChildOnboarding() async {
    final verified = await hasVerifiedChildCanonicalConnection();
    if (!context.mounted) return;
    if (verified) {
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildHomeScreen');
      go(const ChildHomeScreen());
      return;
    }

    final hasProfile = await isChildProfileComplete();
    if (!context.mounted) return;
    debugPrint(
      '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasProfile',
    );
    if (!hasProfile) {
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildSelfIdentifyScreen');
      go(const ChildSelfIdentifyScreen());
      return;
    }

    debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ChildLinkScreen');
    go(const ChildLinkScreen());
  }

  if (role == kUserRoleParent) {
    debugPrint('[GENET][AUTH_ROUTE] navigating parent flow');
    if (isLoginMode) {
      final parentId = await getOrCreateParentId();
      final profile = await getParentProfile(parentId);
      if (!context.mounted) return;
      final hasCompletedProfile = isParentProfileComplete(profile);
      debugPrint(
        '[GENET][ONBOARDING_FLOW] hasCompletedProfile=$hasCompletedProfile',
      );
      if (hasCompletedProfile) {
        debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentShell');
        go(const ParentShell());
        return;
      }
      debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentProfileSetupScreen');
      go(
        ParentProfileSetupScreen(
          completedBuilder: (_) => const ParentShell(),
        ),
      );
      return;
    }
    debugPrint('[GENET][ONBOARDING_FLOW] hasCompletedProfile=false');
    debugPrint('[GENET][ONBOARDING_FLOW] nextRoute=ParentShell');
    go(const ParentShell());
    return;
  }
  if (role == kUserRoleChild) {
    debugPrint('[GENET][AUTH_ROUTE] navigating child flow');
    await routeChildOnboarding();
    return;
  }
}

Future<void> routeAfterVerifiedLogin(
  BuildContext context, {
  bool popOnSuccess = false,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  debugPrint('[GENET][AUTH_ROUTE] auth success');
  debugPrint('[GENET][AUTH_ROUTE] currentUser uid: ${user?.uid}');
  final role = await getUserRole();
  debugPrint('[GENET][AUTH_ROUTE] saved role: $role');
  if (!context.mounted) return;
  if (role == null) {
    debugPrint('[GENET][AUTH_ROUTE] missing role, fallback welcome');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
    return;
  }
  await completePostAuthNavigation(
    context,
    role: role,
    isLoginMode: true,
    popOnSuccess: popOnSuccess,
  );
}

Future<void> openEmailVerificationAuthScreen(BuildContext context) async {
  final role = await getUserRole() ?? kUserRoleParent;
  if (!context.mounted) return;
  Navigator.pushReplacement(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AuthScreen(role: role),
    ),
  );
}
