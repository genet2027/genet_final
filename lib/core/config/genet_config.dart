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

      final enabled = prefs.getBool('genet_sleep_lock_enabled') ?? false;
      final start = prefs.getString('genet_sleep_lock_start') ?? '22:00';
      final end = prefs.getString('genet_sleep_lock_end') ?? '07:00';
      await setSleepLock(enabled: enabled, start: start, end: end);

      final blocked = prefs.getStringList('genet_blocked_packages') ?? [];
      await setBlockedApps(blocked);

      final permissionLock = prefs.getBool('genet_permission_lock_enabled') ?? false;
      await setPermissionLockEnabled(permissionLock);
    } on PlatformException catch (_) {}
  }

  static Future<void> setPermissionLockEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setPermissionLockEnabled', {'enabled': enabled});
    } on PlatformException catch (_) {}
  }

  static Future<bool> getPermissionLockEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod<bool>('getPermissionLockEnabled');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
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

  static Future<List<String>> getMissingPermissions() async {
    if (!Platform.isAndroid) return [];
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('getMissingPermissions');
      return (r ?? []).map((e) => e.toString()).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  static Future<void> setMaintenanceWindowEnd(int endMs) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMaintenanceWindowEnd', {'endMs': endMs});
    } on PlatformException catch (_) {}
  }

  /// Sync map of packageName -> untilMs (extension approved until) to native so blocked app is allowed until that time.
  static Future<void> setExtensionApproved(Map<String, int> packageToUntilMs) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setExtensionApproved', {'map': packageToUntilMs});
    } on PlatformException catch (_) {}
  }
}
