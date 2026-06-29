import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config/genet_config.dart';
import '../core/safe_navigation.dart';
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
import '../repositories/child_vpn_status_report.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../repositories/parent_profile_repository.dart';
import '../models/installed_app.dart';
import '../services/installed_apps_bridge.dart';
import '../services/installed_apps_periodic_fallback.dart';
import '../services/night_mode_service.dart';
import '../services/relevant_installed_apps_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import '../widgets/natural_text_field.dart';
import 'blocked_apps_times_screen.dart';
import 'child_link_screen.dart';
import 'child_sleep_hours_screen.dart';
import 'content_library_screen.dart';

/// MVP child-initiated disconnect confirmation dialog (widget-tested from [ChildHomeScreen]).
Future<bool> showChildMvpDisconnectConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ניתוק חיבור'),
        content: const Text('האם אתה בטוח שברצונך לנתק את החיבור להורה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('נתק'),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

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
/// Connection UX phases: **checking** (verifying until Firestore resolves), **connected**,
/// **disconnected** (only after confirmed invalid state or no saved link prefs).
///
/// [canonicalStartupPreflightUnverified]: role-select could not confirm the canonical doc within
/// the startup window; connection UI waits on the stream / stale reconcile (prefs are not proof).
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
  const ChildHomeScreen({
    super.key,
    this.canonicalStartupPreflightUnverified = false,
  });

  /// When true, show a short-lived “verifying” hint until the child-doc stream resolves.
  final bool canonicalStartupPreflightUnverified;

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> with WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // Fields: subscriptions, connection, timers, VPN / protection, installed apps
  // ---------------------------------------------------------------------------
  static const int _trustedTimeRefreshIntervalMs = 10 * 60 * 1000;
  static const int _timeTamperToleranceMs = 90 * 1000;

  /// Grace period before treating a null canonical snapshot as stale while local link prefs exist.
  static const Duration _staleCanonicalDocGrace = Duration(seconds: 15);

  static const EventChannel _enforcementChannel = EventChannel(
    'genet/enforcement',
  );
  StreamSubscription<SyncedChildData?>? _firebaseSyncSub;
  StreamSubscription<Map<String, dynamic>?>? _sleepLockSub;
  StreamSubscription<Map<String, dynamic>>? _installedAppsChangeSub;
  StreamSubscription<dynamic>? _packageChangeFastPathSub;
  StreamSubscription<List<InstalledApp>>? _relevantLocalListSub;
  StreamSubscription<dynamic>? _enforcementSub;

  /// Single source of truth from Firebase: true = connected, false = disconnected, null = unknown / loading
  bool? _firebaseConnectionStatus;
  String? _linkedNameForDisplay;

  /// From `genet_parents/{parentId}` after canonical connection; does not affect connection truth.
  String? _parentIdentityDisplaySuffix;

  /// True until link state is resolved from Firestore (or known unlinked with no prefs).
  /// While true, UI must not show the disconnected (amber) card for a null connection snapshot.
  bool _isVerifyingConnection = true;

  /// Copied from [ChildHomeScreen.canonicalStartupPreflightUnverified] at init.
  bool _canonicalStartupPreflightUnverified = false;

  /// Timer: keep native prefs in sync when schedule windows cross.
  Timer? _nightCheckTimer;
  Timer? _installedAppsFallbackTimer;

  /// If the canonical child doc stays missing while prefs claim a link, reconcile after [_staleCanonicalDocGrace].
  Timer? _staleCanonicalDocTimer;

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

  /// Dedupe for [reportChildVpnStatus] (Firestore parent-alert map).
  String? _lastVpnStatusReportState;
  DateTime? _lastVpnStatusReportAt;

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
    _canonicalStartupPreflightUnverified =
        widget.canonicalStartupPreflightUnverified;
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
      final syncedCount =
          await RelevantInstalledAppsEngine.instance.refreshFromFullDeviceScanAndSync(
        childId: childId,
        parentId: parentId,
        mutationSource: reason,
        syncTrigger: trigger,
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
      unawaited(_maybeReportChildVpnFirestore(protectionStatus));
    } catch (_) {
      debugPrint('GENET_VPN: VPN CHECK FAILED');
      unawaited(_maybeReportChildVpnFirestore(null));
    }
  }

  /// Writes `vpnStatus` parent-alert map when linked + connected; deduped.
  Future<void> _maybeReportChildVpnFirestore(String? protectionStatus) async {
    if (!mounted || !Platform.isAndroid) return;
    if (_firebaseConnectionStatus != true) return;
    final role = await getUserRole();
    if (!mounted || role != kUserRoleChild) return;
    final pid = normalizeIdentifier(await getLinkedParentId());
    final cid = normalizeIdentifier(await getLinkedChildId());
    if (pid == null || cid == null) return;

    final state = mapProtectionStatusToVpnReportState(protectionStatus);
    final lost = vpnReportProtectionLost(state);
    final now = DateTime.now();
    if (!shouldReportChildVpnStatus(
      nextState: state,
      lastReportedState: _lastVpnStatusReportState,
      now: now,
      lastReportedAt: _lastVpnStatusReportAt,
    )) {
      return;
    }
    final ok = await reportChildVpnStatus(
      parentId: pid,
      childId: cid,
      state: state,
      protectionLost: lost,
      previousReportedState: _lastVpnStatusReportState,
      previousReportedProtectionLost: _lastVpnStatusReportState != null
          ? vpnReportProtectionLost(_lastVpnStatusReportState!)
          : null,
    );
    if (!mounted || !ok) return;
    _lastVpnStatusReportState = state;
    _lastVpnStatusReportAt = now;
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
    if (!mounted) return;
    // One extra pass via [scheduleBlockingStateSync]; avoids waiting only on the 10s timer
    // after remote sleep config changes (bounded, no loops or new timers).
    _syncBlockingState();
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

  void _scheduleParentIdentityRefresh(String rawParentId) {
    unawaited(_loadParentIdentityForDisplay(rawParentId));
  }

  Future<void> _loadParentIdentityForDisplay(String rawParentId) async {
    final pid = normalizeIdentifier(rawParentId);
    if (pid == null) return;
    try {
      final profile = await getParentProfile(pid);
      if (!mounted) return;
      if (_firebaseConnectionStatus != true) return;
      final line = parentProfileDisplayLineForChildUi(profile);
      setState(() => _parentIdentityDisplaySuffix = line);
    } catch (_) {
      if (!mounted) return;
      if (_firebaseConnectionStatus != true) return;
      setState(() => _parentIdentityDisplaySuffix = null);
    }
  }

  void _resetDisconnectedProtectionState() {
    _childProtectionFlow.resetAfterDisconnect();
    setState(() {
      _firebaseConnectionStatus = false;
      _isVerifyingConnection = false;
      _linkedNameForDisplay = null;
      _parentIdentityDisplaySuffix = null;
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
      _lastVpnStatusReportState = null;
      _lastVpnStatusReportAt = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Firebase: watch synced child document (connection + policy updates)
  // ---------------------------------------------------------------------------
  Future<void> _onSyncedChildDataEvent(
    SyncedChildData? data,
    String expectedParentId,
    String expectedChildId,
  ) async {
    if (!mounted) return;
    final role = await getUserRole();
    final status = data?.connectionStatus;
    final docParentId = data?.parentId;
    _logCriticalEvent('GenetDebug', {
      'ROLE': role,
      'PARENT ID': docParentId,
      'CHILD ID': expectedChildId,
      'CONNECTION STATUS': status ?? 'null',
    });
    // Null snapshot: usually transient (first load / race). After a bounded grace period with prefs
    // still claiming a link, reconcile against a server read — persistent missing doc clears local link.
    if (data == null) {
      developer.log(
        'Child connection status: canonical snapshot null (transient or missing); scheduling stale check',
        name: 'Sync',
      );
      _staleCanonicalDocTimer ??= Timer(_staleCanonicalDocGrace, () {
        _staleCanonicalDocTimer = null;
        unawaited(
          _reconcileStaleCanonicalLink(
            expectedParentId: expectedParentId,
            expectedChildId: expectedChildId,
          ),
        );
      });
      return;
    }
    _staleCanonicalDocTimer?.cancel();
    _staleCanonicalDocTimer = null;
    _canonicalStartupPreflightUnverified = false;

    final expectedParentNorm = normalizeIdentifier(expectedParentId);
    final docParentNorm = normalizeIdentifier(data.parentId);
    final parentMatches =
        expectedParentNorm != null && docParentNorm == expectedParentNorm;
    final isConnected =
        isConnectionStatusConnected(data.connectionStatus) && parentMatches;
    if (isConnected) {
      developer.log('Child connected (from Firebase)', name: 'Sync');
      final wasConnected = _firebaseConnectionStatus == true;
      if (!wasConnected) {
        _parentIdentityDisplaySuffix = null;
        _scheduleParentIdentityRefresh(expectedParentId);
      }
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
        // Policy cache for [handleSleepLockState] when called without `data` (e.g. timer path).
        // Must be set before native snapshot read: snap==null used to return without ever assigning.
        _lastSyncedForVpn = data;
        final vpnDot = await handleSleepLockState(data: data);
        final snap = await _readNativeVpnSnapshotForSyncedPolicy(data);
        if (snap == null || !mounted) {
          if (mounted) {
            setState(() {
              _isVerifyingConnection = false;
              _firebaseConnectionStatus = true;
              _linkedNameForDisplay = name;
            });
          }
          return;
        }
        final uiFp = _childHomeUiFingerprint(
          data: data,
          name: name,
          perm: snap.permissionGranted,
          run: snap.running,
          dot: vpnDot,
        );
        if (uiFp == _lastChildHomeUiFingerprint) {
          debugPrint('[GenetVpn] skipped duplicate setState');
          if (mounted && _isVerifyingConnection) {
            setState(() {
              _isVerifyingConnection = false;
              _firebaseConnectionStatus = true;
              _linkedNameForDisplay = name;
            });
          }
          return;
        }
        _lastChildHomeUiFingerprint = uiFp;
        if (_vpnIndicatorStatus != vpnDot) {
          debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
        }
        setState(() {
          _isVerifyingConnection = false;
          _firebaseConnectionStatus = true;
          _linkedNameForDisplay = name;
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
          _isVerifyingConnection = false;
          _firebaseConnectionStatus = true;
          _linkedNameForDisplay = name;
        });
      }
    } else {
      developer.log(
        'Child disconnected (from Firebase) status=$status parentId=$docParentId expectedParent=$expectedParentId',
        name: 'Sync',
      );
      await _handleDisconnected();
    }
  }

  /// After [ChildHomeScreen._staleCanonicalDocGrace], re-check canonical doc vs local prefs and clear stale links.
  Future<void> _reconcileStaleCanonicalLink({
    required String expectedParentId,
    required String expectedChildId,
  }) async {
    if (!mounted) return;
    final role = await getUserRole();
    if (role != kUserRoleChild) return;
    final prefsParent = normalizeIdentifier(await getLinkedParentId());
    final prefsChild = normalizeIdentifier(await getLinkedChildId());
    if (prefsParent == null || prefsChild == null) {
      if (mounted) setState(() => _isVerifyingConnection = false);
      return;
    }
    if (prefsParent != normalizeIdentifier(expectedParentId) ||
        prefsChild != normalizeIdentifier(expectedChildId)) {
      developer.log('Stale canonical reconcile skipped: local prefs changed', name: 'Sync');
      if (mounted) setState(() => _isVerifyingConnection = false);
      return;
    }
    try {
      final outcome = await fetchCanonicalChildDocState(
        parentId: expectedParentId,
        childId: expectedChildId,
        timeout: const Duration(seconds: 12),
      );
      switch (outcome) {
        case CanonicalChildDocFetchOutcome.networkFailure:
          developer.log(
            'Stale canonical reconcile: fetch inconclusive (network); skipping disconnect',
            name: 'Sync',
          );
          if (mounted) setState(() => _isVerifyingConnection = false);
          return;
        case CanonicalChildDocFetchOutcome.missing:
        case CanonicalChildDocFetchOutcome.presentInactive:
          developer.log(
            'Stale canonical reconcile: doc missing or not connected for prefs; clearing local link',
            name: 'Sync',
          );
          await _handleDisconnected();
          return;
        case CanonicalChildDocFetchOutcome.presentActive:
          if (mounted) setState(() => _isVerifyingConnection = false);
      }
    } catch (e, st) {
      developer.log('Stale canonical reconcile unexpected: $e $st', name: 'Sync');
      if (mounted) setState(() => _isVerifyingConnection = false);
    }
  }

  Future<void> _startFirebaseConnectionListener() async {
    final parentId = normalizeIdentifier(await getLinkedParentId());
    final childId = normalizeIdentifier(await getLinkedChildId());
    if (parentId == null || childId == null) {
      developer.log('Child connection status: no parentId or childId, showing disconnected', name: 'Sync');
      if (mounted) {
        setState(() {
          _firebaseConnectionStatus = false;
          _isVerifyingConnection = false;
        });
      }
      return;
    }
    _staleCanonicalDocTimer?.cancel();
    _staleCanonicalDocTimer = null;
    _logCriticalEvent('GenetDebug', {
      'ROLE': await getUserRole(),
      'PARENT ID': parentId,
      'CHILD ID': childId,
      'READ PATH': 'genet_parents/$parentId/children/$childId',
    });
    developer.log('CHILD_READ_PATH = genet_parents/$parentId/children/$childId', name: 'Sync');
    developer.log('CHILD_READ_CHILD_ID = $childId', name: 'Sync');
    if (mounted) {
      setState(() {
        _firebaseConnectionStatus = null;
        _isVerifyingConnection = true;
      });
    }
    _firebaseSyncSub = watchSyncedChildDataStream(parentId, childId).listen(
      (data) => unawaited(_onSyncedChildDataEvent(data, parentId, childId)),
    );
  }

  void _tearDownExtensionAndFirebaseListenersOnDisconnect() {
    _staleCanonicalDocTimer?.cancel();
    _staleCanonicalDocTimer = null;
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
  Future<void> _handleDisconnected({bool navigateToChildLinkScreen = false}) async {
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
    await clearChildLinkPrefsOnly();
    if (!mounted) return;
    _resetDisconnectedProtectionState();
    unawaited(_clearVpnProtectionLostInNative());
    unawaited(GenetConfig.setNightModeActive(false));
    if (!mounted) return;
    if (navigateToChildLinkScreen) {
      await GenetConfig.syncToNative();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ChildLinkScreen()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('הקישור להורה הוסר. ניתן להתחבר מחדש.'),
      ),
    );
  }

  Future<void> _onMvpChildDisconnectPressed() async {
    final confirmed = await showChildMvpDisconnectConfirmation(context);
    if (!confirmed || !mounted) return;

    final p = normalizeIdentifier(await getLinkedParentId());
    final c = normalizeIdentifier(await getLinkedChildId());
    if (p != null && c != null) {
      try {
        await setChildConnectionStatusFirebase(p, c, 'disconnected');
      } catch (e, st) {
        developer.log(
          'Child MVP disconnect: canonical status write failed (ignored): $e $st',
          name: 'Sync',
        );
      }
    }

    if (!mounted) return;
    await _handleDisconnected(navigateToChildLinkScreen: true);
  }

  void _disposeChildHomeTimers() {
    _nightCheckTimer?.cancel();
    _installedAppsFallbackTimer?.cancel();
    _extensionVpnTimer?.cancel();
    _installedAppsSyncDebounceTimer?.cancel();
    _vpnStatusMonitorTimer?.cancel();
    _staleCanonicalDocTimer?.cancel();
    _staleCanonicalDocTimer = null;
  }

  void _disposeChildHomeStreamSubscriptions() {
    _installedAppsChangeSub?.cancel();
    _packageChangeFastPathSub?.cancel();
    _relevantLocalListSub?.cancel();
    RelevantInstalledAppsEngine.instance.reset(mutationSource: 'child_home_dispose');
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

  String _headerGreetingName() {
    final raw = _linkedNameForDisplay?.trim();
    if (raw == null || raw.isEmpty) return 'שלום';
    final first = raw.split(RegExp(r'\s+')).first.trim();
    return first.isEmpty ? 'שלום' : first;
  }

  Widget _buildStar({
    required double size,
    required double opacity,
    bool useBlueTint = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: useBlueTint
            ? Colors.blueAccent.withValues(alpha: opacity)
            : Colors.white.withValues(alpha: opacity),
      ),
    );
  }

  Widget _buildGenetShield() {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF071A3A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1D8CFF).withValues(alpha: 0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D8CFF).withValues(alpha: 0.28),
            blurRadius: 16,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF36F36B).withValues(alpha: 0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(
        Icons.shield_rounded,
        color: Colors.white.withValues(alpha: 0.92),
        size: 24,
      ),
    );
  }

  Widget _buildHeader() {
    final greetingName = _headerGreetingName();

    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'היי, $greetingName 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'שמח לראות אותך',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        _buildGenetShield(),
      ],
    );
  }

  Widget _buildNightSkyLayer({required double width, required double height}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF031A3F),
                Color(0xFF020B1F),
                Color(0xFF010715),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        ..._ChildHomeStarField.stars.map(
          (star) => Positioned(
            left: star.x * width,
            top: star.y * height,
            child: _buildStar(
              size: star.size,
              opacity: star.opacity,
              useBlueTint: star.useBlueTint,
            ),
          ),
        ),
      ],
    );
  }

  String _resolveBedtimeDisplay(NightModeService night) {
    if (!night.isLoaded) return '21:30';
    final raw = night.config.startTime.trim();
    if (raw.isEmpty) return '21:30';
    final parts = raw.split(':');
    if (parts.length < 2) return '21:30';
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return '21:30';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Widget _buildNightStatusCard(NightModeService night) {
    final bedtime = _resolveBedtimeDisplay(night);

    return Container(
      width: double.infinity,
      height: 200,
      decoration: _ChildHomeUiTokens.surfaceDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF0B2556),
            Color(0xFF071A3A),
          ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 18,
            left: 22,
            child: _buildStar(size: 2.5, opacity: 0.45),
          ),
          Positioned(
            top: 28,
            left: 34,
            child: _buildStar(size: 2.0, opacity: 0.32, useBlueTint: true),
          ),
          Positioned(
            top: 16,
            left: 46,
            child: _buildStar(size: 3.0, opacity: 0.38),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      Icons.nightlight_round,
                      color: Colors.white.withValues(alpha: 0.92),
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'מצב הלילה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  bedtime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'שעת השינה שלך להיום',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                const Text(
                  'עוד מעט מתחילים להירגע',
                  style: TextStyle(
                    color: Color(0xFF36F36B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentMessageCard() {
    final message = _parentMessage;
    final hasMessage = message != null && message.hasContent;
    final bodyText = hasMessage
        ? message.body
        : 'כאן תופיע הודעה אישית מההורה';

    return Container(
      width: double.infinity,
      height: 135,
      decoration: _ChildHomeUiTokens.surfaceDecoration(),
      child: Stack(
        children: [
          Positioned(
            top: 14,
            left: 16,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFF36F36B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'הודעה מההורה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    bodyText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textDirection: naturalTextDirectionFor(bodyText),
                    style: TextStyle(
                      color: hasMessage
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                      fontSize: hasMessage ? 17 : 15,
                      fontWeight:
                          hasMessage ? FontWeight.w600 : FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openContentLibrary() {
    debugPrint('[GENET][CHILD_HOME] Genet Library tapped');
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ContentLibraryScreen(),
      ),
    );
  }

  void _openBlockedAppsTimes() {
    debugPrint('[GENET][CHILD_HOME] Apps tapped');
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const BlockedAppsTimesScreen(),
      ),
    );
  }

  void _openSchoolSchedule() {
    debugPrint('[GENET][CHILD_HOME] Mission tapped');
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const ChildSleepHoursScreen(),
      ),
    );
  }

  Future<void> _showProgressComingSoonDialog() async {
    debugPrint('[GENET][CHILD_HOME] Progress tapped');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('בקרוב'),
          content: const Text(
            'אזור ההתקדמות נמצא בפיתוח ויגיע בעדכון הבא.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: _ChildHomeUiTokens.surfaceDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 36,
                color: const Color(0xFF36F36B),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.92,
      children: [
        _buildQuickActionTile(
          title: '📚 ספריית Genet',
          icon: Icons.menu_book_rounded,
          onTap: _openContentLibrary,
        ),
        _buildQuickActionTile(
          title: '📱 האפליקציות שלי',
          icon: Icons.apps_rounded,
          onTap: _openBlockedAppsTimes,
        ),
        _buildQuickActionTile(
          title: '⭐ המשימה שלי',
          icon: Icons.star_rounded,
          onTap: _openSchoolSchedule,
        ),
        _buildQuickActionTile(
          title: '⭐ ההתקדמות שלי',
          icon: Icons.auto_graph_rounded,
          onTap: () => unawaited(_showProgressComingSoonDialog()),
        ),
      ],
    );
  }

  Widget _buildWeeklyProgressCard() {
    const onTimeDays = 5;
    const totalDays = 7;
    const progressValue = onTimeDays / totalDays;
    const percentLabel = '70%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _ChildHomeUiTokens.surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(
                Icons.auto_graph_rounded,
                color: _ChildHomeUiTokens.accentGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                '⭐ ההתקדמות שלך',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'השבוע הלכת לישון בזמן',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$onTimeDays מתוך $totalDays ימים',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                _ChildHomeUiTokens.accentGreen,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              percentLabel,
              style: const TextStyle(
                color: _ChildHomeUiTokens.accentGreen,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI: scaffold, connection cards, navigation
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final nightMode = context.watch<NightModeService>();
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF020B1F),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildNightSkyLayer(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildNightStatusCard(nightMode),
                        const SizedBox(height: 20),
                        _buildParentMessageCard(),
                        const SizedBox(height: 24),
                        _buildQuickActionsGrid(),
                        const SizedBox(height: 24),
                        _buildWeeklyProgressCard(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChildHomeUiTokens {
  static const Color cardFill = Color(0xFF071A3A);
  static const Color borderBlue = Color(0xFF1D8CFF);
  static const Color accentGreen = Color(0xFF36F36B);

  static BoxDecoration surfaceDecoration({
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(24)),
    Gradient? gradient,
  }) {
    return BoxDecoration(
      color: gradient == null ? cardFill : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: Border.all(
        color: borderBlue.withValues(alpha: 0.15),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: borderBlue.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}

class _ChildHomeStarSpec {
  const _ChildHomeStarSpec(
    this.x,
    this.y,
    this.size,
    this.opacity, {
    this.useBlueTint = false,
  });

  final double x;
  final double y;
  final double size;
  final double opacity;
  final bool useBlueTint;
}

class _ChildHomeStarField {
  static const List<_ChildHomeStarSpec> stars = [
    _ChildHomeStarSpec(0.06, 0.05, 3.0, 0.58),
    _ChildHomeStarSpec(0.14, 0.11, 2.0, 0.34),
    _ChildHomeStarSpec(0.22, 0.04, 2.5, 0.44, useBlueTint: true),
    _ChildHomeStarSpec(0.31, 0.09, 2.0, 0.3),
    _ChildHomeStarSpec(0.39, 0.06, 4.0, 0.48),
    _ChildHomeStarSpec(0.48, 0.13, 2.0, 0.38, useBlueTint: true),
    _ChildHomeStarSpec(0.57, 0.05, 2.5, 0.46),
    _ChildHomeStarSpec(0.66, 0.10, 2.0, 0.32),
    _ChildHomeStarSpec(0.74, 0.07, 3.5, 0.52),
    _ChildHomeStarSpec(0.83, 0.12, 2.0, 0.36, useBlueTint: true),
    _ChildHomeStarSpec(0.91, 0.06, 2.5, 0.42),
    _ChildHomeStarSpec(0.18, 0.18, 2.0, 0.26),
    _ChildHomeStarSpec(0.44, 0.17, 3.0, 0.4),
    _ChildHomeStarSpec(0.62, 0.19, 2.0, 0.3, useBlueTint: true),
    _ChildHomeStarSpec(0.78, 0.16, 3.5, 0.46),
    _ChildHomeStarSpec(0.10, 0.24, 1.5, 0.22),
    _ChildHomeStarSpec(0.53, 0.22, 2.5, 0.28),
    _ChildHomeStarSpec(0.88, 0.21, 2.0, 0.34),
    _ChildHomeStarSpec(0.27, 0.27, 4.0, 0.36),
    _ChildHomeStarSpec(0.71, 0.28, 3.0, 0.32, useBlueTint: true),
    _ChildHomeStarSpec(0.35, 0.31, 1.5, 0.2),
    _ChildHomeStarSpec(0.95, 0.18, 2.0, 0.24),
    _ChildHomeStarSpec(0.04, 0.14, 3.5, 0.4),
    _ChildHomeStarSpec(0.58, 0.32, 2.0, 0.18),
  ];
}
