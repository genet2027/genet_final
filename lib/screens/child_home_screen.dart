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
import '../l10n/app_localizations.dart';
import '../models/child_model.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../services/night_mode_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_switcher.dart';
import 'blocked_apps_times_screen.dart';
import 'child_link_screen.dart';
import 'content_library_screen.dart';
import 'night_screen.dart';
import 'role_select_screen.dart';
import 'school_schedule_screen.dart';

enum ChildProtectionState { free, sleepLock, vpnRequired, appBlocked }

/// Child home: connection status from Firebase only. When parent disconnects, UI updates in place.
class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> with WidgetsBindingObserver {
  static const EventChannel _enforcementChannel = EventChannel(
    'genet/enforcement',
  );
  StreamSubscription<SyncedChildData?>? _firebaseSyncSub;
  StreamSubscription<Map<String, dynamic>?>? _sleepLockSub;
  StreamSubscription<Map<String, dynamic>>? _installedAppsChangeSub;
  StreamSubscription<dynamic>? _enforcementSub;

  /// Single source of truth from Firebase: true = connected, false = disconnected, null = loading
  bool? _firebaseConnectionStatus;
  String? _linkedNameForDisplay;

  /// Timer: keep native prefs in sync when schedule windows cross.
  Timer? _nightCheckTimer;

  /// Re-apply VPN when extension windows start/end without waiting for the next Firestore write.
  Timer? _extensionVpnTimer;
  /// Periodic native VPN transport status monitor.
  Timer? _vpnStatusMonitorTimer;
  bool _extensionActiveLastTick = false;
  Timer? _installedAppsSyncDebounceTimer;
  bool _installedAppsSyncInFlight = false;
  bool _installedAppsSyncQueued = false;

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

  /// Skip [setState] when visible VPN/UI fields unchanged.
  String? _lastChildHomeUiFingerprint;
  String? _lastBlockingStateFingerprint;
  ChildProtectionState? _lastAppliedChildProtectionState;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_clearVpnProtectionLostInNative());
    _startFirebaseConnectionListener();
    _startSleepLockRemoteListener();
    // Keep native sleep-lock/VPN state fresh for child mode without a second in-app block route.
    getUserRole().then((role) {
      if (!mounted || role != kUserRoleChild) return;
      _startEnforcementListener();
      _scheduleInstalledAppsSync(reason: 'startup', delay: Duration.zero);
      _nightCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) => _syncBlockingState());
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncBlockingState());
      if (Platform.isAndroid) {
        _startInstalledAppsChangeListener();
        _extensionVpnTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _tickExtensionVpnWindows(),
        );
        _startVpnStatusMonitor();
      }
    });
  }

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
      debugPrint('[GenetProtect] enforcement event type=$type pkg=$packageName');
      setState(() => _currentForegroundApp = packageName);
    });
  }

  void _startVpnStatusMonitor() {
    _vpnStatusMonitorTimer?.cancel();
    _vpnStatusMonitorTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollVpnStatus(),
    );
    _pollVpnStatus();
  }

  bool _policyRequiresVpn([SyncedChildData? data]) {
    return _requireVpn;
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
    final sleepEnabled = night.config.enabled;
    final sleepStartTime = night.config.startTime;
    final sleepEndTime = night.config.endTime;
    final now = DateTime.now();
    final insideSleepWindow =
        sleepEnabled && _sleepLockTimeInRange(sleepStartTime, sleepEndTime);
    final sleepLockActive = insideSleepWindow;
    final effectiveVpnEnabled = sleepLockActive;
    final currentProtectionStatus = await GenetVpn.getVpnProtectionStatus();
    final currentVpnActive =
        currentProtectionStatus == GenetVpn.protectionProtected;
    final actionParts = <String>[];
    if (effectiveVpnEnabled && !currentVpnActive) {
      actionParts.add('start vpn');
    } else if (!effectiveVpnEnabled && currentVpnActive) {
      actionParts.add('stop vpn');
    }
    if (_sleepLockActive != sleepLockActive) {
      actionParts.add(
        sleepLockActive ? 'enable restriction' : 'disable restriction',
      );
    }
    final actionTaken = actionParts.isEmpty ? 'no change' : actionParts.join(' + ');
    debugPrint('[GenetVpn] sleep lock enabled=$sleepEnabled');
    debugPrint('[GenetVpn] sleep start time=$sleepStartTime');
    debugPrint('[GenetVpn] sleep end time=$sleepEndTime');
    debugPrint('[GenetVpn] current time=${_formatCurrentTime(now)}');
    debugPrint('[GenetVpn] insideSleepWindow=$insideSleepWindow');
    debugPrint('[GenetVpn] sleepLockActive final value=$sleepLockActive');
    debugPrint('[GenetVpn] current VPN state=$currentProtectionStatus');
    debugPrint('[GenetVpn] restriction mode active=$sleepLockActive');
    debugPrint('[GenetVpn] action taken: $actionTaken');
    if (_sleepLockActive != sleepLockActive && mounted) {
      setState(() => _sleepLockActive = sleepLockActive);
    } else {
      _sleepLockActive = sleepLockActive;
    }
    await GenetConfig.setNightModeActive(sleepLockActive);
    return VpnRemoteChildPolicy.apply(
      synced,
      overrideVpnEnabled: effectiveVpnEnabled,
    );
  }

  void _startInstalledAppsChangeListener() {
    _installedAppsChangeSub?.cancel();
    _installedAppsChangeSub = GenetConfig.watchInstalledAppsChanges().listen((event) {
      final action = event['action'] as String? ?? '';
      final packageName = event['package'] as String? ?? '';
      debugPrint('[GenetApps] package change action=$action package=$packageName');
      _scheduleInstalledAppsSync(reason: '$action:$packageName');
    });
  }

  void _scheduleInstalledAppsSync({
    required String reason,
    Duration delay = const Duration(milliseconds: 700),
  }) {
    if (!mounted || !Platform.isAndroid) return;
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
    if (!mounted || role != kUserRoleChild) return;
    final childId = await getLinkedChildId();
    if (!mounted || childId == null || childId.isEmpty) return;
    if (_installedAppsSyncInFlight) {
      _installedAppsSyncQueued = true;
      return;
    }
    _installedAppsSyncInFlight = true;
    try {
      debugPrint('[GenetApps] sync requested: $reason');
      await syncInstalledUserAppsOnce(childId);
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

  ChildProtectionState evaluateChildProtectionState({
    required bool sleepLockActive,
    required bool isVpnActive,
    required List<String> blockedApps,
    required String? currentForegroundApp,
    required DateTime currentTime,
  }) {
    final sortedBlockedApps = List<String>.from(blockedApps)..sort();
    final fingerprint =
        '${_vpnProtectionStatus ?? 'unknown'}|$sleepLockActive|$isVpnActive|${sortedBlockedApps.join(",")}|${currentForegroundApp ?? ''}|${currentTime.hour}:${currentTime.minute}';
    final state = switch ((sleepLockActive, isVpnActive, currentForegroundApp)) {
      (true, _, _) => ChildProtectionState.sleepLock,
      (false, false, _) => ChildProtectionState.vpnRequired,
      (false, true, final String app)
          when app.isNotEmpty && sortedBlockedApps.contains(app) =>
        ChildProtectionState.appBlocked,
      _ => ChildProtectionState.free,
    };
    if (_lastBlockingStateFingerprint == fingerprint) return state;
    _lastBlockingStateFingerprint = fingerprint;
    debugPrint('[GenetProtect] sleepLockActive=$sleepLockActive');
    debugPrint('[GenetProtect] isVpnActive=$isVpnActive');
    debugPrint('[GenetProtect] blockedApps=${sortedBlockedApps.join(",")}');
    debugPrint('[GenetProtect] currentForegroundApp=${currentForegroundApp ?? ''}');
    debugPrint('[GenetProtect] currentTime=${_formatCurrentTime(currentTime)}');
    debugPrint('[GenetProtect] finalState=$state');
    return state;
  }

  void _openBlockedContentLibrary() {
    debugPrint('[GenetBlock] content access opened');
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const ContentLibraryScreen(),
      ),
    );
  }

  Widget _showNetworkProtectionScreen({
    required NetworkProtectionBlockReason reason,
  }) {
    return showNetworkProtectionScreen(
      reason: reason,
      onActivateProtection:
          reason == NetworkProtectionBlockReason.vpn
              ? _onApproveNetworkProtection
              : null,
      onOpenContentLibrary: _openBlockedContentLibrary,
    );
  }

  Widget? applyProtectionState(ChildProtectionState state) {
    final changed = _lastAppliedChildProtectionState != state;
    _lastAppliedChildProtectionState = state;
    switch (state) {
      case ChildProtectionState.sleepLock:
        if (changed) {
          debugPrint(
            '[GenetProtect] action taken=ensure vpn on + enable restriction + no vpn screen',
          );
          unawaited(handleSleepLockState());
        }
        return null;
      case ChildProtectionState.vpnRequired:
        if (changed) {
          debugPrint(
            '[GenetProtect] action taken=show network protection required',
          );
        }
        return _showNetworkProtectionScreen(
          reason: NetworkProtectionBlockReason.vpn,
        );
      case ChildProtectionState.appBlocked:
        if (changed) {
          debugPrint('[GenetProtect] action taken=show app blocking behavior');
        }
        return null;
      case ChildProtectionState.free:
        if (changed) {
          debugPrint('[GenetProtect] action taken=remove all blocking');
        }
        return null;
    }
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
    debugPrint('[GenetVpn] requireVpn from Firebase=$requireVpn');
    debugPrint('[GenetVpn] current vpn state=$protectionStatus');
    debugPrint('[GenetVpn] enforcement UI shown=$protectionLost');
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
      final now = DateTime.now().millisecondsSinceEpoch;
      final anyActive =
          d.extensionApproved.entries.any((e) => (e.value) > now);
      if (!anyActive && !_extensionActiveLastTick) return;
      _extensionActiveLastTick = anyActive;
      final vpnDot = await handleSleepLockState(data: d);
      if (!mounted) return;
      final protectionStatus = await GenetVpn.getVpnProtectionStatus();
      final g = _permissionGrantedFromProtectionStatus(protectionStatus);
      final run = _runningFromProtectionStatus(protectionStatus);
      final requireVpn = _policyRequiresVpn(d);
      final lost = _handleVpnRequirement(
        requireVpn: requireVpn,
        isVpnActive: protectionStatus == GenetVpn.protectionProtected,
      );
      if (!mounted) return;
      _applyVpnProtectionSnapshot(
        protectionStatus: protectionStatus,
        permissionGranted: g,
        running: run,
        protectionLost: lost,
        requireVpn: requireVpn,
        vpnIndicatorStatus: vpnDot,
      );
    });
  }

  void _syncBlockingState() {
    if (!mounted) return;
    // Child home is only for child flow; guard so no Timer/Navigator runs without child role.
    getUserRole().then((role) async {
      if (!mounted || role != kUserRoleChild) return;
      await handleSleepLockState();
      _syncNightNativeOnly();
    });
  }

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
    if (!mounted || data == null) return;
    final requireVpn = data['requireVpn'] == true;
    if (_requireVpn != requireVpn) {
      debugPrint('[GenetVpn] requireVpn updated source: Firebase value=$requireVpn');
      setState(() => _requireVpn = requireVpn);
      unawaited(_pollVpnStatus());
    }
    final sleepLockRaw = data['sleepLock'];
    if (sleepLockRaw is Map<String, dynamic>) {
      await _applySleepLockSnapshot(sleepLockRaw);
    } else if (sleepLockRaw is Map) {
      await _applySleepLockSnapshot(Map<String, dynamic>.from(sleepLockRaw));
    }
  }

  /// Same time-window logic as [NightModeService.isNightTimeNow] but without requiring `enabled`.
  bool _sleepLockTimeInRange(String startTime, String endTime) {
    final now = DateTime.now();
    final start = _parseTimeParts(startTime);
    final end = _parseTimeParts(endTime);
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = start.$1 * 60 + start.$2;
    final endMinutes = end.$1 * 60 + end.$2;
    if (startMinutes > endMinutes) {
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  (int, int) _parseTimeParts(String s) {
    final parts = s.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h, m);
  }

  /// Applies remote sleep lock to prefs/native (enforcement is Android-only, no in-app overlay).
  Future<void> _applySleepLockSnapshot(Map<String, dynamic>? data) async {
    if (!mounted || data == null) return;
    // ignore: avoid_print
    print('SLEEP LOCK RECEIVED: $data');
    final now = DateTime.now();
    // ignore: avoid_print
    print(
      'CURRENT TIME: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
    );
    final isActive = data['isActive'] as bool? ?? false;
    final startTime = data['startTime'] as String? ?? '22:00';
    final endTime = data['endTime'] as String? ?? '07:00';
    final isInRange = isActive && _sleepLockTimeInRange(startTime, endTime);
    // ignore: avoid_print
    print('IS IN RANGE: $isInRange');
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
    if (isActive && isInRange) {
      // ignore: avoid_print
      print('LOCK ACTIVATED');
    } else {
      // ignore: avoid_print
      print('LOCK DISABLED');
    }
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

  Future<void> _startFirebaseConnectionListener() async {
    final parentId = await getLinkedParentId();
    final childId = await getLinkedChildId();
    if (parentId == null || parentId.isEmpty || childId == null || childId.isEmpty) {
      developer.log('Child connection status: no parentId or childId, showing disconnected', name: 'Sync');
      if (mounted) setState(() => _firebaseConnectionStatus = false);
      return;
    }
    developer.log('CHILD_READ_PATH = genet_parents/$parentId/children/$childId', name: 'Sync');
    developer.log('CHILD_READ_CHILD_ID = $childId', name: 'Sync');
    if (mounted) setState(() => _firebaseConnectionStatus = null);
    _firebaseSyncSub = watchSyncedChildDataStream(parentId, childId).listen((data) async {
      if (!mounted) return;
      final role = await getUserRole();
      print('ROLE: $role');
      final status = data?.connectionStatus;
      final docParentId = data?.parentId;
      developer.log('CHILD_LISTENER: child doc updated', name: 'Sync');
      developer.log('CHILD_LISTENER: parentId = $docParentId', name: 'Sync');
      developer.log('CHILD_LISTENER: connectionStatus = $status', name: 'Sync');
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
              debugPrint('[GenetVpn] blockedApps changed -> refreshVpn if VPN running');
            }
          }
          final vpnDot = await handleSleepLockState(data: data);
          final protectionStatus = await GenetVpn.getVpnProtectionStatus();
          final g = _permissionGrantedFromProtectionStatus(protectionStatus);
          final run = _runningFromProtectionStatus(protectionStatus);
          final requireVpn = _policyRequiresVpn(data);
          final lost = _handleVpnRequirement(
            requireVpn: requireVpn,
            isVpnActive: protectionStatus == GenetVpn.protectionProtected,
          );
          if (!mounted) return;
          final uiFp = _childHomeUiFingerprint(
            data: data,
            name: name,
            perm: g,
            run: run,
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
            protectionStatus: protectionStatus,
            permissionGranted: g,
            running: run,
            protectionLost: lost,
            requireVpn: requireVpn,
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
    });
  }

  Future<void> _handleDisconnected() async {
    if (Platform.isAndroid) {
      await GenetVpn.stopVpn();
      debugPrint('[GenetVpn] child stopVpn triggered (disconnected from parent)');
    }
    VpnRemoteChildPolicy.resetPushDedupe();
    _extensionVpnTimer?.cancel();
    _extensionVpnTimer = null;
    _extensionActiveLastTick = false;
    _lastChildHomeUiFingerprint = null;
    _sleepLockSub?.cancel();
    _sleepLockSub = null;
    _firebaseSyncSub?.cancel();
    _firebaseSyncSub = null;
    await setLinkedChild(null, null);
    await setLinkedParentId(null);
    if (!mounted) return;
    setState(() {
      _firebaseConnectionStatus = false;
      _linkedNameForDisplay = null;
      _lastSyncedForVpn = null;
      _installedAppsSyncQueued = false;
      _requireVpn = false;
      _sleepLockActive = false;
      _currentForegroundApp = null;
      _vpnProtectionStatus = null;
      _vpnPermissionGranted = null;
      _vpnRunningOnDevice = null;
      _vpnProtectionLostTrigger = false;
      _vpnIndicatorStatus = 'off';
      _lastAppliedChildProtectionState = null;
    });
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nightCheckTimer?.cancel();
    _extensionVpnTimer?.cancel();
    _installedAppsSyncDebounceTimer?.cancel();
    _vpnStatusMonitorTimer?.cancel();
    _installedAppsChangeSub?.cancel();
    _enforcementSub?.cancel();
    _sleepLockSub?.cancel();
    _firebaseSyncSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _currentForegroundApp = null;
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
    final protectionStatus = await GenetVpn.getVpnProtectionStatus();
    final g = _permissionGrantedFromProtectionStatus(protectionStatus);
    final run = _runningFromProtectionStatus(protectionStatus);
    final requireVpn = _policyRequiresVpn(d);
    final lost = _handleVpnRequirement(
      requireVpn: requireVpn,
      isVpnActive: protectionStatus == GenetVpn.protectionProtected,
    );
    final name = await getLinkedChildName();
    if (!mounted) return;
    final uiFp = _childHomeUiFingerprint(data: d, name: name, perm: g, run: run, dot: vpnDot);
    _lastChildHomeUiFingerprint = uiFp;
    if (_vpnIndicatorStatus != vpnDot) {
      debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
    }
    if (mounted) {
      _applyVpnProtectionSnapshot(
        protectionStatus: protectionStatus,
        permissionGranted: g,
        running: run,
        protectionLost: lost,
        requireVpn: requireVpn,
        vpnIndicatorStatus: vpnDot,
      );
    }
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
    await GenetVpn.setBlockedApps(VpnRemoteChildPolicy.effectiveBlockedPackages(d));
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
    final protectionStatus = await GenetVpn.getVpnProtectionStatus();
    final g = _permissionGrantedFromProtectionStatus(protectionStatus);
    final run = _runningFromProtectionStatus(protectionStatus);
    final requireVpn = _policyRequiresVpn(d);
    final lost = _handleVpnRequirement(
      requireVpn: requireVpn,
      isVpnActive: protectionStatus == GenetVpn.protectionProtected,
    );
    if (!mounted) return;
    final name = await getLinkedChildName();
    if (!mounted) return;
    final uiFp = _childHomeUiFingerprint(data: d, name: name, perm: g, run: run, dot: vpnDot);
    _lastChildHomeUiFingerprint = uiFp;
    if (_vpnIndicatorStatus != vpnDot) {
      debugPrint('[GenetVpn] vpnStatus changed from $_vpnIndicatorStatus to $vpnDot');
    }
    if (mounted) {
      _applyVpnProtectionSnapshot(
        protectionStatus: protectionStatus,
        permissionGranted: g,
        running: run,
        protectionLost: lost,
        requireVpn: requireVpn,
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

  @override
  Widget build(BuildContext context) {
    debugPrint('[GenetVpn] child screen rebuild');
    final l10n = AppLocalizations.of(context)!;
    context.watch<NightModeService>();
    final isVpnActive = _vpnProtectionStatus == GenetVpn.protectionProtected;
    final sleepLockActive = _sleepLockActive;
    final blockedApps = _lastSyncedForVpn == null
        ? const <String>[]
        : VpnRemoteChildPolicy.effectiveBlockedPackages(_lastSyncedForVpn!);
    final protectionState = evaluateChildProtectionState(
      sleepLockActive: sleepLockActive,
      isVpnActive: isVpnActive,
      blockedApps: blockedApps,
      currentForegroundApp: _currentForegroundApp,
      currentTime: DateTime.now(),
    );
    final protectionUi = applyProtectionState(protectionState);

    if (protectionUi != null) {
      return protectionUi;
    }

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
              const SizedBox(height: 8),
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
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
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
