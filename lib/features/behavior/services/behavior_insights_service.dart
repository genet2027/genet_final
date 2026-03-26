import '../enums/behavior_event_type.dart';
import '../models/behavior_event.dart';
import 'behavior_local_store.dart';

class BehaviorInsightsSummary {
  const BehaviorInsightsSummary({
    required this.totalAttemptsToday,
    required this.totalAttemptsThisWeek,
    required this.topProblemApps,
    required this.peakHours,
    required this.vpnDisableCount,
    required this.sleepViolationCount,
    required this.exitAttemptCount,
  });

  final int totalAttemptsToday;
  final int totalAttemptsThisWeek;
  final List<String> topProblemApps;
  final List<int> peakHours;
  final int vpnDisableCount;
  final int sleepViolationCount;
  final int exitAttemptCount;
}

class BehaviorInsightsService {
  BehaviorInsightsService({BehaviorLocalStore? localStore})
    : _localStore = localStore ?? BehaviorLocalStore.instance;

  final BehaviorLocalStore _localStore;

  Future<BehaviorInsightsSummary> getInsightsForChild(String childId) async {
    await _localStore.init();
    final events = await _localStore.getEventsForChild(childId);
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(
      Duration(days: startOfToday.weekday - 1),
    );

    final attemptsToday = events.where(
      (event) =>
          event.eventType == BehaviorEventType.blockedAppAttempt &&
          !event.timestamp.isBefore(startOfToday),
    );
    final attemptsThisWeek = events.where(
      (event) =>
          event.eventType == BehaviorEventType.blockedAppAttempt &&
          !event.timestamp.isBefore(startOfWeek),
    );

    final appCounts = <String, int>{};
    final hourCounts = <int, int>{};
    var vpnDisableCount = 0;
    var sleepViolationCount = 0;
    var exitAttemptCount = 0;

    for (final event in events) {
      if (event.eventType == BehaviorEventType.blockedAppAttempt) {
        final appKey = event.appName ?? event.appPackage ?? 'Unknown app';
        appCounts.update(appKey, (count) => count + 1, ifAbsent: () => 1);
      }
      hourCounts.update(
        event.timestamp.hour,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (event.eventType == BehaviorEventType.vpnDisabled) {
        vpnDisableCount++;
      }
      if (event.eventType == BehaviorEventType.sleepViolation) {
        sleepViolationCount++;
      }
      if (event.eventType == BehaviorEventType.exitAttempt) {
        exitAttemptCount++;
      }
    }

    final sortedApps =
        appCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final sortedHours =
        hourCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return BehaviorInsightsSummary(
      totalAttemptsToday: attemptsToday.length,
      totalAttemptsThisWeek: attemptsThisWeek.length,
      topProblemApps: sortedApps.take(3).map((entry) => entry.key).toList(),
      peakHours: sortedHours.take(3).map((entry) => entry.key).toList(),
      vpnDisableCount: vpnDisableCount,
      sleepViolationCount: sleepViolationCount,
      exitAttemptCount: exitAttemptCount,
    );
  }

  Future<String> generateParentInsightSentence(String childId) async {
    final summary = await getInsightsForChild(childId);
    if (summary.sleepViolationCount > 0 && summary.peakHours.isNotEmpty) {
      final peakHour = summary.peakHours.first;
      if (peakHour >= 22 || peakHour < 6) {
        return 'Most restriction attempts happen late at night.';
      }
    }
    if (summary.topProblemApps.isNotEmpty) {
      return '${summary.topProblemApps.first} is the most frequently attempted blocked app.';
    }
    if (summary.vpnDisableCount > 1) {
      return 'Several VPN disable attempts were detected.';
    }
    if (summary.exitAttemptCount > 0) {
      return 'Repeated attempts to exit protection screens were detected.';
    }
    return 'Child protection activity is currently stable.';
  }
}
