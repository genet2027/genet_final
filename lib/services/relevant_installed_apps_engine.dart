import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/user_role.dart';
import '../models/installed_app.dart';
import '../models/installed_app_raw.dart';
import '../models/package_change_event.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import 'installed_apps_bridge.dart';
import 'installed_apps_categorization.dart';

// -----------------------------------------------------------------------------
// DEBUG — package / browser trace (disappearing apps). Set filter to substring of
// package name, e.g. 'com.android.chrome'. Empty = no substring match; apps whose
// display name contains "browser" still trace in debug builds.
// -----------------------------------------------------------------------------
const String _kRelevantAppsTracePackageFilter = '';

/// Authoritative child-side relevant installed apps + backend sync.
///
/// Every mutation follows: INPUT → DECISION → COMMIT → EMIT (if changed) → SYNC (if needed).
///
/// Overlapping async paths are serialized (refresh + package events). Each segment also
/// carries a monotonic [commitGeneration]: stale results never commit after a newer mutation
/// has started, and stale single adds cannot override a newer per-package commit.
class RelevantInstalledAppsEngine {
  RelevantInstalledAppsEngine._();
  static final RelevantInstalledAppsEngine instance = RelevantInstalledAppsEngine._();

  final Map<String, InstalledApp> _byPackage = {};
  int _rawInstalledCount = 0;
  bool _hydrated = false;

  /// Bumped whenever a new mutation **segment** begins; used to drop stale async completions.
  int _mutationGeneration = 0;

  /// Generation of the last **committed** full-inventory replace (hydrate / full scan).
  int _lastFullInventoryCommitGen = 0;

  /// Last **committed** mutation generation touching each package (add/remove). Cleared on full replace.
  final Map<String, int> _packageLastCommitGen = {};

  Future<void> _mutationExclusive = Future<void>.value();

  final StreamController<List<InstalledApp>> _listCtrl =
      StreamController<List<InstalledApp>>.broadcast();

  Stream<List<InstalledApp>> get relevantListStream => _listCtrl.stream;

  List<InstalledApp> get currentRelevantSorted => _sortedListFromMap(_byPackage);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void reset({String mutationSource = 'reset'}) {
    final snap = _captureSnapshot();
    _mutationGeneration++;
    _lastFullInventoryCommitGen = 0;
    _packageLastCommitGen.clear();
    _hydrated = false;
    _byPackage.clear();
    _rawInstalledCount = 0;
    if (kDebugMode) {
      _logPipelineEnd(
        source: mutationSource,
        kind: 'reset',
        snapBefore: snap,
        snapAfter: _captureSnapshot(),
        stateChanged: true,
        uiEmitted: false,
        syncTriggered: false,
      );
    }
  }

  /// Full device scan → decision → commit → emit if changed → sync if needed.
  Future<int> refreshFromFullDeviceScanAndSync({
    required String childId,
    required String parentId,
    required String mutationSource,
    required String syncTrigger,
  }) {
    return _serializeMutations(() async {
      final commitGeneration = _issueMutationGeneration();
      final rawList = await InstalledAppsBridge.fetchInstalledAppsRaw();
      return _runFullReplacementPipeline(
        decidedRelevant: categorizeInstalledApps(rawList),
        nextRawCount: rawList.length,
        commitGeneration: commitGeneration,
        setHydrated: true,
        emitUiAllowed: true,
        childId: childId,
        parentId: parentId,
        mutationSource: mutationSource,
        syncTrigger: syncTrigger,
        kind: 'full_scan',
        inventoryRawForTrace: rawList,
      );
    });
  }

  Future<void> handlePackageChangeEvent(PackageChangeEvent event) async {
    try {
      final role = await getUserRole();
      if (!isChildRole(role)) return;

      final childId = normalizeIdentifier(await getLinkedChildId());
      final parentId = normalizeIdentifier(await getLinkedParentId());
      if (childId == null || parentId == null) return;

      await _serializeMutations(() async {
        final wasHydrated = _hydrated;
        await _hydratePipeline();

        if (!wasHydrated) {
          if (event.action == 'removed') {
            await _runSingleRemovePipeline(
              event.packageName,
              nextRawCount: _rawInstalledCount > 0 ? _rawInstalledCount - 1 : 0,
              childId: childId,
              parentId: parentId,
              mutationSource: 'realtime_remove_first',
              syncTrigger: 'package_removed',
            );
          } else {
            await _runSingleAddPipeline(
              event.packageName,
              nextRawCount: _rawInstalledCount,
              dropExistingKeyFirst: true,
              childId: childId,
              parentId: parentId,
              mutationSource: 'realtime_add_first',
              syncTrigger: 'package_added',
            );
          }
          return;
        }

        if (event.action == 'removed') {
          await _runSingleRemovePipeline(
            event.packageName,
            nextRawCount: _rawInstalledCount > 0 ? _rawInstalledCount - 1 : 0,
            childId: childId,
            parentId: parentId,
            mutationSource: 'realtime_remove',
            syncTrigger: 'package_removed',
          );
          return;
        }

        if (event.action == 'added') {
          await _runSingleAddPipeline(
            event.packageName,
            nextRawCount: _rawInstalledCount + 1,
            dropExistingKeyFirst: true,
            childId: childId,
            parentId: parentId,
            mutationSource: 'realtime_add',
            syncTrigger: 'package_added',
          );
        }
      });
    } catch (e, st) {
      debugPrint('[RelevantInstalledAppsEngine] handlePackageChangeEvent ignored: $e $st');
    }
  }

  // ---------------------------------------------------------------------------
  // Pipeline: INPUT → DECISION → COMMIT → EMIT → SYNC
  // ---------------------------------------------------------------------------

  /// Hydrate only: full raw list → [categorizeInstalledApps] → commit, no UI, no sync.
  Future<void> _hydratePipeline() async {
    if (_hydrated) return;
    final commitGeneration = _issueMutationGeneration();
    final rawList = await InstalledAppsBridge.fetchInstalledAppsRaw();
    final decided = categorizeInstalledApps(rawList);
    await _runFullReplacementPipeline(
      decidedRelevant: decided,
      nextRawCount: rawList.length,
      commitGeneration: commitGeneration,
      setHydrated: true,
      emitUiAllowed: false,
      childId: '',
      parentId: '',
      mutationSource: 'hydrate',
      syncTrigger: '',
      kind: 'hydrate',
      skipSync: true,
      inventoryRawForTrace: rawList,
    );
  }

  Future<int> _runFullReplacementPipeline({
    required List<InstalledApp> decidedRelevant,
    required int nextRawCount,
    required int commitGeneration,
    required bool setHydrated,
    required bool emitUiAllowed,
    required String childId,
    required String parentId,
    required String mutationSource,
    required String syncTrigger,
    required String kind,
    bool skipSync = false,
    List<InstalledAppRaw>? inventoryRawForTrace,
  }) async {
    final snapBefore = _captureSnapshot();
    final relevantKeysBefore = Set<String>.from(_byPackage.keys);
    final traceAppNamesBefore = {
      for (final e in _byPackage.entries) e.key: e.value.appName,
    };
    final inRawByPackage = _traceIndexRawByPackage(inventoryRawForTrace);
    final nextMap = _relevantMapFromDecidedList(decidedRelevant);

    if (kDebugMode) {
      _traceFullInventoryPackages(
        stage: 'after_categorize',
        mutationSource: mutationSource,
        kind: kind,
        commitGeneration: commitGeneration,
        inventoryRawForTrace: inventoryRawForTrace,
        decidedRelevant: decidedRelevant,
        relevantKeysBefore: relevantKeysBefore,
        traceAppNamesBefore: traceAppNamesBefore,
        inRawByPackage: inRawByPackage,
        committed: false,
        commitReason: 'pending',
        nextMap: nextMap,
        uiEmitted: false,
        syncTriggered: false,
        relevantCountAfter: snapBefore.relevantCount,
      );
    }

    final fpNext = relevantInventorySyncFingerprint(decidedRelevant);
    final fpCur = snapBefore.relevantFingerprint;
    final rawChanged = nextRawCount != snapBefore.rawCount;
    final relChanged = fpNext != fpCur || decidedRelevant.length != snapBefore.relevantCount;

    final mustCommit = !snapBefore.hydrated || relChanged || rawChanged;
    if (!mustCommit) {
      if (kDebugMode) {
        _logPipelineEnd(
          source: mutationSource,
          kind: kind,
          snapBefore: snapBefore,
          snapAfter: snapBefore,
          stateChanged: false,
          uiEmitted: false,
          syncTriggered: false,
        );
        _traceFullInventoryPackages(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          kind: kind,
          commitGeneration: commitGeneration,
          inventoryRawForTrace: inventoryRawForTrace,
          decidedRelevant: decidedRelevant,
          relevantKeysBefore: relevantKeysBefore,
          traceAppNamesBefore: traceAppNamesBefore,
          inRawByPackage: inRawByPackage,
          committed: false,
          commitReason: 'identical_no_op',
          nextMap: nextMap,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
        );
      }
      return decidedRelevant.length;
    }

    if (!_isFullInventoryCommitAllowed(commitGeneration)) {
      if (kDebugMode) {
        _logStaleDrop(
          source: mutationSource,
          kind: kind,
          commitGeneration: commitGeneration,
          packageName: null,
          reason: 'newer_mutation_won',
        );
        _traceFullInventoryPackages(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          kind: kind,
          commitGeneration: commitGeneration,
          inventoryRawForTrace: inventoryRawForTrace,
          decidedRelevant: decidedRelevant,
          relevantKeysBefore: relevantKeysBefore,
          traceAppNamesBefore: traceAppNamesBefore,
          inRawByPackage: inRawByPackage,
          committed: false,
          commitReason: 'stale_mutation_dropped',
          nextMap: nextMap,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
        );
      }
      return _byPackage.length;
    }

    _commitAuthoritativeState(
      nextMap,
      nextRawCount,
      markHydrated: setHydrated,
    );
    _recordFullInventoryCommitted(commitGeneration);

    var uiEmitted = false;
    if (emitUiAllowed && relChanged) {
      _emitLocal();
      uiEmitted = true;
    }

    var syncTriggered = false;
    var synced = decidedRelevant.length;
    if (!skipSync && childId.isNotEmpty && (relChanged || rawChanged)) {
      syncTriggered = true;
      synced = await syncRelevantApps(
        childId: childId,
        relevantApps: decidedRelevant,
        rawInstalledAppCount: nextRawCount,
        trigger: syncTrigger,
      );
    }

    if (kDebugMode) {
      final snapAfter = _captureSnapshot();
      _logPipelineEnd(
        source: mutationSource,
        kind: kind,
        snapBefore: snapBefore,
        snapAfter: snapAfter,
        stateChanged: true,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
      );
      if (parentId.isNotEmpty) {
        debugPrint(
          '[RelevantAppsEngine] pipeline full_scan_sync trigger=$syncTrigger child=$childId parent=$parentId synced=$synced',
        );
      }
      _traceFullInventoryPackages(
        stage: 'pipeline_end',
        mutationSource: mutationSource,
        kind: kind,
        commitGeneration: commitGeneration,
        inventoryRawForTrace: inventoryRawForTrace,
        decidedRelevant: decidedRelevant,
        relevantKeysBefore: relevantKeysBefore,
        traceAppNamesBefore: traceAppNamesBefore,
        inRawByPackage: inRawByPackage,
        committed: true,
        commitReason: 'committed_full_inventory_replace',
        nextMap: nextMap,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
        relevantCountAfter: snapAfter.relevantCount,
      );
    }

    return synced;
  }

  Future<void> _runSingleAddPipeline(
    String packageName, {
    required int nextRawCount,
    required bool dropExistingKeyFirst,
    required String childId,
    required String parentId,
    required String mutationSource,
    required String syncTrigger,
  }) async {
    final commitGeneration = _issueMutationGeneration();
    final snapBefore = _captureSnapshot();
    final hadKeyBefore = _byPackage.containsKey(packageName);
    final raw = await InstalledAppsBridge.fetchInstalledAppRaw(packageName);
    final decided = installedAppForRelevantRaw(raw);

    if (kDebugMode) {
      _traceRealtimeAdd(
        stage: 'after_bridge_fetch',
        mutationSource: mutationSource,
        commitGeneration: commitGeneration,
        packageName: packageName,
        raw: raw,
        decided: decided,
        hadKeyBefore: hadKeyBefore,
        relChanged: null,
        rawChanged: null,
        committed: null,
        removedFromRelevantState: null,
        uiEmitted: null,
        syncTriggered: null,
        relevantCountAfter: null,
        outcomeReason: 'pending',
      );
    }

    final nextMap = Map<String, InstalledApp>.from(_byPackage);
    if (dropExistingKeyFirst) {
      nextMap.remove(packageName);
    }
    if (decided != null) {
      nextMap[decided.packageName] = decided;
    } else {
      nextMap.remove(packageName);
    }

    final nextList = _sortedListFromMap(nextMap);
    final fpNext = relevantInventorySyncFingerprint(nextList);
    final relChanged = fpNext != snapBefore.relevantFingerprint || nextList.length != snapBefore.relevantCount;
    final rawChanged = nextRawCount != snapBefore.rawCount;

    if (!relChanged && !rawChanged) {
      if (kDebugMode) {
        _logPipelineEnd(
          source: mutationSource,
          kind: 'realtime_add',
          snapBefore: snapBefore,
          snapAfter: snapBefore,
          stateChanged: false,
          packageName: packageName,
          uiEmitted: false,
          syncTriggered: false,
        );
        _traceRealtimeAdd(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          commitGeneration: commitGeneration,
          packageName: packageName,
          raw: raw,
          decided: decided,
          hadKeyBefore: hadKeyBefore,
          relChanged: relChanged,
          rawChanged: rawChanged,
          committed: false,
          removedFromRelevantState: false,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
          outcomeReason: 'identical_no_op',
        );
      }
      return;
    }

    final canonicalPackage = decided?.packageName ?? packageName;
    final hadInRelevantState =
        _byPackage.containsKey(packageName) ||
        (decided != null && _byPackage.containsKey(decided.packageName));
    final inNextRelevant = decided != null
        ? nextMap.containsKey(decided.packageName)
        : nextMap.containsKey(packageName);
    final removedFromRelevant = hadInRelevantState && !inNextRelevant;

    if (!_isSingleAddCommitAllowed(commitGeneration, canonicalPackage)) {
      final stale = _staleReasonForSingleAdd(commitGeneration, canonicalPackage);
      if (kDebugMode) {
        _logStaleDrop(
          source: mutationSource,
          kind: 'realtime_add',
          commitGeneration: commitGeneration,
          packageName: canonicalPackage,
          reason: stale,
        );
        _traceRealtimeAdd(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          commitGeneration: commitGeneration,
          packageName: packageName,
          raw: raw,
          decided: decided,
          hadKeyBefore: hadKeyBefore,
          relChanged: relChanged,
          rawChanged: rawChanged,
          committed: false,
          removedFromRelevantState: removedFromRelevant,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
          outcomeReason: _traceStaleReasonLabel(stale),
        );
      }
      return;
    }

    _commitAuthoritativeState(nextMap, nextRawCount, markHydrated: false);
    _recordPackageCommitted(canonicalPackage, commitGeneration);

    var uiEmitted = false;
    if (relChanged) {
      _emitLocal();
      uiEmitted = true;
    }

    var syncTriggered = false;
    var synced = 0;
    if (relChanged || rawChanged) {
      syncTriggered = true;
      synced = await syncRelevantApps(
        childId: childId,
        relevantApps: nextList,
        rawInstalledAppCount: nextRawCount,
        trigger: syncTrigger,
      );
    }

    if (kDebugMode) {
      final snapAfter = _captureSnapshot();
      _logPipelineEnd(
        source: mutationSource,
        kind: 'realtime_add',
        snapBefore: snapBefore,
        snapAfter: snapAfter,
        stateChanged: true,
        packageName: packageName,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
      );
      if (syncTriggered) {
        debugPrint('[RelevantAppsEngine] pipeline realtime_add_sync synced=$synced');
      }
      _traceRealtimeAdd(
        stage: 'pipeline_end',
        mutationSource: mutationSource,
        commitGeneration: commitGeneration,
        packageName: packageName,
        raw: raw,
        decided: decided,
        hadKeyBefore: hadKeyBefore,
        relChanged: relChanged,
        rawChanged: rawChanged,
        committed: true,
        removedFromRelevantState: removedFromRelevant,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
        relevantCountAfter: snapAfter.relevantCount,
        outcomeReason:
            removedFromRelevant ? _traceAddRemovalReason(raw, decided) : 'committed_realtime_add',
      );
    }
  }

  Future<void> _runSingleRemovePipeline(
    String packageName, {
    required int nextRawCount,
    required String childId,
    required String parentId,
    required String mutationSource,
    required String syncTrigger,
  }) async {
    final commitGeneration = _issueMutationGeneration();
    final snapBefore = _captureSnapshot();
    final appNameBefore = _byPackage[packageName]?.appName;
    if (kDebugMode) {
      _traceRealtimeRemove(
        stage: 'after_input',
        mutationSource: mutationSource,
        commitGeneration: commitGeneration,
        packageName: packageName,
        appNameBefore: appNameBefore,
        relChanged: null,
        rawChanged: null,
        committed: null,
        uiEmitted: null,
        syncTriggered: null,
        relevantCountAfter: null,
        outcomeReason: 'pending',
      );
    }
    final nextMap = Map<String, InstalledApp>.from(_byPackage)..remove(packageName);
    final nextList = _sortedListFromMap(nextMap);

    final fpNext = relevantInventorySyncFingerprint(nextList);
    final relChanged = fpNext != snapBefore.relevantFingerprint || nextList.length != snapBefore.relevantCount;
    final rawChanged = nextRawCount != snapBefore.rawCount;

    if (!relChanged && !rawChanged) {
      if (kDebugMode) {
        _logPipelineEnd(
          source: mutationSource,
          kind: 'realtime_remove',
          snapBefore: snapBefore,
          snapAfter: snapBefore,
          stateChanged: false,
          packageName: packageName,
          uiEmitted: false,
          syncTriggered: false,
        );
        _traceRealtimeRemove(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          commitGeneration: commitGeneration,
          packageName: packageName,
          appNameBefore: appNameBefore,
          relChanged: relChanged,
          rawChanged: rawChanged,
          committed: false,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
          outcomeReason: 'identical_no_op',
        );
      }
      return;
    }

    if (!_isSingleRemoveCommitAllowed(commitGeneration)) {
      final stale = _staleReasonForSingleRemove(commitGeneration);
      if (kDebugMode) {
        _logStaleDrop(
          source: mutationSource,
          kind: 'realtime_remove',
          commitGeneration: commitGeneration,
          packageName: packageName,
          reason: stale,
        );
        _traceRealtimeRemove(
          stage: 'pipeline_end',
          mutationSource: mutationSource,
          commitGeneration: commitGeneration,
          packageName: packageName,
          appNameBefore: appNameBefore,
          relChanged: relChanged,
          rawChanged: rawChanged,
          committed: false,
          uiEmitted: false,
          syncTriggered: false,
          relevantCountAfter: snapBefore.relevantCount,
          outcomeReason: _traceStaleReasonLabel(stale),
        );
      }
      return;
    }

    _commitAuthoritativeState(nextMap, nextRawCount, markHydrated: false);
    _recordPackageCommitted(packageName, commitGeneration);

    var uiEmitted = false;
    if (relChanged) {
      _emitLocal();
      uiEmitted = true;
    }

    var syncTriggered = false;
    var synced = 0;
    if (relChanged || rawChanged) {
      syncTriggered = true;
      synced = await syncRelevantApps(
        childId: childId,
        relevantApps: nextList,
        rawInstalledAppCount: nextRawCount,
        trigger: syncTrigger,
      );
    }

    if (kDebugMode) {
      final snapAfter = _captureSnapshot();
      _logPipelineEnd(
        source: mutationSource,
        kind: 'realtime_remove',
        snapBefore: snapBefore,
        snapAfter: snapAfter,
        stateChanged: true,
        packageName: packageName,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
      );
      if (syncTriggered) {
        debugPrint('[RelevantAppsEngine] pipeline realtime_remove_sync synced=$synced');
      }
      _traceRealtimeRemove(
        stage: 'pipeline_end',
        mutationSource: mutationSource,
        commitGeneration: commitGeneration,
        packageName: packageName,
        appNameBefore: appNameBefore,
        relChanged: relChanged,
        rawChanged: rawChanged,
        committed: true,
        uiEmitted: uiEmitted,
        syncTriggered: syncTriggered,
        relevantCountAfter: snapAfter.relevantCount,
        outcomeReason: 'removed_event_committed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Decision output → structure (no extra rules; same as [categorizeInstalledApps] output)
  // ---------------------------------------------------------------------------

  Map<String, InstalledApp> _relevantMapFromDecidedList(List<InstalledApp> decided) {
    return {for (final a in decided) a.packageName: a};
  }

  List<InstalledApp> _sortedListFromMap(Map<String, InstalledApp> map) {
    final list = map.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }

  void _commitAuthoritativeState(
    Map<String, InstalledApp> nextByPackage,
    int nextRawCount, {
    required bool markHydrated,
  }) {
    _byPackage
      ..clear()
      ..addAll(nextByPackage);
    _rawInstalledCount = nextRawCount;
    if (markHydrated) _hydrated = true;
  }

  void _emitLocal() {
    if (_listCtrl.isClosed) return;
    _listCtrl.add(_sortedListFromMap(_byPackage));
  }

  _Snapshot _captureSnapshot() {
    final list = _sortedListFromMap(_byPackage);
    return _Snapshot(
      relevantFingerprint: relevantInventorySyncFingerprint(list),
      rawCount: _rawInstalledCount,
      relevantCount: list.length,
      hydrated: _hydrated,
    );
  }

  int _issueMutationGeneration() => ++_mutationGeneration;

  Future<T> _serializeMutations<T>(Future<T> Function() action) async {
    final previous = _mutationExclusive;
    final done = Completer<void>();
    _mutationExclusive = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  bool _isGlobalGenerationCurrent(int g) => g == _mutationGeneration;

  bool _isFullInventoryCommitAllowed(int g) => _isGlobalGenerationCurrent(g);

  bool _isSingleRemoveCommitAllowed(int g) {
    return _isGlobalGenerationCurrent(g) && g >= _lastFullInventoryCommitGen;
  }

  bool _isSingleAddCommitAllowed(int g, String packageName) {
    if (!_isGlobalGenerationCurrent(g)) return false;
    if (g < _lastFullInventoryCommitGen) return false;
    final last = _packageLastCommitGen[packageName];
    return last == null || last <= g;
  }

  void _recordFullInventoryCommitted(int g) {
    _lastFullInventoryCommitGen = g;
    _packageLastCommitGen.clear();
  }

  void _recordPackageCommitted(String packageName, int g) {
    _packageLastCommitGen[packageName] = g;
  }

  String _staleReasonForSingleAdd(int g, String packageName) {
    if (!_isGlobalGenerationCurrent(g)) return 'newer_mutation_won';
    if (g < _lastFullInventoryCommitGen) return 'full_inventory_superseded';
    final last = _packageLastCommitGen[packageName];
    if (last != null && last > g) return 'package_newer_commit';
    return 'stale';
  }

  String _staleReasonForSingleRemove(int g) {
    if (!_isGlobalGenerationCurrent(g)) return 'newer_mutation_won';
    if (g < _lastFullInventoryCommitGen) return 'full_inventory_superseded';
    return 'stale';
  }

  // ---------------------------------------------------------------------------
  // DEBUG — targeted package / "browser" trace (kDebugMode only)
  // ---------------------------------------------------------------------------

  bool _shouldTracePackage(String packageName, String? appName) {
    if (!kDebugMode) return false;
    final f = _kRelevantAppsTracePackageFilter.trim().toLowerCase();
    if (f.isNotEmpty && packageName.toLowerCase().contains(f)) return true;
    final n = (appName ?? '').toLowerCase();
    return n.contains('browser');
  }

  Map<String, InstalledAppRaw>? _traceIndexRawByPackage(List<InstalledAppRaw>? list) {
    if (list == null) return null;
    return {for (final r in list) r.packageName: r};
  }

  Set<String> _collectTracePackageKeys({
    List<InstalledAppRaw>? inventoryRawForTrace,
    required List<InstalledApp> decidedRelevant,
    required Set<String> relevantKeysBefore,
    required Map<String, String> traceAppNamesBefore,
  }) {
    final out = <String>{};
    if (inventoryRawForTrace != null) {
      for (final r in inventoryRawForTrace) {
        if (_shouldTracePackage(r.packageName, r.appName)) out.add(r.packageName);
      }
    }
    for (final a in decidedRelevant) {
      if (_shouldTracePackage(a.packageName, a.appName)) out.add(a.packageName);
    }
    for (final k in relevantKeysBefore) {
      if (_shouldTracePackage(k, traceAppNamesBefore[k])) out.add(k);
    }
    return out;
  }

  String? _traceNotRelevantReasonLabel(InstalledAppRaw raw) {
    final d = decideInstalledAppRelevance(raw);
    if (d != InstalledAppRelevanceDecision.notRelevant) return null;
    if (raw.isLaunchable != true) return 'not_launchable';
    if (raw.isSystemApp) return 'system_app';
    final norm = normalizeInstalledAppCategory(raw.category);
    if (norm == 'unknown') {
      return 'technical_noise_helper';
    }
    return 'notRelevant_category';
  }

  String _traceStaleReasonLabel(String engineReason) {
    switch (engineReason) {
      case 'newer_mutation_won':
        return 'stale_mutation_dropped';
      case 'full_inventory_superseded':
        return 'superseded_by_full_inventory';
      case 'package_newer_commit':
        return 'package_newer_op_won';
      default:
        return engineReason;
    }
  }

  String _traceAddRemovalReason(InstalledAppRaw? raw, InstalledApp? decided) {
    if (decided != null) return 'committed_realtime_add';
    if (raw == null) return 'bridge_returned_null';
    return _traceNotRelevantReasonLabel(raw) ?? 'not_relevant';
  }

  String _traceInventoryDropReason({
    required bool removedFromState,
    required bool inRaw,
    required InstalledAppRaw? row,
    required bool survivedCategorization,
  }) {
    if (!removedFromState) return 'n/a';
    if (!inRaw) return 'missing_from_raw_input';
    if (row != null && !survivedCategorization) {
      return _traceNotRelevantReasonLabel(row) ?? 'notRelevant_category';
    }
    return 'replaced_by_inventory_rebuild';
  }

  void _traceFullInventoryPackages({
    required String stage,
    required String mutationSource,
    required String kind,
    required int commitGeneration,
    required List<InstalledAppRaw>? inventoryRawForTrace,
    required List<InstalledApp> decidedRelevant,
    required Set<String> relevantKeysBefore,
    required Map<String, String> traceAppNamesBefore,
    required Map<String, InstalledAppRaw>? inRawByPackage,
    required bool committed,
    required String commitReason,
    required Map<String, InstalledApp> nextMap,
    required bool uiEmitted,
    required bool syncTriggered,
    required int relevantCountAfter,
  }) {
    if (!kDebugMode) return;
    final keys = _collectTracePackageKeys(
      inventoryRawForTrace: inventoryRawForTrace,
      decidedRelevant: decidedRelevant,
      relevantKeysBefore: relevantKeysBefore,
      traceAppNamesBefore: traceAppNamesBefore,
    );
    if (keys.isEmpty) return;

    final decidedByPkg = {for (final a in decidedRelevant) a.packageName: a};
    for (final pkg in keys) {
      final row = inRawByPackage?[pkg];
      final inRaw = row != null;
      final appLabel = row?.appName ?? decidedByPkg[pkg]?.appName ?? traceAppNamesBefore[pkg] ?? pkg;
      final rawCat = row?.category ?? 'unknown_bridge';
      final normCat =
          row != null ? normalizeInstalledAppCategory(row.category) : 'n/a_no_raw_row';
      final decisionName = row != null ? decideInstalledAppRelevance(row).name : 'n/a_no_raw_row';
      final launchable = row?.isLaunchable;
      final system = row?.isSystemApp;
      final noiseRejected = row != null &&
          normCat == 'unknown' &&
          looksLikeTechnicalOrUtilityNoise(row.appName);
      final survived = decidedByPkg.containsKey(pkg);
      final wasInState = relevantKeysBefore.contains(pkg);
      final nowInNext = nextMap.containsKey(pkg);
      final removedFromState = wasInState && !nowInNext;
      final inEngineNow = _byPackage.containsKey(pkg);
      final inEngineAfter = stage == 'pipeline_end'
          ? (inEngineNow ? 'yes' : 'no')
          : 'pending_pre_commit';
      final dropReason = stage == 'after_categorize'
          ? 'n/a'
          : _traceInventoryDropReason(
              removedFromState: removedFromState,
              inRaw: inRaw,
              row: row,
              survivedCategorization: survived,
            );

      debugPrint(
        '[RelevantAppsEngine::trace] --- $stage ---',
      );
      debugPrint(
        '[RelevantAppsEngine::trace] source=$mutationSource kind=$kind rev=$commitGeneration '
        'pkg=$pkg appName=$appLabel',
      );
      debugPrint(
        '[RelevantAppsEngine::trace] in_raw_scan=${inRaw ? 'yes' : 'no'} '
        'raw_category=$rawCat normalized_category=$normCat decision=$decisionName '
        'isLaunchable=${launchable ?? 'n/a'} isSystemApp=${system ?? 'n/a'} '
        'noise_helper_rejected=$noiseRejected survived_categorization=$survived',
      );
      debugPrint(
        '[RelevantAppsEngine::trace] was_in_relevant_state=$wasInState '
        'in_proposed_next_map=$nowInNext removed_from_relevant=$removedFromState '
        'commit_applied=$committed commit_context=$commitReason '
        'in_engine_after_step=$inEngineAfter '
        'emit=$uiEmitted sync=$syncTriggered rel_count_after=$relevantCountAfter '
        'final_drop_reason=$dropReason',
      );
    }
  }

  void _traceRealtimeAdd({
    required String stage,
    required String mutationSource,
    required int commitGeneration,
    required String packageName,
    required InstalledAppRaw? raw,
    required InstalledApp? decided,
    required bool hadKeyBefore,
    required bool? relChanged,
    required bool? rawChanged,
    required bool? committed,
    required bool? removedFromRelevantState,
    required bool? uiEmitted,
    required bool? syncTriggered,
    required int? relevantCountAfter,
    required String outcomeReason,
  }) {
    if (!kDebugMode) return;
    final appLabel = raw?.appName ?? decided?.appName ?? packageName;
    if (!_shouldTracePackage(packageName, appLabel)) return;

    final decisionName = raw != null ? decideInstalledAppRelevance(raw).name : 'n/a_no_raw';
    final rawCat = raw?.category ?? 'n/a';
    final normCat = raw != null ? normalizeInstalledAppCategory(raw.category) : 'n/a';
    final noiseRejected =
        raw != null && normCat == 'unknown' && looksLikeTechnicalOrUtilityNoise(raw.appName);

    debugPrint('[RelevantAppsEngine::trace] --- realtime_add $stage ---');
    debugPrint(
      '[RelevantAppsEngine::trace] source=$mutationSource rev=$commitGeneration pkg=$packageName '
      'appName=$appLabel had_key_before=$hadKeyBefore',
    );
    debugPrint(
      '[RelevantAppsEngine::trace] raw_category=$rawCat normalized_category=$normCat '
      'decision=$decisionName isLaunchable=${raw?.isLaunchable ?? 'n/a'} '
      'isSystemApp=${raw?.isSystemApp ?? 'n/a'} noise_helper_rejected=$noiseRejected '
      'decided_installed_app=${decided != null ? 'yes' : 'no'}',
    );
    debugPrint(
      '[RelevantAppsEngine::trace] rel_changed=$relChanged raw_changed=$rawChanged '
      'commit=$committed removed_from_relevant=$removedFromRelevantState '
      'emit=$uiEmitted sync=$syncTriggered rel_count_after=$relevantCountAfter '
      'outcome=$outcomeReason',
    );
  }

  void _traceRealtimeRemove({
    required String stage,
    required String mutationSource,
    required int commitGeneration,
    required String packageName,
    required String? appNameBefore,
    required bool? relChanged,
    required bool? rawChanged,
    required bool? committed,
    required bool? uiEmitted,
    required bool? syncTriggered,
    required int? relevantCountAfter,
    required String outcomeReason,
  }) {
    if (!kDebugMode) return;
    if (!_shouldTracePackage(packageName, appNameBefore)) return;

    debugPrint('[RelevantAppsEngine::trace] --- realtime_remove $stage ---');
    debugPrint(
      '[RelevantAppsEngine::trace] source=$mutationSource rev=$commitGeneration pkg=$packageName '
      'appName=${appNameBefore ?? 'n/a'}',
    );
    debugPrint(
      '[RelevantAppsEngine::trace] rel_changed=$relChanged raw_changed=$rawChanged '
      'commit=$committed emit=$uiEmitted sync=$syncTriggered '
      'rel_count_after=$relevantCountAfter outcome=$outcomeReason',
    );
  }

  void _logStaleDrop({
    required String source,
    required String kind,
    required int commitGeneration,
    required String? packageName,
    required String reason,
  }) {
    final pkg = packageName != null ? ' pkg=$packageName' : '';
    debugPrint(
      '[RelevantAppsEngine] stale_drop kind=$kind source=$source$pkg rev=$commitGeneration reason=$reason',
    );
  }

  void _logPipelineEnd({
    required String source,
    required String kind,
    required _Snapshot snapBefore,
    required _Snapshot snapAfter,
    required bool stateChanged,
    String? packageName,
    required bool uiEmitted,
    required bool syncTriggered,
  }) {
    final pkg = packageName != null ? ' pkg=$packageName' : '';
    final raw = ' raw=${snapBefore.rawCount}→${snapAfter.rawCount}';
    final rel = ' rel=${snapBefore.relevantCount}→${snapAfter.relevantCount}';
    debugPrint(
      '[RelevantAppsEngine] pipeline end kind=$kind source=$source$pkg changed=$stateChanged$rel$raw '
      'ui=$uiEmitted sync=$syncTriggered',
    );
  }
}

class _Snapshot {
  const _Snapshot({
    required this.relevantFingerprint,
    required this.rawCount,
    required this.relevantCount,
    required this.hydrated,
  });

  final String relevantFingerprint;
  final int rawCount;
  final int relevantCount;
  final bool hydrated;
}
