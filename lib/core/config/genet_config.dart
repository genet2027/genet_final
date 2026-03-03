import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Syncs parent config (PIN, Sleep Lock, blocked apps) to native Android storage
/// so the Accessibility Service can enforce locks.
class GenetConfig {
  /// Sync all config from Flutter prefs to native. Call on app startup.
  static Future<void> syncToNative() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pin = prefs.getString('genet_parent_pin') ?? '1234';
      await setPin(pin);

      final enabled = prefs.getBool('genet_sleep_lock_enabled') ?? false;
      final start = prefs.getString('genet_sleep_lock_start') ?? '22:00';
      final end = prefs.getString('genet_sleep_lock_end') ?? '07:00';
      await setSleepLock(enabled: enabled, start: start, end: end);

      final blocked = prefs.getStringList('genet_blocked_packages') ?? [];
      await setBlockedApps(blocked);
    } on PlatformException catch (_) {}
  }

  static const _channel = MethodChannel('com.example.genet_final/config');

  static Future<void> setPin(String pin) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setPin', {'pin': pin});
    } on PlatformException catch (_) {}
  }

  static Future<void> setSleepLock({
    required bool enabled,
    required String start,
    required String end,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSleepLock', {
        'enabled': enabled,
        'start': start,
        'end': end,
      });
    } on PlatformException catch (_) {}
  }

  static Future<void> setBlockedApps(List<String> packageNames) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBlockedApps', {'packages': packageNames});
    } on PlatformException catch (_) {}
  }

  static Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (_) {}
  }

  static Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } on PlatformException catch (_) {}
  }

  static Future<void> openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openOverlaySettings');
    } on PlatformException catch (_) {}
  }
}
