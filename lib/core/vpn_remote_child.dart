import 'dart:io';

import 'package:flutter/foundation.dart';

import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import 'genet_vpn.dart';
import 'user_role.dart';

/// Applies remote VPN policy on the child device only (Firestore → local VPN).
/// Uses [SyncedChildData.blockedPackages] minus packages with active extension
/// ([SyncedChildData.extensionApproved][pkg] > now) as the effective block list for the VPN.
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

  /// Effective packages to pass to native VPN: blocked list minus active temporary approvals.
  static List<String> effectiveBlockedPackages(SyncedChildData data) {
    return effectiveBlockedFromLists(data.blockedPackages, data.extensionApproved);
  }

  /// Same rule as [effectiveBlockedPackages] for prefs-only sync (e.g. [GenetConfig.syncToNative]).
  static List<String> effectiveBlockedFromLists(
    List<String> rawBlocked,
    Map<String, int> extensionApproved,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <String>[];
    for (final pkg in rawBlocked) {
      final until = extensionApproved[pkg] ?? 0;
      if (until > now) {
        continue;
      }
      out.add(pkg);
    }
    return out;
  }

  /// Returns UI/Firebase status: on | off | error
  static Future<String> apply(
    SyncedChildData data, {
    bool? overrideVpnEnabled,
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
    final effective = effectiveBlockedPackages(data);
    final effSorted = List<String>.from(effective)..sort();
    final effKey = '$vpnEnabled|${effSorted.join(',')}';

    if (effKey == _lastNativeEffectiveKey) {
      return _lastReturnedApplyStatus;
    }

    if (effKey != _lastPushPolicyKey) {
      _lastPushPolicyKey = effKey;
      _lastPushedStatus = null;
      _lastPushedMsg = null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final newEffSet = effective.toSet();
    final prev = _lastEffectiveBlockedSet;
    for (final pkg in rawBlocked) {
      final until = data.extensionApproved[pkg] ?? 0;
      if (until > now) {
        debugPrint(
          '[GenetVpn] extension approved for package=$pkg expiresAt=${DateTime.fromMillisecondsSinceEpoch(until).toIso8601String()}',
        );
      }
    }
    for (final p in prev.difference(newEffSet)) {
      if (!rawBlocked.contains(p)) continue;
      final until = data.extensionApproved[p] ?? 0;
      if (until > now) {
        debugPrint(
          '[GenetVpn] temporary unblock applied for package=$p expiresAt=${DateTime.fromMillisecondsSinceEpoch(until).toIso8601String()}',
        );
      }
    }
    var extensionJustExpired = false;
    if (prev.isNotEmpty) {
      for (final p in newEffSet.difference(prev)) {
        if (rawBlocked.contains(p)) {
          extensionJustExpired = true;
          debugPrint('[GenetVpn] extension expired for package=$p');
          debugPrint('[GenetVpn] package re-blocked: $p');
        }
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

    debugPrint('[GenetVpn] child raw blockedApps: $rawBlocked');
    debugPrint('[GenetVpn] child effective blockedApps for VPN: $effective');

    await GenetVpn.setBlockedApps(effective);

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
