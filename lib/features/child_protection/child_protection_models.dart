import '../behavior/enums/behavior_event_type.dart';
import '../../repositories/parent_child_sync_repository.dart';

/// Priority order in `ChildProtectionFlow.evaluate` must stay:
/// timeTampered → sleepLock → appBlocked → vpnRequired → free.
enum ChildProtectionState {
  free,
  sleepLock,
  vpnRequired,
  timeTampered,
  appBlocked,
}

/// Frame-level inputs for protection evaluation (blocked list, VPN flags, sleep flag, time).
class ChildProtectionEvaluateInputs {
  const ChildProtectionEvaluateInputs({
    required this.isVpnActive,
    required this.sleepLockActive,
    required this.protectionTime,
    required this.requireNetworkProtectionScreen,
    required this.networkProtectionRelevant,
    required this.blockedApps,
  });

  final bool isVpnActive;
  final bool sleepLockActive;
  final DateTime protectionTime;
  final bool requireNetworkProtectionScreen;
  final bool networkProtectionRelevant;
  /// Align with child UI: `VpnRemoteChildPolicy.effectiveBlockedPackages` using the same clock as
  /// [protectionTime] (`currentTimeMs: protectionTime.millisecondsSinceEpoch` on child home).
  final List<String> blockedApps;
}

/// Full read context for one evaluate pass (includes dedupe/logging fields from the screen).
class ChildProtectionEvaluationContext {
  const ChildProtectionEvaluationContext({
    required this.inputs,
    required this.currentForegroundApp,
    required this.vpnProtectionStatusLabel,
    required this.timeTamperingDetected,
    required this.timeTamperingReason,
  });

  final ChildProtectionEvaluateInputs inputs;
  final String? currentForegroundApp;
  final String? vpnProtectionStatusLabel;
  final bool timeTamperingDetected;
  final String? timeTamperingReason;
}

/// Side effects for [ChildProtectionFlow.apply] (sleep/native policy + behavior log + foreground field).
class ChildProtectionApplyBindings {
  ChildProtectionApplyBindings({
    required this.runSleepLockPolicy,
    required this.logBehaviorEvent,
    required this.getForegroundApp,
    required this.clearForegroundApp,
  });

  final Future<void> Function({SyncedChildData? data}) runSleepLockPolicy;
  final Future<void> Function({
    required BehaviorEventType eventType,
    String? appPackage,
    Map<String, dynamic>? metadata,
  }) logBehaviorEvent;
  final String? Function() getForegroundApp;
  final void Function() clearForegroundApp;
}
