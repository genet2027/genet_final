import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/user_role.dart';
import '../models/installed_app.dart';
import '../models/package_change_event.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import 'installed_apps_bridge.dart';
import 'installed_apps_categorization.dart';

/// Step 3 — single in-memory relevant list + fast-path package add/remove (no full scan per event).
/// Step 4 — sole input for [syncRelevantApps] on the child (parent exclusions apply on parent only).
class RelevantInstalledAppsEngine {
  RelevantInstalledAppsEngine._();
  static final RelevantInstalledAppsEngine instance = RelevantInstalledAppsEngine._();

  final Map<String, InstalledApp> _byPackage = {};
  int _rawInstalledCount = 0;
  bool _hydrated = false;

  final StreamController<List<InstalledApp>> _listCtrl =
      StreamController<List<InstalledApp>>.broadcast();

  /// Sorted relevant apps after each local mutation (for immediate UI).
  Stream<List<InstalledApp>> get relevantListStream => _listCtrl.stream;

  List<InstalledApp> get currentRelevantSorted => _sortedList();

  void reset() {
    _hydrated = false;
    _byPackage.clear();
    _rawInstalledCount = 0;
  }

  /// After a full device scan + Step‑2 categorization on the child.
  void applyFullRelevantState(List<InstalledApp> relevantApps, int rawInstalledAppCount) {
    _byPackage
      ..clear()
      ..addEntries(relevantApps.map((a) => MapEntry(a.packageName, a)));
    _rawInstalledCount = rawInstalledAppCount;
    _hydrated = true;
    _emitLocal();
  }

  List<InstalledApp> _sortedList() {
    final list = _byPackage.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }

  void _emitLocal() {
    if (_listCtrl.isClosed) return;
    _listCtrl.add(_sortedList());
  }

  Future<void> _hydrateIfNeeded() async {
    if (_hydrated) return;
    final rawList = await InstalledAppsBridge.fetchInstalledAppsRaw();
    _rawInstalledCount = rawList.length;
    _byPackage.clear();
    for (final app in categorizeInstalledApps(rawList)) {
      _byPackage[app.packageName] = app;
    }
    _hydrated = true;
  }

  Future<void> _mergeSingleAddedPackage(String packageName) async {
    final raw = await InstalledAppsBridge.fetchInstalledAppRaw(packageName);
    if (raw == null) return;
    final categorized = categorizeInstalledApps([raw]);
    if (categorized.isEmpty) return;
    final app = categorized.first;
    _byPackage[app.packageName] = app;
  }

  /// Handles one native [onPackageChanged] event: merge, then full-list backend sync.
  Future<void> handlePackageChangeEvent(PackageChangeEvent event) async {
    try {
      final role = await getUserRole();
      if (!isChildRole(role)) return;

      final childId = normalizeIdentifier(await getLinkedChildId());
      final parentId = normalizeIdentifier(await getLinkedParentId());
      if (childId == null || parentId == null) return;

      final wasHydrated = _hydrated;
      await _hydrateIfNeeded();

      if (!wasHydrated) {
        if (event.action == 'removed') {
          _byPackage.remove(event.packageName);
        } else {
          await _mergeSingleAddedPackage(event.packageName);
        }
        _emitLocal();
        await syncRelevantApps(
          childId: childId,
          relevantApps: _sortedList(),
          rawInstalledAppCount: _rawInstalledCount,
          trigger: event.action == 'removed' ? 'package_removed' : 'package_added',
        );
        return;
      }

      if (event.action == 'removed') {
        _byPackage.remove(event.packageName);
        if (_rawInstalledCount > 0) _rawInstalledCount -= 1;
        _emitLocal();
        await syncRelevantApps(
          childId: childId,
          relevantApps: _sortedList(),
          rawInstalledAppCount: _rawInstalledCount,
          trigger: 'package_removed',
        );
        return;
      }

      if (event.action == 'added') {
        _rawInstalledCount += 1;
        await _mergeSingleAddedPackage(event.packageName);
        _emitLocal();
        await syncRelevantApps(
          childId: childId,
          relevantApps: _sortedList(),
          rawInstalledAppCount: _rawInstalledCount,
          trigger: 'package_added',
        );
      }
    } catch (e, st) {
      debugPrint('[RelevantInstalledAppsEngine] handlePackageChangeEvent ignored: $e $st');
    }
  }
}
