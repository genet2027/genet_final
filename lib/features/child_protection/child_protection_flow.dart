import 'dart:async';

import 'package:flutter/material.dart';

import '../behavior/enums/behavior_event_type.dart';
import '../blocked_apps/blocked_package_matching.dart';
import '../../repositories/parent_child_sync_repository.dart';
import 'child_protection_models.dart';

/// Active child protection coordinator: evaluate → apply, periodic refresh hook, disconnect reset.
///
/// Owns dedupe fingerprint and last-applied state only. Does not own timers, listeners, or [BuildContext].
///
/// **Trigger ownership (who calls into this flow)** — see also `ChildHomeScreen` doc:
/// - [evaluate] + [apply]: only from [ChildHomeScreen.build] (each frame when mounted).
/// - [scheduleBlockingStateSync]: timers + post-frame callback + Firebase blocked-list delta
///   (screen calls `_syncBlockingState` → this method). Does **not** call evaluate/apply; it runs
///   native sleep/VPN policy via the screen’s `handleSleepLockState` callback.
/// - [resetAfterDisconnect]: parent disconnect path before clearing screen-owned prefs/state.
///
/// **Not duplicated here:** [VpnRemoteChildPolicy.apply] on the child device is native policy push;
/// it is separate from this UI-layer evaluate/apply state machine.
class ChildProtectionFlow {
  ChildProtectionFlow({required this.logCritical});

  final void Function(String scope, Map<String, Object?> fields) logCritical;

  String? _lastBlockingStateFingerprint;
  ChildProtectionState? _lastAppliedChildProtectionState;

  /// Clears evaluate log dedupe + apply transition dedupe only. Screen-owned fields (VPN snapshot,
  /// sleep flags, `_lastSyncedForVpn`, etc.) are reset separately in [ChildHomeScreen].
  void resetAfterDisconnect() {
    _lastBlockingStateFingerprint = null;
    _lastAppliedChildProtectionState = null;
  }

  @visibleForTesting
  String? get debugBlockingFingerprintForTest => _lastBlockingStateFingerprint;

  @visibleForTesting
  ChildProtectionState? get debugLastAppliedStateForTest => _lastAppliedChildProtectionState;

  static String _formatCurrentTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  static List<String> _normalizeBlockedApps(List<String> blockedApps) {
    final clean = <String>{};
    for (final packageName in blockedApps) {
      final normalized = normalizeIdentifier(packageName);
      if (normalized == null) continue;
      clean.add(normalized);
    }
    final list = clean.toList()..sort();
    return list;
  }

  static String? _normalizeForegroundApp(String? packageName) {
    return normalizeIdentifier(packageName);
  }

  static bool _isValidProtectionState(ChildProtectionState state) {
    return ChildProtectionState.values.contains(state);
  }

  /// Decides [ChildProtectionState] from [ctx]. Updates [_lastBlockingStateFingerprint] when the
  /// fingerprint changes; repeated **identical** fingerprints return immediately **without** re-emitting
  /// the verbose `GenetProtect`/`GenetTime` logs (build may call this every frame).
  ChildProtectionState evaluate(ChildProtectionEvaluationContext ctx) {
    final i = ctx.inputs;
    final sortedBlockedApps = _normalizeBlockedApps(i.blockedApps);
    final normalizedForegroundApp = _normalizeForegroundApp(ctx.currentForegroundApp);
    final fingerprint =
        '${ctx.vpnProtectionStatusLabel ?? 'unknown'}|${i.sleepLockActive}|${i.isVpnActive}|${i.requireNetworkProtectionScreen}|${i.networkProtectionRelevant}|${ctx.timeTamperingDetected}|${sortedBlockedApps.join(",")}|${ctx.currentForegroundApp ?? ''}|${i.protectionTime.hour}:${i.protectionTime.minute}';
    late final ChildProtectionState state;
    if (ctx.timeTamperingDetected) {
      state = ChildProtectionState.timeTampered;
    } else if (i.sleepLockActive) {
      state = ChildProtectionState.sleepLock;
    } else if (isPackageBlockedByRawList(ctx.currentForegroundApp, i.blockedApps)) {
      state = ChildProtectionState.appBlocked;
    } else if (i.requireNetworkProtectionScreen && i.networkProtectionRelevant) {
      state = ChildProtectionState.vpnRequired;
    } else {
      state = ChildProtectionState.free;
    }
    if (_lastBlockingStateFingerprint == fingerprint) return state;
    _lastBlockingStateFingerprint = fingerprint;
    if (!_isValidProtectionState(state)) {
      logCritical('GenetProtect', {
        'VALIDATION': 'invalid protection state',
        'PROTECTION STATE': state,
      });
      return ChildProtectionState.free;
    }
    logCritical('GenetTime', {
      'TIME TAMPERING': ctx.timeTamperingDetected,
      'TAMPERING REASON': ctx.timeTamperingReason ?? 'none',
    });
    logCritical('GenetProtect', {
      'SLEEP LOCK': i.sleepLockActive,
      'VPN ACTIVE': i.isVpnActive,
      'BLOCKED APPS COUNT': sortedBlockedApps.length,
      'CURRENT FOREGROUND APP': normalizedForegroundApp ?? '',
      'CURRENT TIME': _formatCurrentTime(i.protectionTime),
      'REQUIRE NETWORK SCREEN': i.requireNetworkProtectionScreen,
      'NETWORK WARNING RELEVANT': i.networkProtectionRelevant,
    });
    if (state == ChildProtectionState.vpnRequired) {
      logCritical('GenetProtect', {
        'NETWORK WARNING': 'shown',
        'REASON': 'toggle=true and condition relevant',
      });
    } else {
      logCritical('GenetProtect', {
        'NETWORK WARNING': 'skipped',
        'REASON':
            'toggle=${i.requireNetworkProtectionScreen} relevant=${i.networkProtectionRelevant}',
      });
    }
    logCritical('GenetProtect', {
      'PROTECTION STATE': state,
    });
    return state;
  }

  /// Runs side effects for [state]. [_lastAppliedChildProtectionState] gates one-shot work: sleep /
  /// vpnRequired / timeTampered behavior logs and sleep native policy run only when [state] **changes**.
  /// [ChildProtectionState.free] and [ChildProtectionState.appBlocked] foreground clearing follow the
  /// historical rules (free clears every call; appBlocked clears only on transition into appBlocked).
  ///
  /// [timeTamperingReason] is only used when [state] is [ChildProtectionState.timeTampered].
  Widget? apply(
    ChildProtectionState state,
    ChildProtectionApplyBindings bindings, {
    String? timeTamperingReason,
  }) {
    final changed = _lastAppliedChildProtectionState != state;
    _lastAppliedChildProtectionState = state;
    switch (state) {
      case ChildProtectionState.sleepLock:
        if (changed) {
          debugPrint(
            '[GenetProtect] action taken=ensure vpn on + enable restriction + no vpn screen',
          );
          unawaited(bindings.runSleepLockPolicy());
          unawaited(
            bindings.logBehaviorEvent(
              eventType: BehaviorEventType.protectionActivated,
              metadata: const {
                'state': 'sleepLock',
              },
            ),
          );
          final fg = bindings.getForegroundApp();
          if (fg != null && fg.isNotEmpty) {
            unawaited(
              bindings.logBehaviorEvent(
                eventType: BehaviorEventType.sleepViolation,
                appPackage: fg,
                metadata: const {
                  'state': 'sleepLock',
                },
              ),
            );
          }
        }
        return null;
      case ChildProtectionState.vpnRequired:
        if (changed) {
          debugPrint(
            '[GenetProtect] action taken=track vpnRequired without blocking UI',
          );
          unawaited(
            bindings.logBehaviorEvent(
              eventType: BehaviorEventType.vpnDisabled,
              metadata: const {
                'state': 'vpnRequired',
              },
            ),
          );
          unawaited(
            bindings.logBehaviorEvent(
              eventType: BehaviorEventType.protectionActivated,
              metadata: const {
                'state': 'vpnRequired',
              },
            ),
          );
        }
        return null;
      case ChildProtectionState.timeTampered:
        if (changed) {
          debugPrint(
            '[GenetTime] action taken=track time tampering without blocking UI',
          );
          unawaited(
            bindings.logBehaviorEvent(
              eventType: BehaviorEventType.protectionActivated,
              metadata: {
                'state': 'timeTampered',
                'reason': timeTamperingReason ?? 'unknown',
              },
            ),
          );
        }
        return null;
      case ChildProtectionState.appBlocked:
        if (changed) {
          debugPrint('[GenetProtect] action taken=show app blocking behavior');
          bindings.clearForegroundApp();
        }
        return null;
      case ChildProtectionState.free:
        if (changed) {
          debugPrint('[GenetProtect] action taken=remove all blocking');
        }
        bindings.clearForegroundApp();
        return null;
    }
  }

  /// Timer-driven protection refresh: role guard → sleep/native policy → night native sync.
  void scheduleBlockingStateSync({
    required bool Function() mounted,
    required Future<String?> Function() getUserRole,
    required String expectedChildRole,
    required Future<void> Function({SyncedChildData? data}) runSleepLockPolicy,
    required void Function() syncNightNativeOnly,
  }) {
    if (!mounted()) return;
    getUserRole().then((role) async {
      if (!mounted() || role != expectedChildRole) return;
      logCritical('GenetProtect', {
        'ROLE': role,
        'SYNC BLOCKING': 'start',
      });
      await runSleepLockPolicy();
      syncNightNativeOnly();
    });
  }
}
