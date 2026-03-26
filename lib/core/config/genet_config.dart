import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/children_repository.dart';
import '../user_role.dart';
import '../vpn_remote_child.dart';

/// Syncs parent config (PIN, Sleep Lock, blocked apps) to native Android storage
/// so the Accessibility Service can enforce locks.
class GenetConfig {
  static const _channel = MethodChannel('com.example.genet_final/config');
  static const _installedAppsEventsChannel =
      EventChannel('com.example.genet_final/installed_apps_events');

  /// Persists [kUserRoleParent] / [kUserRoleChild] and sets native child mode in one step.
  static Future<void> commitUserRole(String role) async {
    await setUserRole(role);
    await setChildMode(role == kUserRoleChild);
  }

  /// Applies native [setChildMode] from saved role. Unknown / missing role → parent (no enforcement).
  static Future<void> applyNativeChildModeFromSavedRole() async {
    if (!Platform.isAndroid) return;
    final role = await getUserRole();
    final isChild = role == kUserRoleChild;
    await setChildMode(isChild);
  }

  /// Call after a Firestore snapshot for the linked child is merged into local prefs
  /// ([watchChildDocStream] on the child device only — not on parent UI streams).
  /// Pushes blocked apps / extension approvals / sleep lock to Android so remote parent changes enforce on this device.
  /// No-op when [getUserRole] is not [kUserRoleChild] (parent emulator never applies child policy natively).
  static Future<void> syncToNativeAfterRemoteChildDoc() async {
    if (!Platform.isAndroid) return;
    final role = await getUserRole();
    if (role != kUserRoleChild) return;
    await syncToNative();
  }

  /// Sync all config from Flutter prefs to native. Call on app startup.
  /// When this device is linked to a child, blocked apps and extension approved
  /// are taken from that child's data.
  /// Native enforcement only when saved role is child.
  static Future<void> syncToNative() async {
    if (!Platform.isAndroid) return;
    await applyNativeChildModeFromSavedRole();
    try {
      final prefs = await SharedPreferences.getInstance();

      final enabled = prefs.getBool('genet_sleep_lock_enabled') ?? false;
      final start = prefs.getString('genet_sleep_lock_start') ?? '22:00';
      final end = prefs.getString('genet_sleep_lock_end') ?? '07:00';
      await setSleepLock(enabled: enabled, start: start, end: end);

      List<String> blocked;
      Map<String, int> extensionApproved;
      final linkedChildId = await getLinkedChildId();
      if (linkedChildId != null && linkedChildId.isNotEmpty) {
        blocked = await getBlockedPackagesForChild(linkedChildId);
        extensionApproved = await getExtensionApprovedForChild(linkedChildId);
      } else {
        blocked = prefs.getStringList('genet_blocked_packages') ?? [];
        final raw = prefs.getString('genet_extension_approved_until');
        extensionApproved = raw != null && raw.isNotEmpty
            ? _decodeExtensionApproved(raw) ?? {}
            : {};
      }
      final effective =
          VpnRemoteChildPolicy.effectiveBlockedFromLists(blocked, extensionApproved);
      await setBlockedApps(effective);
      await setExtensionApproved(extensionApproved);

      final permissionLock = prefs.getBool('genet_permission_lock_enabled') ?? false;
      await setPermissionLockEnabled(permissionLock);
    } on PlatformException catch (_) {}
  }

  static Map<String, int>? _decodeExtensionApproved(String raw) {
    try {
      if (raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return null;
    }
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

  static Future<void> setVpnProtectionLost(bool lost) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVpnProtectionLost', {'lost': lost});
    } on PlatformException catch (_) {}
  }

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

  static Future<void> setNightModeActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setNightModeActive', {
        'active': active,
      });
    } on PlatformException catch (_) {}
  }

  static Future<void> setBlockedApps(List<String> packageNames) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBlockedApps', {'packages': packageNames});
    } on PlatformException catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw == null) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  static Stream<Map<String, dynamic>> watchInstalledAppsChanges() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _installedAppsEventsChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    }).where((event) {
      return (event['action'] as String?)?.isNotEmpty == true &&
          (event['package'] as String?)?.isNotEmpty == true;
    }).handleError((Object error, StackTrace stackTrace) {
      debugPrint('[GenetApps] installed apps stream error: $error');
    });
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

  /// Set child mode (true) or parent mode (false). Blocking runs only when in child mode.
  static Future<void> setChildMode(bool isChildMode) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setChildMode', {'isChildMode': isChildMode});
    } on PlatformException catch (_) {}
  }

  /// Opens the system screen to enable Genet as Device Admin.
  static Future<void> enableDeviceAdmin() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('enableDeviceAdmin');
    } on PlatformException catch (_) {}
  }

  static Future<bool> getIsDeviceAdminEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod<bool>('getIsDeviceAdminEnabled');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } on PlatformException catch (_) {}
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final r = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return r ?? true;
    } on PlatformException catch (_) {
      return true;
    }
  }

  static Future<int?> getElapsedRealtimeMs() async {
    if (!Platform.isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<int>('getElapsedRealtimeMs');
      return r;
    } on PlatformException catch (_) {
      return null;
    }
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

  /// Called when app is brought to foreground after native requested permission recovery (blocked app opened, permissions missing). Returns true once then clears.
  static Future<bool> shouldShowPermissionRecovery() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod<bool>('shouldShowPermissionRecovery');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<void> setMaintenanceWindowEnd(int endMs) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMaintenanceWindowEnd', {'endMs': endMs});
    } on PlatformException catch (_) {}
  }

  /// Current app package name (Genet). Used so Genet is never added to blocked list.
  static Future<String> getPackageName() async {
    if (!Platform.isAndroid) return '';
    try {
      final r = await _channel.invokeMethod<String>('getPackageName');
      return r ?? '';
    } on PlatformException catch (_) {
      return '';
    }
  }

  /// Sync map of packageName -> untilMs (extension approved until) to native so blocked app is allowed until that time.
  static Future<void> setExtensionApproved(Map<String, int> packageToUntilMs) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setExtensionApproved', {'map': packageToUntilMs});
    } on PlatformException catch (_) {}
  }
}
