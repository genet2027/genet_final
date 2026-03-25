import 'package:flutter/material.dart';

enum NetworkProtectionBlockReason { vpn, sleep, other }

String networkProtectionBlockReasonLabel(
  NetworkProtectionBlockReason reason,
) {
  switch (reason) {
    case NetworkProtectionBlockReason.vpn:
      return 'vpn';
    case NetworkProtectionBlockReason.sleep:
      return 'sleep';
    case NetworkProtectionBlockReason.other:
      return 'other';
  }
}

Widget showNetworkProtectionScreen({
  Key? key,
  required NetworkProtectionBlockReason reason,
  required VoidCallback onOpenContentLibrary,
  VoidCallback? onActivateProtection,
  String? message,
}) {
  return NetworkProtectionRequiredScreen(
    key: key,
    reason: reason,
    onOpenContentLibrary: onOpenContentLibrary,
    onActivateProtection: onActivateProtection,
    message: message,
  );
}

/// Unified full-screen block UI for VPN, sleep-lock, and enforced restrictions.
class NetworkProtectionRequiredScreen extends StatelessWidget {
  const NetworkProtectionRequiredScreen({
    super.key,
    required this.reason,
    required this.onOpenContentLibrary,
    this.onActivateProtection,
    this.message,
  });

  final NetworkProtectionBlockReason reason;
  final VoidCallback onOpenContentLibrary;
  final VoidCallback? onActivateProtection;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final bodyMessage =
        message ??
        (reason == NetworkProtectionBlockReason.sleep
            ? 'הגישה מוגבלת כרגע עקב שעות שימוש. ניתן להיכנס רק לספריית התכנים.'
            : 'כדי להמשיך להשתמש ב-Genet יש להפעיל מחדש את הגנת הרשת.');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A237E),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 72,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Network Protection Required',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 32),
                  Text(
                    bodyMessage,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (onActivateProtection != null) ...[
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: onActivateProtection,
                      child: const Text('Activate Protection'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onOpenContentLibrary,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    child: const Text('כניסה לספריית תכנים'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
