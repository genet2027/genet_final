import 'dart:io';

import 'package:flutter/services.dart';

/// Native VPN blackhole (Android): [MethodChannel] `genet/vpn`.
/// Call [setBlockedApps] before [startVpn]; use [refreshVpn] after list changes while VPN is on.
class GenetVpn {
  GenetVpn._();

  static const MethodChannel _channel = MethodChannel('genet/vpn');

  /// Dedupes concurrent [startVpn] calls so native is not invoked twice in parallel.
  static Future<Map<String, dynamic>?>? _inFlightStartVpn;

  /// Updates the in-memory blocked list used when establishing / restarting the VPN session.
  static Future<void> setBlockedApps(List<String> packageNames) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setBlockedApps', {
        'packages': packageNames,
      });
    } on PlatformException catch (_) {}
  }

  /// Returns `{ started: bool, needsPermission: bool }`.
  /// - If `needsPermission` is true, the VPN was **not** started; open the system screen, then call [startVpn] again after approval.
  /// - If `started` is true, the foreground service was asked to start the VPN.
  /// - If both are false, the VPN may already be running (see [isVpnRunning]) or start was skipped.
  static Future<Map<String, dynamic>?> startVpn() async {
    if (!Platform.isAndroid) return null;
    final existing = _inFlightStartVpn;
    if (existing != null) return existing;
    final future = _invokeStartVpnOnce();
    _inFlightStartVpn = future;
    try {
      return await future;
    } finally {
      _inFlightStartVpn = null;
    }
  }

  static Future<Map<String, dynamic>?> _invokeStartVpnOnce() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('startVpn');
      if (r is Map) {
        final m = Map<String, dynamic>.from(r);
        return {
          'started': m['started'] == true,
          'needsPermission': m['needsPermission'] == true,
        };
      }
      return null;
    } on PlatformException catch (_) {
      return null;
    }
  }

  static Future<void> stopVpn() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopVpn');
    } on PlatformException catch (_) {}
  }

  /// Optionally pass [packages] to update the list; if VPN is running, restarts it cleanly.
  static Future<void> refreshVpn({List<String>? packages}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('refreshVpn', {
        if (packages != null) 'packages': packages,
      });
    } on PlatformException catch (_) {}
  }

  static Future<bool> isVpnRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod<bool>('isVpnRunning');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// True if [VpnService.prepare] would not require user consent (already approved once).
  static Future<bool> isVpnPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _channel.invokeMethod<bool>('isVpnPermissionGranted');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
