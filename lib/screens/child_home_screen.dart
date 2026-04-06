import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config/genet_config.dart';
import '../core/genet_vpn.dart';
import '../core/user_role.dart';
import '../core/vpn_remote_child.dart';
import '../features/behavior/enums/behavior_event_type.dart';
import '../features/behavior/services/behavior_logger.dart';
import '../features/child_protection/child_protection_flow.dart';
import '../features/child_protection/child_protection_models.dart';
import '../l10n/app_localizations.dart';
import '../models/child_model.dart';
import '../models/parent_message.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../models/installed_app.dart';
import '../services/installed_apps_bridge.dart';
import '../services/installed_apps_categorization.dart';
import '../services/installed_apps_periodic_fallback.dart';
import '../services/night_mode_service.dart';
import '../services/relevant_installed_apps_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import '../widgets/natural_text_field.dart';
import 'blocked_apps_times_screen.dart';
import 'child_link_screen.dart';
import 'content_library_screen.dart';
import 'role_select_screen.dart';
import 'school_schedule_screen.dart';

/// Maps local sync scheduling reasons to backend [syncRelevantApps] trigger strings.
String _mapInstalledAppsBackendTrigger(String reason) {
  return switch (reason) {
    'startup' => 'app_launch',
    'manual_refresh' => 'manual_refresh',
    'firebase_connected' => 'reconnect_recovery',
    'resume' => 'app_resume',
    'permission_granted' => 'permission_granted',
    'empty_scan_retry' => 'retry_after_empty',
    'failure_retry' => 'failure_retry',
    'active_verification' => 'active_verification',
    'identity_retry' => 'identity_retry',
    'package_added' => 'package_added',
    'package_removed' => 'package_removed',
    _ => reason,
  };
}

/// Result of reading native VPN transport + applying [_policyRequiresVpn] / [_handleVpnRequirement].
class _NativeVpnSnapshot {
  const _NativeVpnSnapshot({
    required this.protectionStatus,
    required this.permissionGranted,
    required this.running,
    required this.requireVpn,
    required this.protectionLost,
  });
  final String protectionStatus;
  final bool permissionGranted;
  final bool running;
  final bool requireVpn;
  final bool protectionLost;
}

/// Child home: connection status from Firebase only. When parent disconnects, UI updates in place.
///
/// Orchestration layout (search for section headers):
/// - Lifecycle & dispose
/// - Child-mode bootstrap (timers, listeners after role check)
/// - Installed-app sync (debounce, identity, backend trigger mapping)
/// - Trusted time / tampering
/// - Sleep lock & native night sync
/// - Protection evaluate/apply via [ChildProtectionFlow] (see `lib/features/child_protection/`)
/// - VPN policy interpretation & native VPN snapshot
/// - Firebase child-doc stream (connection + blocked-app reactions)
/// - Disconnect / reset
/// - UI build & small widgets
///
/// **Protection flow triggers (authoritative map):**
/// - [ChildProtectionFlow.evaluate] + [ChildProtectionFlow.apply]: only from [build] (each rebuild).
/// - [ChildProtectionFlow.scheduleBlockingStateSync]: [_syncBlockingState] — night timer (10s), post-frame
///   after child bootstrap, and when Firebase child doc reports a **blocked-packages list change**.
/// - [ChildProtectionFlow.resetAfterDisconnect]: [_resetDisconnectedProtectionState] on parent disconnect.
/// - [handleSleepLockState] / [VpnRemoteChildPolicy.apply]: native policy paths (Firebase, settings,
///   extension VPN tick, resume, approve button, sleep snapshot, etc.); they do **not** call evaluate/apply
///   directly but may [setState] → rebuild → evaluate/apply.
/// - Installed-app sync: does not call the flow; indirect protection updates only if Firestore/policy changes.
class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> with WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // Fields: subscriptions, connection, timers, VPN / protection, installed apps
  // ---------------------------------------------------------------------------
  static const int _trustedTimeRefreshIntervalMs = 10 * 60 * 1000;
  static const int _timeTamperToleranceMs = 90 * 1000;

  static const EventChannel _enforcementChannel = EventChannel(
    'genet/enforcement',
  );
  StreamSubscription<SyncedChildData?>? _firebaseSyncSub;
  StreamSubscription<Map<String, dynamic>?>? _sleepLockSub;
  StreamSubscription<Map<String, dynamic>>? _installedAppsChangeSub;
  StreamSubscription<dynamic>? _packageChangeFastPathSub;
  StreamSubscription<List<InstalledApp>>? _relevantLocalListSub;
  StreamSubscription<dynamic>? _enforcementSub;

  /// Single source of truth from Firebase: true = connected, false = disconnected, null = loading
  bool? _firebaseConnectionStatus;
  String? _linkedNameForDisplay;

  /// Timer: keep native prefs in sync when schedule windows cross.
  Timer? _nightCheckTimer;
  Timer? _installedAppsFallbackTimer;

  /// Re-apply VPN when extension windows start/end without waiting for the next Firestore write.
  Timer? _extensionVpnTimer;
  /// Periodic native VPN transport status monitor.
  Timer? _vpnStatusMonitorTimer;
  bool _extensionActiveLastTick = false;
  Timer? _installedAppsSyncDebounceTimer;
  bool _installedAppsSyncInFlight = false;
  bool _installedAppsSyncQueued = false;
  bool _installedAppsEmptyRetryUsed = false;
  bool _installedAppsIdentityRetryUsed = false;

  /// Remote VPN policy snapshot (child device only).
  SyncedChildData? _lastSyncedForVpn;
  bool? _vpnPermissionGranted;
  bool? _vpnRunningOnDevice;
  /// Single local protection state: protected | vpn_inactive | vpn_removed.
  String? _vpnProtectionStatus;
  /// Next-stage trigger: true when policy needs VPN but protection is lost.
  bool _vpnProtectionLostTrigger = false;
  /// on | off | error — from [VpnRemoteChildPolicy.apply]
  String _vpnIndicatorStatus = 'off';
  bool _sleepLockActive = false;
  String? _currentForegroundApp;
  ParentMessage? _parentMessage;
  DateTime _lastProtectionEvaluationTime = DateTime.now();
  DateTime? _lastTrustedTime;
  int? _lastTrustedElapsedRealtimeMs;
  int? _lastTrustedRefreshElapsedRealtimeMs;
  DateTime? _lastDeviceTimeSnapshot;
  int? _lastDeviceElapsedRealtimeMs;
  bool _timeTamperingDetected = false;
  String? _timeTamperingReason;
  List<String> _missingPermissionsForShortcuts = const [];
  final BehaviorLogger _behaviorLogger = BehaviorLogger();

  /// Skip [setState] when visible VPN/UI fields unchanged.
  String? _lastChildHomeUiFingerprint;

  late ChildProtectionFlow _childProtectionFlow;

  // ---------------------------------------------------------------------------
  // Logging & validation helpers
  // ---------------------------------------------------------------------------
  void _logCriticalEvent(String scope, Map<String, Object?> fields) {
    final payload = fields.entries
        .map((entry) => '${entry.key}: ${entry.value ?? 'null'}')
        .join(' | ');
    debugPrint('[$scope] $payload');
  }

  bool _hasSingleChildTarget({String? linkedChildId, String? selectedChildId}) {
    final linked = normalizeIdentifier(linkedChildId);
    final selected = normalizeIdentifier(selectedChildId);
    return linked == null || selected == null || linked == selected;
  }

  String _childHomeUiFingerprint({
    required SyncedChildData data,
    required String? name,
    required bool? perm,
    required bool? run,
    required String dot,
  }) {
    final sorted = List<String>.from(data.blockedPackages)..sort();
    final extKeys = data.extensionApproved.keys.toList()..sort();
    final ext = extKeys.map((k) => '$k:${data.extensionApproved[k]}').join('|');
    return '${data.connectionStatus}|${data.parentId}|${data.vpnEnabled}|${sorted.join(',')}|'
        '${data.vpnStatus}|${data.extensionRequests.length}|$ext|$name|${perm}_$run|$dot';
  }

  // ---------------------------------------------------------------------------
  // Lifecycle: initState / dispose / app resume
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _childProtectionFlow = ChildProtectionFlow(logCritical: _logCriticalEvent);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_clearVpnProtectionLostInNative());
    _startFirebaseConnectionListener();
    _startSleepLockRemoteListener();
    getUserRole().then((role) {
      if (!mounted || role != kUserRoleChild) return;
      _startChildModeOrchestration();
    });
  }

  // ---------------------------------------------------------------------------
  // Child-mode bootstrap (runs only when role == child)
  // ---------------------------------------------------------------------------
  void _startChildModeOrchestration() {
    // Keep native sleep-lock/VPN state fresh for child mode without a second in-app block route.
    unawaited(_refreshPermissionShortcuts());
    _startEnforcementListener();
    _startInstalledAppsSyncTriggers();
    _startProtectionRefreshTimers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBlockingState());
    if (Platform.isAndroid) {
      _startInstalledAppsChangeListener();
      _startVpnStatusMonitor();
    }
  }

  void _startInstalledAppsSyncTriggers() {
    _scheduleInstalledAppsSync(reason: 'startup', delay: Duration.zero);
    _installedAppsFallbackTimer?.cancel();
    _installedAppsFallbackTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(runFallbackInstalledAppsRefresh()),
    );
  }

  void _startProtectionRefreshTimers() {
    _nightCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncBlockingState(),
    );
    _extensionVpnTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickExtensionVpnWindows(),
    );
  }

  Future<void> _refreshPermissionShortcuts() async {
    if (!Platform.isAndroid) return;
    final hadMissingPermissions = _missingPermissionsForShortcuts.isNotEmpty;
    final missing = await GenetConfig.getMissingPermissions();
    if (!mounted) return;
    setState(() {
      _missingPermissionsForShortcuts = missing;
    });
    if (hadMissingPermissions && missing.isEmpty) {
      _scheduleInstalledAppsSync(
        reason: 'permission_granted',
        delay: Duration.zero,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Native: enforcement EventChannel (foreground app blocked)
  // ---------------------------------------------------------------------------
  void _startEnforcementListener() {
    _enforcementSub?.cancel();
    _enforcementSub = _enforcementChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (!mounted || event is! Map) return;
      final payload = Map<String, dynamic>.from(event);
      final type = payload['type'] as String? ?? '';
      final packageName = payload['packageName'] as String? ?? '';
      if (type != 'app_blocked' || packageName.isEmpty) return;
      setState(() => _currentForegroundApp = packageName);
    });
  }

  // ---------------------------------------------------------------------------
  // Native: periodic VPN transport status poll
  // ---------------------------------------------------------------------------
  void _startVpnStatusMonitor() {
    _vpnStatusMonitorTimer?.cancel();
    _vpnStatusMonitorTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollVpnStatus(),
    );
    _pollVpnStatus();
  }

  bool _policyRequiresVpn([SyncedChildData? data]) {
    return resolveRequireVpn(syncedChildData: data) || _requireVpn;
  }

  String _formatCurrentTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  bool _permissionGrantedFromProtectionStatus(String status) {
    return status != GenetVpn.protectionVpnRemoved;
  }

  bool _runningFromProtectionStatus(String status) {
    return status == GenetVpn.protectionProtected;
  }

  bool _requireVpn = false;

  bool _handleVpnRequirement({
    required bool requireVpn,
    required bool isVpnActive,
  }) {
    final show = requireVpn && !isVpnActive;
    debugPrint('[GenetVpn] requireVpn from Firebase=$requireVpn');
    debugPrint('[GenetVpn] current vpn state active=$isVpnActive');
    debugPrint('[GenetVpn] enforcement UI shown=$show');
    return show;
  }

  Future<void> _clearVpnProtectionLostInNative() async {
    await GenetConfig.setVpnProtectionLost(false);
  }

  Future<int> _getElapsedRealtimeMs() async {
    final monotonic = await GenetConfig.getElapsedRealtimeMs();
    return monotonic ?? DateTime.now().millisecondsSinceEpoch;
  }

  DateTime? _projectTrustedTime(int elapsedRealtimeMs) {
    final trustedTime = _lastTrustedTime;
    final trustedElapsed = _lastTrustedElapsedRealtimeMs;
    if (trustedTime == null || trustedElapsed == null) return null;
    final deltaMs = elapsedRealtimeMs - trustedElapsed;
    if (deltaMs <= 0) return trustedTime;
    return trustedTime.add(Duration(milliseconds: deltaMs));
  }

  bool _shouldRefreshTrustedTime(int elapsedRealtimeMs) {
    final lastRefresh = _lastTrustedRefreshElapsedRealtimeMs;
    if (lastRefresh == null) return true;
    return elapsedRealtimeMs - lastRefresh >= _trustedTimeRefreshIntervalMs;
  }

  void _updateProtectionTimeState({
    required DateTime effectiveTime,
    required bool tamperingDetected,
    required String? tamperingReason,
  }) {
    final tamperingChanged = _timeTamperingDetected != tamperingDetected;
    final previousReason = _timeTamperingReason;
    _lastProtectionEvaluationTime = effectiveTime;
    _timeTamperingDetected = tamperingDetected;
    _timeTamperingReason = tamperingReason;
    if (tamperingChanged) {
      debugPrint('[GenetTime] tamperingDetected=$tamperingDetected');
      debugPrint('[GenetTime] reason=${tamperingReason ?? 'none'}');
      if (mounted) {
        setState(() {});
      }
    } else if (previousReason != tamperingReason) {
      debugPrint('[GenetTime] reason=${tamperingReason ?? 'none'}');
    }
  }

  // ---------------------------------------------------------------------------
  // Trusted time / clock tampering
  // ---------------------------------------------------------------------------
  Future<DateTime> _resolveProtectionTime({
    bool forceTrustedRefresh = false,
  }) async {
    final elapsedRealtimeMs = await _getElapsedRealtimeMs();
    final deviceNow = DateTime.now();
    String? tamperingReason;

    if (_lastDeviceTimeSnapshot != null && _lastDeviceElapsedRealtimeMs != null) {
      final expectedDeltaMs = elapsedRealtimeMs - _lastDeviceElapsedRealtimeMs!;
      final actualDeltaMs =
          deviceNow.millisecondsSinceEpoch -
          _lastDeviceTimeSnapshot!.millisecondsSinceEpoch;
      final driftMs = (actualDeltaMs - expectedDeltaMs).abs();
      if (expectedDeltaMs >= 0 && driftMs > _timeTamperToleranceMs) {
        tamperingReason = 'local_clock_jump';
      }
    }

    var trustedNow = _projectTrustedTime(elapsedRealtimeMs);
    if (forceTrustedRefresh || _shouldRefreshTrustedTime(elapsedRealtimeMs)) {
      final childId = await getLinkedChildId();
      if (childId != null && childId.isNotEmpty) {
        final fetchedTrustedTime = await fetchTrustedTimeFromFirebase(childId);
        if (fetchedTrustedTime != null) {
          _lastTrustedTime = fetchedTrustedTime;
          _lastTrustedElapsedRealtimeMs = elapsedRealtimeMs;
          _lastTrustedRefreshElapsedRealtimeMs = elapsedRealtimeMs;
          trustedNow = fetchedTrustedTime;
          debugPrint(
            '[GenetTime] trusted time refreshed=${fetchedTrustedTime.toIso8601String()}',
          );
        } else {
          debugPrint('[GenetTime] trusted time unavailable, using safe fallback');
        }
      }
    }

    if (trustedNow != null) {
      final trustedDriftMs =
          (deviceNow.millisecondsSinceEpoch - trustedNow.millisecondsSinceEpoch)
              .abs();
      if (trustedDriftMs > _timeTamperToleranceMs) {
        tamperingReason ??= 'trusted_time_mismatch';
      }
    }

    _lastDeviceTimeSnapshot = deviceNow;
    _lastDeviceElapsedRealtimeMs = elapsedRealtimeMs;
    final effectiveTime = trustedNow ?? deviceNow;
    _updateProtectionTimeState(
      effectiveTime: effectiveTime,
      tamperingDetected: tamperingReason != null,
      tamperingReason: tamperingReason,
    );
    return effectiveTime;
  }

  // ---------------------------------------------------------------------------
  // Sleep lock, night service, and native VPN policy application
  // ---------------------------------------------------------------------------
  Future<String> handleSleepLockState({
    SyncedChildData? data,
  }) async {
    if (!mounted || !Platform.isAndroid) return _vpnIndicatorStatus;
    final role = await getUserRole();
    if (!mounted || role != kUserRoleChild) return _vpnIndicatorStatus;
    final synced = data ?? _lastSyncedForVpn;
    if (synced == null) return _vpnIndicatorStatus;
    final night = context.read<NightModeService>();
    if (!night.isLoaded) {
      await night.load();
      if (!mounted) return _vpnIndicatorStatus;
    }
    final previousTamperingDetected = _timeTamperingDetected;
    final sleepEnabled = night.config.enabled;
    final sleepStartTime = night.config.startTime;
    final sleepEndTime = night.config.endTime;
    final now = await _resolveProtectionTime();
    final insideSleepWindow =
        sleepEnabled &&
        NightModeService.isWithinWindow(
          startTime: sleepStartTime,
          endTime: sleepEndTime,
          currentTime: now,
        );
    final sleepLockActive = insideSleepWindow;
    final restrictionActive = sleepLockActive || _timeTamperingDetected;
    final effectiveVpnEnabled = restrictionActive;
    final currentProtectionStatus = await GenetVpn.getVpnProtectionStatus();
    final currentVpnActive =
        currentProtectionStatus == GenetVpn.protectionProtected;
    final previousRestrictionActive =
        _sleepLockActive || previousTamperingDetected;
    final nextRestrictionActive = restrictionActive;
    final actionParts = <String>[];
    if (effectiveVpnEnabled && !currentVpnActive) {
      actionParts.add('start vpn');
    } else if (!effectiveVpnEnabled && currentVpnActive) {
      actionParts.add('stop vpn');
    }
    if (previousRestrictionActive != nextRestrictionActive) {
      actionParts.add(
        nextRestrictionActive ? 'enable restriction' : 'disable restriction',
      );
    }
    final actionTaken = actionParts.isEmpty ? 'no change' : actionParts.join(' + ');
    debugPrint('[GenetVpn] sleep lock enabled=$sleepEnabled');
    debugPrint('[GenetVpn] sleep start time=$sleepStartTime');
    debugPrint('[GenetVpn] sleep end time=$sleepEndTime');
    debugPrint('[GenetVpn] current time=${_formatCurrentTime(now)}');
    debugPrint('[GenetVpn] insideSleepWindow=$insideSleepWindow');
    debugPrint('[GenetVpn] sleepLockActive final value=$sleepLockActive');
    debugPrint('[GenetTime] timeTamperingDetected=$_timeTamperingDetected');
    debugPrint('[GenetTime] effectiveProtectionTime=${now.toIso8601String()}');
    debugPrint('[GenetVpn] current VPN state=$currentProtectionStatus');
    debugPrint('[GenetVpn] restriction mode active=$restrictionActive');
    debugPrint('[GenetVpn] action taken: $actionTaken');
    if (_sleepLockActive != sleepLockActive && mounted) {
      setState(() => _sleepLockActive = sleepLockActive);
    } else {
      _sleepLockActive = sleepLockActive;
    }
    await GenetConfig.setNightModeActive(restrictionActive);
    return VpnRemoteChildPolicy.apply(
      synced,
      overrideVpnEnabled: effectiveVpnEnabled,
      currentTimeMs: now.millisecondsSinceEpoch,
    );
  }

  // ---------------------------------------------------------------------------
  // Installed-app sync: device events → debounced Firebase upload
  // ---------------------------------------------------------------------------
  void _startInstalledAppsChangeListener() {
    _installedAppsChangeSub?.cancel();
    _installedAppsChangeSub = GenetConfig.watchInstalledAppsChanges().listen((event) {
      final action = event['action'] as String? ?? '';
      final packageName = event['package'] as String? ?? '';
      _scheduleInstalledAppsSync(reason: '$action:$packageName');
    });
    InstalledAppsBridge.ensurePackageChangeInboundHandler();
    _packageChangeFastPathSub?.cancel();
    _packageChangeFastPathSub = InstalledAppsBridge.packageChangeStream.listen((event) {
      notifyInstalledAppsRealtimePackageEvent();
      unawaited(RelevantInstalledAppsEngine.instance.handlePackageChangeEvent(event));
    });
    _relevantLocalListSub?.cancel();
    _relevantLocalListSub =
        RelevantInstalledAppsEngine.instance.relevantListStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _scheduleInstalledAppsSync({
    required String reason,
    Duration delay = const Duration(milliseconds: 700),
  }) {
    if (!mounted || !Platform.isAndroid) return;
    _logCriticalEvent('RELEVANT_APPS', {
      'childRefreshStarted': reason,
    });
    _installedAppsSyncDebounceTimer?.cancel();
    _installedAppsSyncDebounceTimer = Timer(delay, () {
      unawaited(_syncInstalledAppsToFirebase(reason: reason));
    });
  }

  Future<void> _syncInstalledAppsToFirebase({
    required String reason,
  }) async {
    if (!mounted || !Platform.isAndroid) return;
    final role = await getUserRole();
    if (!mounted || role != kUserRoleChild) {
      _logCriticalEvent('RELEVANT_APPS', {
        'syncSkippedReason': 'role_not_child',
      });
      return;
    }
    final parentId = normalizeIdentifier(await getLinkedParentId());
    final childId = normalizeIdentifier(await getLinkedChildId());
    if (!mounted || parentId == null || childId == null) {
      _logCriticalEvent('RELEVANT_APPS', {
        'syncSkippedReason': 'identity_not_ready',
        'parentId': parentId ?? 'missing',
        'childId': childId ?? 'missing',
      });
      if (!_installedAppsIdentityRetryUsed) {
        _installedAppsIdentityRetryUsed = true;
        _scheduleInstalledAppsSync(
          reason: 'identity_retry',
          delay: const Duration(seconds: 2),
        );
      }
      return;
    }
    _logCriticalEvent('RELEVANT_APPS', {
      'childIdentityReady': true,
      'parentId': parentId,
      'childId': childId,
    });
    if (_installedAppsSyncInFlight) {
      _logCriticalEvent('RELEVANT_APPS', {
        'syncSkippedReason': 'sync_in_flight',
      });
      _installedAppsSyncQueued = true;
      return;
    }
    _installedAppsSyncInFlight = true;
    try {
      final trigger = _mapInstalledAppsBackendTrigger(reason);
      _logCriticalEvent('RELEVANT_APPS', {
        'syncRelevantAppsStarted': trigger,
      });
      final rawList = await InstalledAppsBridge.fetchInstalledAppsRaw();
      final relevantApps = categorizeInstalledApps(rawList);
      RelevantInstalledAppsEngine.instance.applyFullRelevantState(
        relevantApps,
        rawList.length,
      );
      final syncedCount = await syncRelevantApps(
        childId: childId,
        relevantApps: relevantApps,
        rawInstalledAppCount: rawList.length,
        trigger: trigger,
      );
      _logCriticalEvent('RELEVANT_APPS', {
        'syncRelevantAppsFinished': true,
        'classifiedRelevantCount': syncedCount,
      });
      _installedAppsIdentityRetryUsed = false;
      if (syncedCount > 0) {
        _installedAppsEmptyRetryUsed = false;
      } else if (!_installedAppsEmptyRetryUsed) {
        _installedAppsEmptyRetryUsed = true;
        debugPrint('[RELEVANT_APPS] lastSyncTriggerReason=retry_after_empty');
        _scheduleInstalledAppsSync(
          reason: 'empty_scan_retry',
          delay: const Duration(seconds: 2),
        );
      }
    } catch (e, st) {
      debugPrint('[RELEVANT_APPS] syncInstalledApps unexpected: $e $st');
    } finally {
      _installedAppsSyncInFlight = false;
      if (_installedAppsSyncQueued) {
        _installedAppsSyncQueued = false;
        _scheduleInstalledAppsSync(
          reason: 'queued_followup',
          delay: const Duration(milliseconds: 400),
        );
      }
    }
  }

  void _logProtectionStatusTransition({
    required String? previousStatus,
    required String nextStatus,
  }) {
    if (previousStatus == nextStatus) return;
    switch (nextStatus) {
      case GenetVpn.protectionProtected:
        debugPrint('GENET_VPN: VPN ACTIVE');
        break;
      case GenetVpn.protectionVpnRemoved:
        debugPrint('GENET_VPN: VPN REMOVED OR NOT CONFIGURED');
        break;
      default:
        debugPrint('GENET_VPN: VPN INACTIVE');
    }
  }

  void _logProtectionLossTransition({
    required bool previousLost,
    required bool nextLost,
    required String nextStatus,
  }) {
    if (!previousLost && nextLost) {
      debugPrint('GENET_VPN: PROTECTION LOST');
    } else if (previousLost && !nextLost) {
      if (nextStatus == GenetVpn.protectionProtected) {
        debugPrint('GENET_VPN: PROTECTION RESTORED');
      }
    }
  }

  Future<void> _logBehaviorEvent({
    required BehaviorEventType eventType,
    String? appPackage,
    Map<String, dynamic>? metadata,
  }) async {
    final childId = await getLinkedChildId();
    if (childId == null || childId.isEmpty) return;
    await _behaviorLogger.logEvent(
      childId: childId,
      eventType: eventType,
      appPackage: appPackage,
      metadata: metadata,
    );
  }

  // ---------------------------------------------------------------------------
  // Native VPN permission / running / “protection lost” snapshot
  // ---------------------------------------------------------------------------
  Future<_NativeVpnSnapshot?> _readNativeVpnSnapshotForSyncedPolicy(
    SyncedChildData synced,
  ) async {
    if (!mounted) return null;
    final protectionStatus = await GenetVpn.getVpnProtectionStatus();
    final permissionGranted =
        _permissionGrantedFromProtectionStatus(protectionStatus);
    final running = _runningFromProtectionStatus(protectionStatus);
    final requireVpn = _policyRequiresVpn(synced);
    final protectionLost = _handleVpnRequirement(
      requireVpn: requireVpn,
      isVpnActive: protectionStatus == GenetVpn.protectionProtected,
    );
    if (!mounted) return null;
    return _NativeVpnSnapshot(
      protectionStatus: protectionStatus,
      permissionGranted: permissionGranted,
      running: running,
      requireVpn: requireVpn,
      protectionLost: protectionLost,
    );
  }

  void _applyVpnProtectionSnapshot({
    required String protectionStatus,
    required bool permissionGranted,
    required bool running,
    required bool protectionLost,
    required bool requireVpn,
    String? vpnIndicatorStatus,
  }) {
    _logProtectionStatusTransition(
      previousStatus: _vpnProtectionStatus,
      nextStatus: protectionStatus,
    );
    _logProtectionLossTransition(
      previousLost: _vpnProtectionLostTrigger,
      nextLost: protectionLost,
      nextStatus: protectionStatus,
    );
    final changed = _vpnProtectionStatus != protectionStatus ||
        _vpnPermissionGranted != permissionGranted ||
        _vpnRunningOnDevice != running ||
        _vpnProtectionLostTrigger != protectionLost ||
        (vpnIndicatorStatus != null && _vpnIndicatorStatus != vpnIndicatorStatus);
    if (!changed || !mounted) return;
    final prevLost = _vpnProtectionLostTrigger;
    setState(() {
      _vpnProtectionStatus = protectionStatus;
      _vpnPermissionGranted = permissionGranted;
      _vpnRunningOnDevice = running;
      _vpnProtectionLostTrigger = protectionLost;
      if (vpnIndicatorStatus != null) {
        _vpnIndicatorStatus = vpnIndicatorStatus;
      }
    });
    if (protectionLost != prevLost) {
      unawaited(GenetConfig.setVpnProtectionLost(protectionLost));
    }
    _logCriticalEvent('GenetVpn', {
      'VPN STATUS': protectionStatus,
      'VPN PERMISSION': permissionGranted,
      'VPN RUNNING': running,
      'VPN ENFORCEMENT LOST': protectionLost,
      'REQUIRE VPN': requireVpn,
    });
  }

  Future<void> _pollVpnStatus() async {
    if (!mounted || !Platform.isAndroid) return;
    final role = await getUserRole();
    if (!mounted || role != kUserRoleChild) return;
    try {
      final protectionStatus = await GenetVpn.getVpnProtectionStatus();
      final requireVpn = _policyRequiresVpn();
      final protectionLost = _handleVpnRequirement(
        requireVpn: requireVpn,
        isVpnActive: protectionStatus == GenetVpn.protectionProtected,
      );
      final permissionGranted =
          _permissionGrantedFromProtectionStatus(protectionStatus);
      final running = _runningFromProtectionStatus(protectionStatus);
      _applyVpnProtectionSnapshot(
        protectionStatus: protectionStatus,
        permissionGranted: permissionGranted,
        running: running,
        protectionLost: protectionLost,
        requireVpn: requireVpn,
      );
    } catch (_) {
      debugPrint('GENET_VPN: VPN CHECK FAILED');
    }
  }

  void _tickExtensionVpnWindows() {
    if (!mounted) return;
    getUserRole().then((role) async {
      if (!mounted || role != kUserRoleChild || !Platform.isAndroid) return;
      final d = _lastSyncedForVpn;
      if (d == null || d.blockedPackages.isEmpty) return;
      final now =
          (_projectTrustedTime(await _getElapsedRealtimeMs()) ??
                  _lastProtectionEvaluationTime)
              .millisecondsSinceEpoch;
      final anyActive =
          d.extensionApproved.entries.any((e) => (e.value) > now);
      if (!anyActive && !_extensionActiveLastTick) return;
      _extensionActiveLastTick = anyActive;
      final vpnDot = await handleSleepLockState(data: d);
      if (!mounted) return;
      final snap = await _readNativeVpnSnapshotForSyncedPolicy(d);
      if (snap == null || !mounted) return;
      _applyVpnProtectionSnapshot(
        protectionStatus: snap.protectionStatus,
        permissionGranted: snap.permissionGranted,
        running: snap.running,
        protectionLost: snap.protectionLost,
        requireVpn: snap.requireVpn,
        vpnIndicatorStatus: vpnDot,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Protection refresh entry (periodic timer → sleep policy + native sync)
  // Routes to [ChildProtectionFlow.scheduleBlockingStateSync] only — no evaluate/apply here.
  // ---------------------------------------------------------------------------
  void _syncBlockingState() {
    _childProtectionFlow.scheduleBlockingStateSync(
      mounted: () => mounted,
      getUserRole: getUserRole,
      expectedChildRole: kUserRoleChild,
      runSleepLockPolicy: ({data}) async {
        await handleSleepLockState(data: data);
      },
      syncNightNativeOnly: _syncNightNativeOnly,
    );
  }

  void _mergeParentMessageIfChanged(ParentMessage? next) {
    final currentUpdatedAt = _parentMessage?.updatedAt.millisecondsSinceEpoch;
    final nextUpdatedAt = next?.updatedAt.millisecondsSinceEpoch;
    if (_parentMessage?.body != next?.body || currentUpdatedAt != nextUpdatedAt) {
      setState(() => _parentMessage = next);
    }
  }

  // ---------------------------------------------------------------------------
  // Remote child_settings stream (requireVpn, parent messages, sleepLock payload)
  // ---------------------------------------------------------------------------
  /// Remote Sleep Lock from Firebase → prefs + [NightModeService] → native (child device only).
  void _startSleepLockRemoteListener() {
    getLinkedChildId().then((cid) {
      if (!mounted || cid == null || cid.isEmpty) return;
      developer.log(
        'CHILD_SETTINGS child listen childId=$cid path=child_settings/$cid',
        name: 'Sync',
      );
      _sleepLockSub = watchChildSettingsStream(cid).listen((data) async {
        await _applyRemoteChildSettingsSnapshot(data);
      });
    });
  }

  Future<void> _applyRemoteChildSettingsSnapshot(Map<String, dynamic>? data) async {
    if (!mounted || data == null) {
      _logCriticalEvent('GenetDebug', {
        'CHILD SETTINGS SNAPSHOT': 'missing',
      });
      return;
    }
    final requireVpn = resolveRequireVpn(childSettingsData: data);
    if (_requireVpn != requireVpn) {
      _logCriticalEvent('GenetVpn', {
        'REQUIRE VPN SOURCE': 'firebase',
        'REQUIRE VPN': requireVpn,
      });
      setState(() => _requireVpn = requireVpn);
      unawaited(_pollVpnStatus());
    }
    _mergeParentMessageIfChanged(latestParentMessageFromChildSettings(data));
    final sleepLockRaw = data['sleepLock'];
    if (sleepLockRaw is Map<String, dynamic>) {
      await _applySleepLockSnapshot(sleepLockRaw);
    } else if (sleepLockRaw is Map) {
      await _applySleepLockSnapshot(Map<String, dynamic>.from(sleepLockRaw));
    }
  }

  /// Applies remote sleep lock to prefs/native (enforcement is Android-only, no in-app overlay).
  Future<void> _applySleepLockSnapshot(Map<String, dynamic>? data) async {
    if (!mounted || data == null) {
      _logCriticalEvent('GenetTime', {
        'SLEEP LOCK SNAPSHOT': 'missing',
      });
      return;
    }
    final now = _lastProtectionEvaluationTime;
    final isActive = data['isActive'] as bool? ?? false;
    final startTime = data['startTime'] as String? ?? '22:00';
    final endTime = data['endTime'] as String? ?? '07:00';
    final isInRange = isActive &&
        NightModeService.isWithinWindow(
          startTime: startTime,
          endTime: endTime,
          currentTime: now,
        );
    _logCriticalEvent('GenetTime', {
      'SLEEP LOCK': isActive,
      'START TIME': startTime,
      'END TIME': endTime,
      'IN WINDOW': isInRange,
      'EVALUATED AT': _formatCurrentTime(now),
    });
    if (!mounted) return;
    final night = context.read<NightModeService>();
    if (!night.isLoaded) await night.load();
    if (!mounted) return;
    await night.saveConfig(
      night.config.copyWith(
        enabled: isActive,
        startTime: startTime,
        endTime: endTime,
      ),
    );
    developer.log(
      'SLEEP_LOCK child applied isActive=$isActive start=$startTime end=$endTime lockActive=$isActive',
      name: 'Sync',
    );
    await GenetConfig.syncToNativeAfterRemoteChildDoc();
    await handleSleepLockState();
    if (!mounted) return;
    setState(() {});
    _syncNightNativeOnly();
  }

  /// Sleep / night lock is enforced only by Android (Accessibility overlay), never via in-app [Navigator] routes.
  void _syncNightNativeOnly() {
    if (!mounted) return;
    final night = context.read<NightModeService>();
    if (!night.isLoaded) {
      night.load().then((_) {
        if (mounted) _syncNightNativeOnly();
      });
      return;
    }
    GenetConfig.syncToNativeAfterRemoteChildDoc();
  }

  void _resetDisconnectedProtectionState() {
    _childProtectionFlow.resetAfterDisconnect();
    setState(() {
      _firebaseConnectionStatus = false;
      _linkedNameForDisplay = null;
      _lastSyncedForVpn = null;
      _installedAppsSyncQueued = false;
      _installedAppsEmptyRetryUsed = false;
      _installedAppsIdentityRetryUsed = false;
      _requireVpn = false;
      _sleepLockActive = false;
      _currentForegroundApp = null;
      _parentMessage = null;
      _lastProtectionEvaluationTime = DateTime.now();
      _lastTrustedTime = null;
      _lastTrustedElapsedRealtimeMs = null;
      _lastTrustedRefreshElapsedRealtimeMs = null;
      _lastDeviceTimeSnapshot = null;
      _lastDeviceElapsedRealtimeMs = null;
      _timeTamperingDetected = false;
      _timeTamperingReason = null;
      _vpnProtectionStatus = null;
      _vpnPermissionGranted = null;
      _vpnRunningOnDevice = null;
      _vpnProtectionLostTrigger = false;
      _vpnIndicatorStatus = 'off';
    });
  }

  // ---------------------------------------------------------------------------
  // Firebase: watch synced child document (connection + policy updates)
  // ---------------------------------------------------------------------------
  Future<void> _onSyncedChildDataEvent(
    SyncedChildData? data,
    String childId,
  ) async {
    if (!mounted) return;
    final role = await getUserRole();
    final status = data?.connectionStatus;
    final docParentId = data?.parentId;
    _logCriticalEvent('GenetDebug', {
      'ROLE': role,
      'PARENT ID': docParentId,
      'CHILD ID': childId,
      'CONNECTION STATUS': status ?? 'null',
    });
    // Only treat as disconnected when Firebase explicitly says so (doc exists and status/parentId indicate disconnect).
    // Do NOT treat null data as disconnect: doc may not exist yet right after connect (race).
    if (data == null) {
      developer.log('Child connection status: no doc yet (loading), not disconnecting', name: 'Sync');
      return;
    }
    final isConnected = isConnectionStatusConnected(status) &&
        (docParentId != null && docParentId.isNotEmpty);
    if (isConnected) {
      developer.log('Child connected (from Firebase)', name: 'Sync');
      final wasConnected = _firebaseConnectionStatus == true;
      if (!wasConnected && Platform.isAndroid) {
        _scheduleInstalledAppsSync(
          reason: 'firebase_connected',
          delay: Duration.zero,
        );
      }
      final name = await getLinkedChildName();
      if (role == kUserRoleChild && Platform.isAndroid) {
        final oldVpn = _lastSyncedForVpn?.vpnEnabled;
        final oldBlocked = _lastSyncedForVpn?.blockedPackages;
        debugPrint('[GenetVpn] child realtime listener fired');
        debugPrint('[GenetVpn] old vpnEnabled=$oldVpn new vpnEnabled=${data.vpnEnabled}');
        if (oldBlocked != null) {
          final a = List<String>.from(oldBlocked)..sort();
          final b = List<String>.from(data.blockedPackages)..sort();
          if (a.join(',') != b.join(',')) {
            _logCriticalEvent('GenetProtect', {
              'BLOCKED APPS COUNT': b.length,
              'BLOCKED APPS UPDATE': 'received',
            });
            _syncBlockingState();
          }
        }
        final vpnDot = await handleSleepLockState(data: data);
        final snap = await _readNativeVpnSnapshotForSyncedPolicy(data);
        if (snap == null || !mounted) return;
        final uiFp = _childHomeUiFingerprint(
          data: data,
          name: name,
          perm: snap.permissionGranted,
          run: snap.running,
          dot: vpnDot,
        );
        if (uiFp == _lastChildHomeUiFingerprint) {
          debugPrint('[GenetVpn] skipped duplicate setState');
          _lastSyncedForVpn = data;
          return;
        }
        _lastChildHomeUiFingerprint = uiFp;
        if (_vpnIndicatorStatus != vpnDot) {
          debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
        }
        setState(() {
          _firebaseConnectionStatus = true;
          _linkedNameForDisplay = name;
          _lastSyncedForVpn = data;
        });
        _applyVpnProtectionSnapshot(
          protectionStatus: snap.protectionStatus,
          permissionGranted: snap.permissionGranted,
          running: snap.running,
          protectionLost: snap.protectionLost,
          requireVpn: snap.requireVpn,
          vpnIndicatorStatus: vpnDot,
        );
      } else if (mounted) {
        setState(() {
          _firebaseConnectionStatus = true;
          _linkedNameForDisplay = name;
        });
      }
    } else {
      developer.log('Child disconnected (from Firebase) status=$status parentId=$docParentId', name: 'Sync');
      await _handleDisconnected();
    }
  }

  Future<void> _startFirebaseConnectionListener() async {
    final parentId = normalizeIdentifier(await getLinkedParentId());
    final childId = normalizeIdentifier(await getLinkedChildId());
    if (parentId == null || childId == null) {
      developer.log('Child connection status: no parentId or childId, showing disconnected', name: 'Sync');
      if (mounted) setState(() => _firebaseConnectionStatus = false);
      return;
    }
    _logCriticalEvent('GenetDebug', {
      'ROLE': await getUserRole(),
      'PARENT ID': parentId,
      'CHILD ID': childId,
      'READ PATH': 'genet_parents/$parentId/children/$childId',
    });
    developer.log('CHILD_READ_PATH = genet_parents/$parentId/children/$childId', name: 'Sync');
    developer.log('CHILD_READ_CHILD_ID = $childId', name: 'Sync');
    if (mounted) setState(() => _firebaseConnectionStatus = null);
    _firebaseSyncSub = watchSyncedChildDataStream(parentId, childId).listen(
      (data) => unawaited(_onSyncedChildDataEvent(data, childId)),
    );
  }

  void _tearDownExtensionAndFirebaseListenersOnDisconnect() {
    VpnRemoteChildPolicy.resetPushDedupe();
    _extensionVpnTimer?.cancel();
    _extensionVpnTimer = null;
    _extensionActiveLastTick = false;
    _lastChildHomeUiFingerprint = null;
    _sleepLockSub?.cancel();
    _sleepLockSub = null;
    _firebaseSyncSub?.cancel();
    _firebaseSyncSub = null;
  }

  // ---------------------------------------------------------------------------
  // Disconnect: native teardown, identity cleanup, local protection reset
  // ---------------------------------------------------------------------------
  Future<void> _handleDisconnected() async {
    if (Platform.isAndroid) {
      await GenetVpn.stopVpn();
      debugPrint('[GenetVpn] child stopVpn triggered (disconnected from parent)');
    }
    _tearDownExtensionAndFirebaseListenersOnDisconnect();
    final selectedChildId = normalizeIdentifier(await getSelectedChildId());
    final linkedChildId = normalizeIdentifier(await getLinkedChildId());
    if (!_hasSingleChildTarget(
      linkedChildId: linkedChildId,
      selectedChildId: selectedChildId,
    )) {
      _logCriticalEvent('GenetDebug', {
        'VALIDATION': 'selected child mismatch on disconnect',
        'LINKED CHILD ID': linkedChildId,
        'SELECTED CHILD ID': selectedChildId,
      });
    }
    await setLinkedChild(null, null);
    await setLinkedParentId(null);
    if (!mounted) return;
    _resetDisconnectedProtectionState();
    unawaited(_clearVpnProtectionLostInNative());
    unawaited(GenetConfig.setNightModeActive(false));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקישור להורה הוסר. ניתן להתחבר מחדש.'),
        ),
      );
    }
  }

  void _disposeChildHomeTimers() {
    _nightCheckTimer?.cancel();
    _installedAppsFallbackTimer?.cancel();
    _extensionVpnTimer?.cancel();
    _installedAppsSyncDebounceTimer?.cancel();
    _vpnStatusMonitorTimer?.cancel();
  }

  void _disposeChildHomeStreamSubscriptions() {
    _installedAppsChangeSub?.cancel();
    _packageChangeFastPathSub?.cancel();
    _relevantLocalListSub?.cancel();
    RelevantInstalledAppsEngine.instance.reset();
    resetInstalledAppsFallbackGuards();
    _enforcementSub?.cancel();
    _sleepLockSub?.cancel();
    _firebaseSyncSub?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeChildHomeTimers();
    _disposeChildHomeStreamSubscriptions();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _currentForegroundApp = null;
      unawaited(_refreshPermissionShortcuts());
      _scheduleInstalledAppsSync(
        reason: 'resume',
        delay: const Duration(milliseconds: 300),
      );
      _syncVpnAfterResume();
    }
  }

  Future<void> _syncVpnAfterResume() async {
    if (!mounted || !Platform.isAndroid) return;
    final d = _lastSyncedForVpn;
    if (d == null) return;
    final role = await getUserRole();
    if (role != kUserRoleChild) return;
    final vpnDot = await handleSleepLockState(data: d);
    if (!mounted) return;
    final snap = await _readNativeVpnSnapshotForSyncedPolicy(d);
    if (snap == null || !mounted) return;
    final name = await getLinkedChildName();
    if (!mounted) return;
    final uiFp = _childHomeUiFingerprint(
      data: d,
      name: name,
      perm: snap.permissionGranted,
      run: snap.running,
      dot: vpnDot,
    );
    _lastChildHomeUiFingerprint = uiFp;
    if (_vpnIndicatorStatus != vpnDot) {
      debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
    }
    if (mounted) {
      _applyVpnProtectionSnapshot(
        protectionStatus: snap.protectionStatus,
        permissionGranted: snap.permissionGranted,
        running: snap.running,
        protectionLost: snap.protectionLost,
        requireVpn: snap.requireVpn,
        vpnIndicatorStatus: vpnDot,
      );
    }
  }

  ChildProtectionEvaluateInputs _buildProtectionInputs() {
    final protectionTime = _lastProtectionEvaluationTime;
    return ChildProtectionEvaluateInputs(
      isVpnActive: _vpnProtectionStatus == GenetVpn.protectionProtected,
      sleepLockActive: _sleepLockActive,
      protectionTime: protectionTime,
      requireNetworkProtectionScreen: _requireVpn,
      networkProtectionRelevant: _vpnProtectionLostTrigger,
      blockedApps: _lastSyncedForVpn == null
          ? const <String>[]
          : VpnRemoteChildPolicy.effectiveBlockedPackages(
              _lastSyncedForVpn!,
              currentTimeMs: protectionTime.millisecondsSinceEpoch,
            ),
    );
  }

  String _vpnStatusTitle() {
    final d = _lastSyncedForVpn;
    if (d == null) return '…';
    if (!_requireVpn) return 'הגנת רשת: לא נדרשת';
    if (d.blockedPackages.isEmpty) return 'הגנת רשת: אין אפליקציות חסומות ברשימה';
    final g = _vpnPermissionGranted == true;
    final run = _vpnRunningOnDevice == true;
    if (!g) return 'הגנת רשת לא אושרה';
    if (run) return 'הגנת רשת פעילה';
    return 'הגנת רשת מאושרת';
  }

  Future<void> _onApproveNetworkProtection() async {
    final d = _lastSyncedForVpn;
    if (d == null || !_requireVpn || d.blockedPackages.isEmpty) return;
    await GenetVpn.setBlockedApps(
      VpnRemoteChildPolicy.effectiveBlockedPackages(
        d,
        currentTimeMs: _lastProtectionEvaluationTime.millisecondsSinceEpoch,
      ),
    );
    if (await GenetVpn.isVpnPermissionGranted()) {
      debugPrint('[GenetVpn] approval button: permission already granted, apply only (no startVpn for consent)');
      debugPrint('[GenetVpn] result of VpnService.prepare()=already_granted');
    } else {
      debugPrint('[GenetVpn] VPN start requested');
      final r = await GenetVpn.startVpn();
      debugPrint('[GenetVpn] approval flow startVpn result=$r');
      debugPrint('[GenetVpn] result of VpnService.prepare() needsPermission=${r?['needsPermission'] == true}');
    }
    if (!mounted) return;
    final vpnDot = await handleSleepLockState(data: d);
    final snap = await _readNativeVpnSnapshotForSyncedPolicy(d);
    if (snap == null || !mounted) return;
    final name = await getLinkedChildName();
    if (!mounted) return;
    final uiFp = _childHomeUiFingerprint(
      data: d,
      name: name,
      perm: snap.permissionGranted,
      run: snap.running,
      dot: vpnDot,
    );
    _lastChildHomeUiFingerprint = uiFp;
    if (_vpnIndicatorStatus != vpnDot) {
      debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
    }
    if (mounted) {
      _applyVpnProtectionSnapshot(
        protectionStatus: snap.protectionStatus,
        permissionGranted: snap.permissionGranted,
        running: snap.running,
        protectionLost: snap.protectionLost,
        requireVpn: snap.requireVpn,
        vpnIndicatorStatus: vpnDot,
      );
    }
  }

  Widget _buildVpnStatusDot(String status) {
    final Color c;
    switch (status) {
      case 'on':
        c = Colors.green;
        break;
      case 'error':
        c = Colors.amber.shade700;
        break;
      default:
        c = Colors.red;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

  // ---------------------------------------------------------------------------
  // UI: scaffold, connection cards, navigation
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    context.watch<NightModeService>();
    // Sole active evaluate/apply site: dedupe inside [ChildProtectionFlow] limits log/side-effect spam.
    final evaluateInputs = _buildProtectionInputs();
    final protectionState = _childProtectionFlow.evaluate(
      ChildProtectionEvaluationContext(
        inputs: evaluateInputs,
        currentForegroundApp: _currentForegroundApp,
        vpnProtectionStatusLabel: _vpnProtectionStatus,
        timeTamperingDetected: _timeTamperingDetected,
        timeTamperingReason: _timeTamperingReason,
      ),
    );
    final protectionUi = _childProtectionFlow.apply(
      protectionState,
      ChildProtectionApplyBindings(
        runSleepLockPolicy: ({data}) async {
          await handleSleepLockState(data: data);
        },
        logBehaviorEvent: _logBehaviorEvent,
        getForegroundApp: () => _currentForegroundApp,
        clearForegroundApp: () => _currentForegroundApp = null,
      ),
      timeTamperingReason: _timeTamperingReason,
    );

    if (protectionUi != null) {
      return protectionUi;
    }

    final parentMessage = _parentMessage;

    return Scaffold(
            appBar: AppBar(
              title: Text(l10n.childHomeTitle),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.backToRoleSelect,
                onPressed: () async {
                  await GenetConfig.commitUserRole(kUserRoleParent);
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const RoleSelectScreen()),
                    (route) => false,
                  );
                },
              ),
              actions: const [LanguageSwitcher()],
            ),
            body: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                ChildModel.load(),
                getLinkedChildName(),
                getChildSelfProfile(),
              ]),
              builder: (context, snapshot) {
                final hasData = snapshot.connectionState == ConnectionState.done && snapshot.data != null && snapshot.data!.length >= 3;
                ChildModel? child;
                String? linkedName;
                Map<String, dynamic>? selfProfile;
                if (hasData) {
                  child = snapshot.data![0] as ChildModel?;
                  linkedName = snapshot.data![1] as String?;
                  selfProfile = snapshot.data![2] as Map<String, dynamic>?;
                  if (child == null && selfProfile != null && selfProfile.isNotEmpty) {
                    final first = selfProfile[kChildSelfProfileFirstName] as String? ?? '';
                    final last = selfProfile[kChildSelfProfileLastName] as String? ?? '';
                    final name = [first, last].join(' ').trim();
                    final age = (selfProfile[kChildSelfProfileAge] as num?)?.toInt() ?? 0;
                    final schoolCode = selfProfile[kChildSelfProfileSchoolCode] as String? ?? '';
                    if (name.isNotEmpty || age > 0 || schoolCode.isNotEmpty) {
                      child = ChildModel(name: name, age: age, schoolCode: schoolCode);
                    }
                  }
                }
                final isConnected = _firebaseConnectionStatus == true;
                return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isConnected && Platform.isAndroid) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Expanded(
                              child: Text(
                                _vpnStatusTitle(),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                            _buildVpnStatusDot(_vpnIndicatorStatus),
                          ],
                        ),
                        if (_lastSyncedForVpn?.vpnEnabled == true &&
                            (_vpnPermissionGranted != true) &&
                            (_lastSyncedForVpn?.blockedPackages.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'יש לאשר הגנת רשת פעם אחת',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _onApproveNetworkProtection,
                            child: const Text('אשר הגנת רשת'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isConnected) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Icon(Icons.link, color: AppTheme.primaryBlue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'מחובר להורה',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              if ((_linkedNameForDisplay ?? linkedName) != null && (_linkedNameForDisplay ?? linkedName)!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    (_linkedNameForDisplay ?? linkedName)!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!isConnected) ...[
                Card(
                  elevation: 2,
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Icon(Icons.link_off, color: Colors.amber.shade800, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'לא מחובר להורה',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Colors.amber.shade900,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'יש לחבר להורה כדי להפעיל את הניהול',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.amber.shade800,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChildLinkScreen(),
                              ),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('התחברות להורה'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (child != null &&
                  (child.name.isNotEmpty ||
                      child.age > 0 ||
                      child.grade.isNotEmpty ||
                      child.schoolCode.isNotEmpty)) ...[
                _ChildInfoCard(model: child),
                const SizedBox(height: 16),
              ],
              _ParentMessageCard(message: parentMessage),
              const SizedBox(height: 16),
              _MenuCard(
                title: l10n.scheduleTomorrow,
                icon: Icons.calendar_today_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SchoolScheduleScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.blockedAppsAndTimes,
                icon: Icons.block_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlockedAppsTimesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: l10n.contentLibraryTitle,
                icon: Icons.menu_book_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const ContentLibraryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
                );
              },
            ),
    );
  }
}

class _ChildInfoCard extends StatelessWidget {
  const _ChildInfoCard({required this.model});
  final ChildModel model;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'פרטי משתמש',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'שם', value: model.name),
            _InfoRow(
              label: 'גיל',
              value: model.age > 0 ? model.age.toString() : '',
            ),
            _InfoRow(label: 'כיתה', value: model.grade),
            _InfoRow(label: 'קוד בית ספר', value: model.schoolCode),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              textDirection: naturalTextDirectionFor(value),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParentMessageCard extends StatelessWidget {
  const _ParentMessageCard({required this.message});

  final ParentMessage? message;

  @override
  Widget build(BuildContext context) {
    final hasMessage = message != null && message!.hasContent;
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              AppTheme.lightBlue.withValues(alpha: 0.42),
              Colors.white,
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.favorite_rounded,
                      color: AppTheme.primaryBlue.withValues(alpha: 0.82),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Message from Parent',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.blueGrey.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hasMessage
                    ? message!.body
                    : 'A message from your parent will appear here',
                maxLines: hasMessage ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textDirection: naturalTextDirectionFor(
                  hasMessage ? message!.body : 'A message from your parent will appear here',
                ),
                textAlign: TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: hasMessage
                      ? Colors.blueGrey.shade800
                      : Colors.blueGrey.shade500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                hasMessage
                    ? _formatUpdatedLabel(message!.updatedAt)
                    : 'No message yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.blueGrey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatUpdatedLabel(DateTime updatedAt) {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);
    if (diff.inMinutes < 1) return 'updated just now';
    if (diff.inHours < 1) return 'updated recently';
    if (diff.inHours < 24) return 'updated ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'updated yesterday';
    final month = updatedAt.month.toString().padLeft(2, '0');
    final day = updatedAt.day.toString().padLeft(2, '0');
    return 'updated on $day/$month';
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
