import 'package:flutter/material.dart';

import '../core/auth_flow_helpers.dart';
import '../core/firebase_auth_guard.dart';
import '../theme/app_theme.dart';
import 'welcome_screen.dart';

/// App entry gate: auto-routes signed-in users, otherwise shows [WelcomeScreen].
class GenetAuthEntry extends StatefulWidget {
  const GenetAuthEntry({super.key});

  @override
  State<GenetAuthEntry> createState() => _GenetAuthEntryState();
}

class _GenetAuthEntryState extends State<GenetAuthEntry> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveInitialRoute());
  }

  Future<void> _resolveInitialRoute() async {
    if (!firebaseUserIsAuthenticated()) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    final user = await authFlowReloadCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() => _checking = false);
      return;
    }

    final isGoogleUser =
        user.providerData.any((provider) => provider.providerId == 'google.com');
    if (!user.emailVerified && !isGoogleUser) {
      await openEmailVerificationAuthScreen(context);
      return;
    }

    await routeAfterVerifiedLogin(context);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Color(0xFF050B18),
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryBlue),
          ),
        ),
      );
    }
    return const WelcomeScreen();
  }
}
