import 'dart:io';

import 'package:flutter/foundation.dart';

import '../features/blocked_apps/blocked_package_matching.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import 'genet_vpn.dart';
import 'user_role.dart';

/// Applies remote VPN policy on the child device only (Firestore → local VPN).
/// Effective native list = [effectiveBlockedPackageIds] (fixed-catalog aliases) minus
/// active temporary approvals ([maxApprovedUntilMsForPackage] per package).
/// Pushed to native via [GenetVpn.setBlockedApps] (MethodChannel `genet/vpn`).
class VpnRemoteChildPolicy {
  VpnRemoteChildPolicy._();

  static String? _lastPushPolicyKey;
  static String? _lastNativeEffectiveKey;
  static String _lastReturnedApplyStatus = 'off';
  static Set<String> _lastEffectiveBlockedSet = {};
  static String? _lastPushedStatus;
  static String? _lastPushedMsg;

  /// Call when child unlinks so the next session can push status again.
  static void resetPushDedupe() {
    _lastPushPolicyKey = null;
    _lastNativeEffectiveKey = null;
    _lastReturnedApplyStatus = 'off';
    _lastEffectiveBlockedSet = {};
    _lastPushedStatus = null;
    _lastPushedMsg = null;
  }

  /// Effective packages for native VPN: fixed-catalog expansion + extension family windows
  /// (see [effectiveBlockedFromLists]).
  static List<String> effectiveBlockedPackages(
    SyncedChildData data, {
    int? currentTimeMs,
  }) {
    return effectiveBlockedFromLists(
      data.blockedPackages,
      data.extensionApproved,
      currentTimeMs: currentTimeMs,
    );
  }

  /// Same rule as [effectiveBlockedPackages]: catalog expansion + extension family window.
  /// Used by [GenetConfig.syncToNative] (Accessibility prefs path, `com.example.genet_final/config`).
  static List<String> effectiveBlockedFromLists(
    List<String> rawBlocked,
    Map<String, int> extensionApproved, {
    int? currentTimeMs,
  }) {
    final now = currentTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    final expanded = effectiveBlockedPackageIds(rawBlocked);
    final out = <String>[];
    for (final pkg in expanded) {
      if (maxApprovedUntilMsForPackage(pkg, extensionApproved) <= now) {
        out.add(pkg);
      }
    }
    out.sort();
    return out;
  }

  /// Returns UI/Firebase status: on | off | error
  static Future<String> apply(
    SyncedChildData data, {
    bool? overrideVpnEnabled,
    int? currentTimeMs,
  }) async {
    if (!Platform.isAndroid) return 'off';
    final role = await getUserRole();
    if (role != kUserRoleChild) return 'off';

    final pid = await getLinkedParentId();
    final cid = await getLinkedChildId();
    if (pid == null || pid.isEmpty || cid == null || cid.isEmpty) {
      debugPrint('[GenetVpn] child apply skipped: missing linked parentId or childId');
      return 'error';
    }

    final vpnEnabled = overrideVpnEnabled ?? data.vpnEnabled;
    final rawBlocked = data.blockedPackages;
    final expandedCatalog = effectiveBlockedPackageIds(rawBlocked);
    final effective =
        effectiveBlockedPackages(data, currentTimeMs: currentTimeMs);
    final effSorted = List<String>.from(effective)..sort();
    final rawKeyParts = List<String>.from(
      rawBlocked.map((s) => s.trim()).where((s) => s.isNotEmpty),
    )..sort();
    // Include raw in dedupe key so parent UNBLOCK (raw shrinks / clears) always re-pushes even when
    // effective stayed identical (e.g. empty both times, or same after expansion).
    final effKey = '$vpnEnabled|eff:${effSorted.join(',')}|raw:${rawKeyParts.join(',')}';

    if (effKey == _lastNativeEffectiveKey) {
      return _lastReturnedApplyStatus;
    }

    if (effKey != _lastPushPolicyKey) {
      _lastPushPolicyKey = effKey;
      _lastPushedStatus = null;
      _lastPushedMsg = null;
    }

    final now = currentTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    final newEffSet = effective.toSet();
    final prev = _lastEffectiveBlockedSet;
    debugPrint(
      '[GenetVpn] nativePush path=VpnRemoteChildPolicy.apply channel=genet/vpn '
      'rawBlocked=$rawBlocked expandedCatalog=$expandedCatalog effectiveNative=$effective '
      'prevNativeEffective=${(prev.toList()..sort()).join(',')}',
    );
    if (prev.isNotEmpty && (newEffSet.length < prev.length || newEffSet.isEmpty)) {
      debugPrint(
        '[GenetVpn] unblock-shrink after parent change: prevCount=${prev.length} newCount=${newEffSet.length} '
        'rawAfter=$rawKeyParts effAfter=$effSorted',
      );
    }
    for (final pkg in expandedCatalog) {
      final until = maxApprovedUntilMsForPackage(pkg, data.extensionApproved);
      if (until > now) {
        debugPrint(
          '[GenetVpn] extension window active package=$pkg expiresAt=${DateTime.fromMillisecondsSinceEpoch(until).toIso8601String()}',
        );
      }
    }
    for (final p in prev.difference(newEffSet)) {
      if (!expandedCatalog.contains(p)) continue;
      final until = maxApprovedUntilMsForPackage(p, data.extensionApproved);
      if (until > now) {
        debugPrint(
          '[GenetVpn] temporary unblock applied package=$p expiresAt=${DateTime.fromMillisecondsSinceEpoch(until).toIso8601String()}',
        );
      }
    }
    var extensionJustExpired = false;
    if (prev.isNotEmpty) {
      for (final p in newEffSet.difference(prev)) {
        // Firestore raw list only: avoids treating first-time catalog expansion as extension expiry.
        if (!rawBlocked.contains(p)) continue;
        extensionJustExpired = true;
        debugPrint('[GenetVpn] extension expired for package=$p (re-entered effective native set)');
      }
    }
    _lastEffectiveBlockedSet = Set<String>.from(newEffSet);

    Future<void> push(String status, [String? msg]) async {
      if (_lastPushedStatus == status && _lastPushedMsg == msg) {
        debugPrint('[GenetVpn] skipped duplicate vpnStatus write');
        return;
      }
      _lastPushedStatus = status;
      _lastPushedMsg = msg;
      await syncChildVpnStatusToFirebase(pid, cid, status, vpnStatusMessage: msg);
    }

    await GenetVpn.setBlockedApps(effective);
    if (effective.isEmpty) {
      debugPrint('[GenetVpn] nativePush apply: sent empty effectiveNative to genet/vpn (clear VPN block list)');
    }

    if (!vpnEnabled) {
      debugPrint('[GenetVpn] applying stopVpn now');
      await GenetVpn.stopVpn();
      debugPrint('[GenetVpn] child stopVpn triggered');
      await push('off');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'off';
      return 'off';
    }

    if (rawBlocked.isEmpty) {
      if (await GenetVpn.isVpnRunning()) {
        debugPrint('[GenetVpn] applying stopVpn now (empty blocked list)');
        await GenetVpn.stopVpn();
        debugPrint('[GenetVpn] child stopVpn triggered (empty blocked list)');
      }
      await push('error', 'empty_blocked');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'error';
      return 'error';
    }

    if (effective.isEmpty) {
      debugPrint('[GenetVpn] all blocked packages have active extension windows — VPN stays on, native block list empty');
      if (await GenetVpn.isVpnRunning()) {
        await GenetVpn.refreshVpn(packages: effective);
        debugPrint('[GenetVpn] vpn refreshed after extension apply (all packages in extension window)');
      } else {
        final granted = await GenetVpn.isVpnPermissionGranted();
        if (!granted) {
          await push('error', 'no_permission');
          _lastNativeEffectiveKey = effKey;
          _lastReturnedApplyStatus = 'error';
          return 'error';
        }
        debugPrint('[GenetVpn] applying startVpn now (all in extension; empty effective list)');
        final r = await GenetVpn.startVpn();
        if (r?['needsPermission'] == true) {
          await push('error', 'needs_approval');
          _lastNativeEffectiveKey = effKey;
          _lastReturnedApplyStatus = 'error';
          return 'error';
        }
      }
      await push('on');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'on';
      return 'on';
    }

    final granted = await GenetVpn.isVpnPermissionGranted();
    if (granted) {
      debugPrint('[GenetVpn] child permission granted');
    } else {
      debugPrint('[GenetVpn] child permission not granted');
    }
    if (!granted) {
      debugPrint('[GenetVpn] child startVpn skipped (no permission yet)');
      await push('error', 'no_permission');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'error';
      return 'error';
    }

    if (await GenetVpn.isVpnRunning()) {
      debugPrint('[GenetVpn] effective blockedApps changed -> refreshVpn');
      await GenetVpn.refreshVpn(packages: effective);
      debugPrint(
        extensionJustExpired
            ? '[GenetVpn] vpn refreshed after extension expiry'
            : '[GenetVpn] vpn refreshed after extension apply',
      );
      final on = await GenetVpn.isVpnRunning();
      if (on) {
        await push('on');
        _lastNativeEffectiveKey = effKey;
        _lastReturnedApplyStatus = 'on';
        return 'on';
      }
      await push('error', 'refresh_failed');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'error';
      return 'error';
    }

    if (!await GenetVpn.isVpnPermissionGranted()) {
      debugPrint('[GenetVpn] child startVpn skipped (no permission yet)');
      await push('error', 'no_permission');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'error';
      return 'error';
    }
    debugPrint('[GenetVpn] applying startVpn now');
    final r = await GenetVpn.startVpn();
    debugPrint('[GenetVpn] child startVpn triggered');
    if (r?['needsPermission'] == true) {
      await push('error', 'needs_approval');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'error';
      return 'error';
    }
    final on = await GenetVpn.isVpnRunning();
    if (on) {
      await push('on');
      _lastNativeEffectiveKey = effKey;
      _lastReturnedApplyStatus = 'on';
      return 'on';
    }
    await push('error', 'start_failed');
    _lastNativeEffectiveKey = effKey;
    _lastReturnedApplyStatus = 'error';
    return 'error';
  }
}
