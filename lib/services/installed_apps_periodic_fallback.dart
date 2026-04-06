import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../core/user_role.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import 'installed_apps_bridge.dart';
import 'installed_apps_categorization.dart';
import 'relevant_installed_apps_engine.dart';

/// Step 5 — infrequent full scan + engine + [syncRelevantApps] when realtime may have missed events.
///
/// Realtime (Step 3) remains primary; this is a safety net only.
const Duration _minGapBetweenFallbacks = Duration(minutes: 12);
const Duration _realtimeRecentIfForeground = Duration(minutes: 5);

DateTime? _lastFallbackRun;
DateTime? _lastRealtimePackageEvent;

/// Call when a Step 3 [onPackageChanged] event is received (before handling).
void notifyInstalledAppsRealtimePackageEvent() {
  _lastRealtimePackageEvent = DateTime.now();
}

/// Clears guard timestamps (e.g. when child home is disposed after unlink).
void resetInstalledAppsFallbackGuards() {
  _lastFallbackRun = null;
  _lastRealtimePackageEvent = null;
}

/// One full scan → Step 2 → engine → Step 4 sync. No extra list sources.
Future<void> runFallbackInstalledAppsRefresh() async {
  if (!Platform.isAndroid) return;

  final now = DateTime.now();
  if (_lastFallbackRun != null &&
      now.difference(_lastFallbackRun!) < _minGapBetweenFallbacks) {
    return;
  }

  final lifecycle = WidgetsBinding.instance.lifecycleState;
  final inForeground = lifecycle == AppLifecycleState.resumed;
  if (inForeground &&
      _lastRealtimePackageEvent != null &&
      now.difference(_lastRealtimePackageEvent!) < _realtimeRecentIfForeground) {
    return;
  }

  try {
    final role = await getUserRole();
    if (!isChildRole(role)) return;

    final parentId = normalizeIdentifier(await getLinkedParentId());
    final childId = normalizeIdentifier(await getLinkedChildId());
    if (parentId == null || childId == null) return;

    _lastFallbackRun = DateTime.now();

    final rawList = await InstalledAppsBridge.fetchInstalledAppsRaw();
    final relevantApps = categorizeInstalledApps(rawList);
    RelevantInstalledAppsEngine.instance.applyFullRelevantState(
      relevantApps,
      rawList.length,
    );
    await syncRelevantApps(
      childId: childId,
      relevantApps: relevantApps,
      rawInstalledAppCount: rawList.length,
      trigger: 'periodic_fallback',
    );
  } catch (e, st) {
    debugPrint('[InstalledAppsPeriodicFallback] runFallbackInstalledAppsRefresh: $e $st');
  }
}
