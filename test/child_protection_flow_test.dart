import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/features/behavior/enums/behavior_event_type.dart';
import 'package:genet_final/features/child_protection/child_protection_flow.dart';
import 'package:genet_final/features/child_protection/child_protection_models.dart';
import 'package:genet_final/repositories/parent_child_sync_repository.dart';

void _noopLog(String scope, Map<String, Object?> fields) {}

ChildProtectionEvaluationContext _ctx({
  bool tamper = false,
  bool sleep = false,
  List<String> blocked = const [],
  String? fg,
  bool reqVpnScreen = false,
  bool netRelevant = false,
  bool isVpnActive = false,
  DateTime? protectionTime,
}) {
  final t = protectionTime ?? DateTime(2026, 4, 4, 12, 0);
  return ChildProtectionEvaluationContext(
    inputs: ChildProtectionEvaluateInputs(
      isVpnActive: isVpnActive,
      sleepLockActive: sleep,
      protectionTime: t,
      requireNetworkProtectionScreen: reqVpnScreen,
      networkProtectionRelevant: netRelevant,
      blockedApps: blocked,
    ),
    currentForegroundApp: fg,
    vpnProtectionStatusLabel: 'protected',
    timeTamperingDetected: tamper,
    timeTamperingReason: null,
  );
}

ChildProtectionApplyBindings _bindings({
  Future<void> Function({SyncedChildData? data})? runSleep,
  Future<void> Function({
    required BehaviorEventType eventType,
    String? appPackage,
    Map<String, dynamic>? metadata,
  })? log,
  String? Function()? fg,
  void Function()? clearFg,
}) {
  Future<void> defaultSleep({SyncedChildData? data}) async {}
  return ChildProtectionApplyBindings(
    runSleepLockPolicy: runSleep ?? defaultSleep,
    logBehaviorEvent: ({
      required BehaviorEventType eventType,
      String? appPackage,
      Map<String, dynamic>? metadata,
    }) async {
      await log?.call(
        eventType: eventType,
        appPackage: appPackage,
        metadata: metadata,
      );
    },
    getForegroundApp: fg ?? () => null,
    clearForegroundApp: clearFg ?? () {},
  );
}

void main() {
  group('ChildProtectionFlow.evaluate priority', () {
    test('timeTampered beats sleepLock and appBlocked', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      expect(
        flow.evaluate(
          _ctx(
            tamper: true,
            sleep: true,
            blocked: const ['com.bad'],
            fg: 'com.bad',
          ),
        ),
        ChildProtectionState.timeTampered,
      );
    });

    test('sleepLock beats appBlocked and vpnRequired', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      expect(
        flow.evaluate(
          _ctx(
            sleep: true,
            blocked: const ['com.bad'],
            fg: 'com.bad',
            reqVpnScreen: true,
            netRelevant: true,
          ),
        ),
        ChildProtectionState.sleepLock,
      );
    });

    test('appBlocked beats vpnRequired when foreground is in blocked list', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      expect(
        flow.evaluate(
          _ctx(
            blocked: const ['com.bad', 'com.bad'],
            fg: 'com.bad',
            reqVpnScreen: true,
            netRelevant: true,
          ),
        ),
        ChildProtectionState.appBlocked,
      );
    });

    test('vpnRequired when policy+relevant and not blocked', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      expect(
        flow.evaluate(
          _ctx(
            reqVpnScreen: true,
            netRelevant: true,
            blocked: const ['other.pkg'],
            fg: 'com.safe',
          ),
        ),
        ChildProtectionState.vpnRequired,
      );
    });

    test('free when nothing applies', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      expect(
        flow.evaluate(
          _ctx(
            blocked: const ['other.pkg'],
            fg: 'com.safe',
          ),
        ),
        ChildProtectionState.free,
      );
    });
  });

  group('ChildProtectionFlow.evaluate dedupe + resetAfterDisconnect', () {
    test('identical fingerprint skips extra critical logs', () {
      final logs = <String>[];
      final flow = ChildProtectionFlow(
        logCritical: (scope, fields) {
          logs.add(scope);
        },
      );
      final c = _ctx();
      flow.evaluate(c);
      final n = logs.length;
      expect(n, greaterThan(0));
      flow.evaluate(c);
      expect(logs.length, n);
    });

    test('resetAfterDisconnect clears fingerprint and last-applied tracking', () {
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      final c = _ctx();
      flow.evaluate(c);
      expect(flow.debugBlockingFingerprintForTest, isNotNull);
      flow.apply(ChildProtectionState.free, _bindings());
      expect(flow.debugLastAppliedStateForTest, ChildProtectionState.free);
      flow.resetAfterDisconnect();
      expect(flow.debugBlockingFingerprintForTest, isNull);
      expect(flow.debugLastAppliedStateForTest, isNull);
    });
  });

  group('ChildProtectionFlow.apply side-effect gating', () {
    test('sleepLock: runSleepLockPolicy only on transition into sleepLock', () async {
      var sleepRuns = 0;
      final b = _bindings(
        runSleep: ({data}) async {
          sleepRuns++;
        },
      );
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      flow.apply(ChildProtectionState.sleepLock, b);
      expect(sleepRuns, 1);
      flow.apply(ChildProtectionState.sleepLock, b);
      expect(sleepRuns, 1);
      flow.apply(ChildProtectionState.free, b);
      flow.apply(ChildProtectionState.sleepLock, b);
      expect(sleepRuns, 2);
    });

    test('appBlocked: clearForeground only on transition into appBlocked', () {
      var clears = 0;
      final b = _bindings(clearFg: () => clears++);
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      flow.apply(ChildProtectionState.appBlocked, b);
      expect(clears, 1);
      flow.apply(ChildProtectionState.appBlocked, b);
      expect(clears, 1);
    });

    test('free: clearForeground on every apply (historical behavior)', () {
      var clears = 0;
      final b = _bindings(clearFg: () => clears++);
      final flow = ChildProtectionFlow(logCritical: _noopLog);
      flow.apply(ChildProtectionState.free, b);
      flow.apply(ChildProtectionState.free, b);
      expect(clears, 2);
    });
  });
}
