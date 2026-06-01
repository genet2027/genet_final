import 'package:flutter/material.dart';

import '../screens/child_home_screen.dart';
import '../screens/parent_shell.dart';
import '../screens/welcome_screen.dart';

/// Pops when possible; otherwise replaces stack with [fallback] to avoid black screens.
void safeBackOrNavigate(
  BuildContext context, {
  required String fromScreen,
  required Widget fallback,
  Object? popResult,
}) {
  debugPrint('[GENET][NAV] back tapped from $fromScreen');
  if (Navigator.canPop(context)) {
    debugPrint('[GENET][NAV] pop used');
    if (popResult != null) {
      Navigator.pop(context, popResult);
    } else {
      Navigator.pop(context);
    }
    return;
  }
  debugPrint('[GENET][NAV] fallback used: ${fallback.runtimeType}');
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute<void>(builder: (_) => fallback),
    (route) => false,
  );
}

void safeBackToWelcome(BuildContext context, String fromScreen) {
  safeBackOrNavigate(
    context,
    fromScreen: fromScreen,
    fallback: const WelcomeScreen(),
  );
}

void safeBackToParentShell(BuildContext context, String fromScreen) {
  safeBackOrNavigate(
    context,
    fromScreen: fromScreen,
    fallback: const ParentShell(),
  );
}

void safeBackToChildHome(BuildContext context, String fromScreen) {
  safeBackOrNavigate(
    context,
    fromScreen: fromScreen,
    fallback: const ChildHomeScreen(),
  );
}
