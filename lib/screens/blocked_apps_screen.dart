import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/genet_config.dart';
import '../core/user_role.dart';
import '../core/extension_requests.dart';
import '../models/child_entity.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';

const MethodChannel _channel = MethodChannel('com.example.genet_final/config');

String _formatRemainingParent(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// מסך רשימת אפליקציות חסומות + בקשות הארכה מהילד.
class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen({super.key});

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  List<Map<String, dynamic>> _installedApps = [];
  final List<String> _blockedPackages = [];
  List<ExtensionRequest> _extensionRequests = [];
  List<ChildEntity> _children = [];
  Map<String, int> _approvedUntil = {};
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier(true);
  String? _selectedChildId;
  String? _parentId;
  Timer? _countdownTimer;
  StreamSubscription<Map<String, dynamic>?>? _childDocSub;
  /// Avoid cancel+resubscribe on refresh when parent|child unchanged (single listener).
  String? _listenerAttachKey;
  /// Decode app icons once — full ListView rebuild was re-decoding base64 every frame (visible flicker).
  final Map<String, Uint8List> _iconBytesCache = {};
  /// True while local toggle → Firestore write is in flight (ignore echo snapshot).
  bool _isApplyingLocalBlockedWrite = false;
  /// Last snapshot fingerprint for [extensionRequests] field (realtime, no polling).
  String _lastExtensionRequestsSnapFingerprint = '';
  /// Cached once — avoids async in Firestore listener (vpnStatus pings caused rebuild churn).
  String _cachedGenetPkg = '';
  /// Fingerprint of only UI fields: blocked + extensionRequests + extensionApproved (ignores vpnStatus/updatedAt).
  String _lastChildDocUiFingerprint = '';
  /// Only drives countdown text; avoids full setState every second.
  final ValueNotifier<int> _timerTick = ValueNotifier(0);
  /// Extension / requests header — rebuilds independently from app rows (less icon flicker).
  final ValueNotifier<int> _sectionRequests = ValueNotifier(0);
  /// App rows + footer — rebuilds independently from extension UI.
  final ValueNotifier<int> _sectionApps = ValueNotifier(0);
  /// During [_loadAll]: coalesce bumps at the end (no rapid multi-flash).
  bool _suppressListBump = false;
  /// Skip redundant installed-apps work when refresh returns the same list.
  String _lastInstalledAppsFingerprint = '';

  void _bumpAllSections() {
    _sectionRequests.value++;
    _sectionApps.value++;
  }

  void _maybeBumpApps() {
    if (_suppressListBump) return;
    _sectionApps.value++;
  }

  void _maybeBumpRequests() {
    if (_suppressListBump) return;
    _sectionRequests.value++;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final sid = _selectedChildId;
      if (sid == null || sid.isEmpty) return;
      getExtensionApprovedUntil(sid).then((map) {
        if (!mounted) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        final hasActive = map.values.any((ms) => ms > now);
        if (hasActive) _timerTick.value++;
      });
    });
  }

  void _listenToChildDoc() {
    final parentId = _parentId;
    final childId = _selectedChildId;
    if (parentId == null || childId == null) return;
    final attachKey = '$parentId|$childId';
    if (_childDocSub != null && _listenerAttachKey == attachKey) {
      debugPrint('[GenetBlocked] duplicate listener prevented');
      return;
    }
    _childDocSub?.cancel();
    _listenerAttachKey = attachKey;
    final path = 'genet_parents/$parentId/children/$childId';
    debugPrint('[GenetBlocked] blocked apps listener attached path=$path');
    debugPrint('[GenetExtReq] extension request listener attached path=$path childId used=$childId');
    _childDocSub = watchParentChildDocStream(parentId, childId).listen((data) {
      if (!mounted || data == null) return;
      if (_isApplyingLocalBlockedWrite) {
        debugPrint('[GenetBlocked] skipped duplicate blockedApps update (local write in flight)');
        return;
      }
      final genetPkg = _cachedGenetPkg;
      final docFp = _childDocUiFingerprint(data, genetPkg);
      if (docFp == _lastChildDocUiFingerprint) {
        debugPrint('[GenetBlocked] full rebuild prevented (doc UI fingerprint unchanged)');
        return;
      }
      debugPrint('[GenetBlocked] blocked listener fired');
      debugPrint('[GenetExtReq] extension request listener fired');

      var remote = (data['blockedPackages'] as List?)?.cast<String>() ?? [];
      if (genetPkg.isNotEmpty) remote = remote.where((p) => p != genetPkg).toList();
      final sr = List<String>.from(remote)..sort();
      final sl = List<String>.from(_blockedPackages)..sort();
      final blockedChanged = !listEquals(sr, sl);
      if (blockedChanged) {
        debugPrint('[GenetBlocked] blocked apps changed -> applied');
      } else {
        debugPrint('[GenetBlocked] blocked apps unchanged -> skipped');
      }

      final fromSnap = _parseExtensionRequestsFromSnapshot(data);
      final mergedReq = <ExtensionRequest>[
        ..._extensionRequests.where((r) => r.childId != childId),
        ...fromSnap,
      ];
      final reqFp = _extensionSnapFpFromRequests(mergedReq);
      final prevReqFp = _extensionSnapFpFromRequests(_extensionRequests);
      final requestsChanged = reqFp != prevReqFp;
      if (requestsChanged) {
        for (final r in fromSnap) {
          debugPrint('[GenetExtReq] request received requestId=${r.id} status=${r.status}');
        }
      }

      final untilMap = _parseExtensionApprovedFromSnapshot(data);
      final approvedChanged = !_mapEquals(_approvedUntil, untilMap);

      if (!blockedChanged && !requestsChanged && !approvedChanged) {
        _lastChildDocUiFingerprint = docFp;
        debugPrint('[GenetBlocked] state update skipped due to equality (parsed lists)');
        return;
      }

      _lastChildDocUiFingerprint = docFp;
      _lastExtensionRequestsSnapFingerprint = reqFp;
      if (blockedChanged) {
        _blockedPackages
          ..clear()
          ..addAll(remote);
      }
      if (requestsChanged) {
        _extensionRequests
          ..clear()
          ..addAll(mergedReq);
      }
      if (approvedChanged) {
        _approvedUntil = untilMap;
      }
      if (blockedChanged || approvedChanged) {
        _sectionApps.value++;
      }
      if (requestsChanged) {
        _sectionRequests.value++;
      }
    });
  }

  String _extensionSnapFpFromRaw(dynamic raw) {
    if (raw == null) return '';
    if (raw is! List) return '';
    final ids = <String>[];
    for (final e in raw) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        ids.add('${m['id']}:${m['status']}');
      }
    }
    ids.sort();
    return ids.join('|');
  }

  String _extensionSnapFpFromRequests(List<ExtensionRequest> list) {
    final ids = list.map((e) => '${e.id}:${e.status}').toList()..sort();
    return ids.join('|');
  }

  String _approvedFpFromRaw(dynamic raw) {
    if (raw == null || raw is! Map) return '';
    final m = Map<String, dynamic>.from(raw);
    final keys = m.keys.toList()..sort();
    return keys.map((k) {
      final v = m[k];
      final i = v is int ? v : (v is num ? v.toInt() : 0);
      return '$k:$i';
    }).join('|');
  }

  String _approvedFpFromMap(Map<String, int> map) {
    final keys = map.keys.toList()..sort();
    return keys.map((k) => '$k:${map[k]}').join('|');
  }

  /// Same fields as Firestore doc (ignores vpnStatus / updatedAt).
  String _childDocUiFingerprint(Map<String, dynamic> data, String genetPkg) {
    var blocked = (data['blockedPackages'] as List?)?.cast<String>() ?? [];
    if (genetPkg.isNotEmpty) {
      blocked = blocked.where((p) => p != genetPkg).toList();
    }
    final bs = List<String>.from(blocked)..sort();
    final reqFp = _extensionSnapFpFromRaw(data['extensionRequests']);
    final appr = _approvedFpFromRaw(data['extensionApproved']);
    return '${bs.join(',')}|$reqFp|$appr';
  }

  String _buildLocalUiFingerprint() {
    final cid = _selectedChildId ?? '';
    final bs = List<String>.from(_blockedPackages)..sort();
    final forChild = _extensionRequests
        .where(
          (r) =>
              r.childId == cid ||
              (r.childId.isEmpty && cid.isNotEmpty),
        )
        .toList();
    final reqFp = _extensionSnapFpFromRequests(forChild);
    final appr = _approvedFpFromMap(_approvedUntil);
    return '${bs.join(',')}|$reqFp|$appr';
  }

  Map<String, int> _parseExtensionApprovedFromSnapshot(
    Map<String, dynamic> data,
  ) {
    final approvedRaw = data['extensionApproved'] as Map<String, dynamic>?;
    final approved = <String, int>{};
    if (approvedRaw != null) {
      for (final e in approvedRaw.entries) {
        final v = e.value;
        if (v is int) {
          approved[e.key] = v;
        } else if (v is num) {
          approved[e.key] = v.toInt();
        }
      }
    }
    return approved;
  }

  List<ExtensionRequest> _parseExtensionRequestsFromSnapshot(
    Map<String, dynamic> data,
  ) {
    final reqList = (data['extensionRequests'] as List?) ?? [];
    return reqList
        .map(
          (e) => ExtensionRequest.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _timerTick.dispose();
    _sectionRequests.dispose();
    _sectionApps.dispose();
    _loadingNotifier.dispose();
    _childDocSub?.cancel();
    _listenerAttachKey = null;
    super.dispose();
  }

  Future<void> _loadAll() async {
    _suppressListBump = true;
    try {
      _cachedGenetPkg = await GenetConfig.getPackageName();
      _selectedChildId = await getSelectedChildId();
      _parentId = await getParentId();
      _children = await getChildren();
      await _loadBlocked();
      await _loadInstalledApps();
      await _loadExtensionRequests();
      await _loadApprovedUntil();
      if (mounted) {
        _lastChildDocUiFingerprint = _buildLocalUiFingerprint();
        _listenToChildDoc();
      }
    } finally {
      _suppressListBump = false;
    }
    if (mounted) _bumpAllSections();
  }

  Future<void> _loadApprovedUntil() async {
    final map = await getExtensionApprovedUntil(_selectedChildId);
    if (!mounted) return;
    if (_mapEquals(_approvedUntil, map)) {
      debugPrint('[GenetBlocked] skipped identical item update (approvedUntil)');
      return;
    }
    _approvedUntil = map;
    _maybeBumpApps();
  }

  Future<void> _loadBlocked() async {
    final sid = _selectedChildId;
    var list = <String>[];
    if (sid != null && sid.isNotEmpty) {
      list = await getBlockedPackagesForChild(sid);
    }
    final genetPkg = await GenetConfig.getPackageName();
    if (genetPkg.isNotEmpty) list = list.where((p) => p != genetPkg).toList();
    final sr = List<String>.from(list)..sort();
    final sl = List<String>.from(_blockedPackages)..sort();
    if (listEquals(sr, sl)) {
      debugPrint('[GenetBlocked] skipped identical item update (blocked list)');
      return;
    }
    if (mounted) {
      _blockedPackages
        ..clear()
        ..addAll(list);
      _maybeBumpApps();
    }
  }

  Future<void> _loadExtensionRequests() async {
    final list = await getExtensionRequests();
    if (!mounted) return;
    final fp = _extensionSnapFpFromRequests(list);
    if (fp == _lastExtensionRequestsSnapFingerprint) {
      debugPrint('[GenetBlocked] skipped identical list update (extension requests)');
      return;
    }
    _lastExtensionRequestsSnapFingerprint = fp;
    _extensionRequests = list;
    _maybeBumpRequests();
  }

  Future<void> _loadInstalledApps() async {
    final showLoading = _installedApps.isEmpty;
    if (mounted && showLoading) _loadingNotifier.value = true;
    final list = await _getInstalledApps();
    if (!mounted) return;
    final fp = list.map((e) => '${e['package']}|${e['name']}').join(',');
    if (fp == _lastInstalledAppsFingerprint && list.length == _installedApps.length) {
      debugPrint('[GenetBlocked] skipped identical list update (installed apps)');
      _loadingNotifier.value = false;
      return;
    }
    _lastInstalledAppsFingerprint = fp;
    final newPkgs = list.map((e) => e['package'] as String? ?? '').toSet();
    for (final k in _iconBytesCache.keys.toList()) {
      if (!newPkgs.contains(k)) _iconBytesCache.remove(k);
    }
    _installedApps = list;
    _loadingNotifier.value = false;
  }

  Future<List<Map<String, dynamic>>> _getInstalledApps() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (raw == null) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<void> _saveBlocked() async {
    final sid = _selectedChildId;
    final parentId = _parentId;
    if (sid == null || sid.isEmpty) return;
    _isApplyingLocalBlockedWrite = true;
    try {
      await setBlockedPackagesForChild(sid, _blockedPackages);
      if (parentId != null) {
        final role = await getUserRole();
        debugPrint('[GenetVpn] ROLE: $role');
        await syncBlockedPackagesToFirebase(parentId, sid, _blockedPackages);
      }
    } finally {
      _isApplyingLocalBlockedWrite = false;
    }
  }

  Future<void> _toggleBlock(String packageName) async {
    if (_selectedChildId == null || _selectedChildId!.isEmpty) return;
    final genetPkg = await GenetConfig.getPackageName();
    if (genetPkg.isNotEmpty && packageName == genetPkg) return;
    if (_blockedPackages.contains(packageName)) {
      _blockedPackages.remove(packageName);
    } else {
      _blockedPackages.add(packageName);
    }
    _maybeBumpApps();
    await _saveBlocked();
  }

  Future<void> _approveRequest(ExtensionRequest req) async {
    final childId = req.childId.isNotEmpty ? req.childId : _selectedChildId;
    final parentId = _parentId;
    if (childId == null || childId.isEmpty) return;
    final untilMs =
        DateTime.now().millisecondsSinceEpoch + req.minutes * 60 * 1000;
    final map = await getExtensionApprovedUntil(childId);
    map[req.packageName] = untilMs;
    await saveExtensionApprovedUntil(map, childId);
    final list = await getExtensionRequests();
    final idx = list.indexWhere((e) => e.id == req.id);
    if (idx >= 0)
      list[idx] = list[idx].copyWith(status: ExtensionRequestStatus.approved);
    await saveExtensionRequests(list);
    if (parentId != null) {
      await updateExtensionRequestInFirebase(
        parentId,
        childId,
        req.id,
        ExtensionRequestStatus.approved,
        approvedUntilMs: untilMs,
        packageName: req.packageName,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${req.childDisplayName.isNotEmpty ? "${req.childDisplayName} – " : ""}${req.appName} אושר זמנית ל־${req.minutes} דקות',
          ),
        ),
      );
      _loadExtensionRequests();
      _loadApprovedUntil();
    }
  }

  Future<void> _rejectRequest(ExtensionRequest req) async {
    final childId = req.childId.isNotEmpty ? req.childId : _selectedChildId;
    final parentId = _parentId;
    final list = await getExtensionRequests();
    final idx = list.indexWhere((e) => e.id == req.id);
    if (idx >= 0)
      list[idx] = list[idx].copyWith(status: ExtensionRequestStatus.rejected);
    await saveExtensionRequests(list);
    if (parentId != null && childId != null) {
      await updateExtensionRequestInFirebase(
        parentId,
        childId,
        req.id,
        ExtensionRequestStatus.rejected,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('בקשת הארכה ל־${req.appName} נדחתה')),
      );
      _loadExtensionRequests();
    }
  }

  Future<void> _cancelExtension(String packageName) async {
    final sid = _selectedChildId;
    final parentId = _parentId;
    if (sid == null || sid.isEmpty) return;
    final map = await getExtensionApprovedUntil(sid);
    map.remove(packageName);
    await saveExtensionApprovedUntil(map, sid);
    if (parentId != null) {
      await cancelExtensionInFirebase(parentId, sid, packageName);
    }
    if (mounted) {
      _approvedUntil = Map.from(map);
      _maybeBumpApps();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הארכת הזמן בוטלה, האפליקציה נחסמה שוב')),
      );
    }
  }

  int? _remainingSeconds(String packageName) {
    final untilMs = _approvedUntil[packageName];
    if (untilMs == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (untilMs <= now) return null;
    return ((untilMs - now) / 1000).floor();
  }

  Set<String> get _currentChildIds =>
      _children.map((c) => c.childId).toSet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _loadingNotifier,
      builder: (context, loading, _) {
        debugPrint('[GenetBlocked] blocked apps screen rebuild (loading=$loading)');
        return Scaffold(
      appBar: AppBar(
        title: const Text('אפליקציות חסומות'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loading
                ? null
                : () async {
                    await _loadAll();
                  },
            tooltip: 'רענן',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RepaintBoundary(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: ValueListenableBuilder<int>(
                      valueListenable: _sectionRequests,
                      builder: (context, _, __) {
                        final childIds = _currentChildIds;
                        final pendingRequests = _extensionRequests
                            .where((r) =>
                                r.status == ExtensionRequestStatus.pending &&
                                (r.childId.isEmpty
                                    ? (_selectedChildId != null &&
                                        childIds.contains(_selectedChildId))
                                    : childIds.contains(r.childId)))
                            .toList();
                        final otherRequests = _extensionRequests
                            .where((r) =>
                                r.status != ExtensionRequestStatus.pending &&
                                (r.childId.isEmpty
                                    ? (_selectedChildId != null &&
                                        childIds.contains(_selectedChildId))
                                    : childIds.contains(r.childId)))
                            .toList();
                        return SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_selectedChildId == null ||
                                  _selectedChildId!.isEmpty) ...[
                                Card(
                                  color: Colors.amber.shade50,
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'נא לבחור ילד במסך "ילדים" כדי לנהל חסימות ובקשות הארכה.',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const Text(
                                'בקשות הארכה',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (pendingRequests.isEmpty &&
                                  otherRequests.isEmpty)
                                Card(
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('אין בקשות הארכה'),
                                  ),
                                )
                              else ...[
                                ...pendingRequests.map(
                                  (req) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (req.childDisplayName
                                                    .isNotEmpty)
                                                  Text(
                                                    req.childDisplayName,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade700,
                                                    ),
                                                  ),
                                                Text(
                                                  req.appName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  '${req.minutes} דקות',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _rejectRequest(req),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                            ),
                                            child: const Text('דחייה'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.primaryBlue,
                                            ),
                                            onPressed: () =>
                                                _approveRequest(req),
                                            child: const Text('אישור'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (otherRequests.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'היסטוריה',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...otherRequests
                                      .take(20)
                                      .map(
                                        (req) => Card(
                                          margin:
                                              const EdgeInsets.only(bottom: 6),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${req.childDisplayName.isNotEmpty ? "${req.childDisplayName} – " : ""}${req.appName} – ${req.minutes} דקות',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  req.status ==
                                                          ExtensionRequestStatus
                                                              .approved
                                                      ? 'אושר'
                                                      : 'נדחה',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: req.status ==
                                                            ExtensionRequestStatus
                                                                .approved
                                                        ? Colors.green.shade700
                                                        : Colors.red.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _sectionApps,
                    builder: (context, _, __) {
                      debugPrint('[GenetBlocked] blocked apps list rebuild');
                      if (_selectedChildId == null ||
                          _selectedChildId!.isEmpty) {
                        return const SliverToBoxAdapter(child: SizedBox.shrink());
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == 0) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      'בחר את האפליקציות שתיחסמנה',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                );
                              }
                              if (index == _installedApps.length + 1) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'הערה: חסימת אפליקציות בפועל דורשת הרשאות מערכת Android.',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }
                              final app = _installedApps[index - 1];
                              final packageName =
                                  app['package'] as String? ?? '';
                              final name =
                                  app['name'] as String? ?? packageName;
                              final iconBase64 = app['icon'] as String?;
                              final blocked =
                                  _blockedPackages.contains(packageName);
                              final hasActiveExtension = blocked &&
                                  _remainingSeconds(packageName) != null;
                              return _InstalledAppTile(
                                key: ValueKey<String>('blocked_app_$packageName'),
                                packageName: packageName,
                                label: name,
                                iconBase64: iconBase64,
                                blocked: blocked,
                                hasActiveExtension: hasActiveExtension,
                                onToggle: () => _toggleBlock(packageName),
                                onCancel: () => _cancelExtension(packageName),
                                timerTick: _timerTick,
                                remainingSeconds: () =>
                                    _remainingSeconds(packageName),
                                buildIcon: _buildAppIcon,
                              );
                            },
                            childCount: _installedApps.length + 2,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        );
      },
    );
  }

  Widget? _buildAppIcon(String packageName, String? base64) {
    if (base64 == null || base64.isEmpty) return null;
    try {
      var bytes = _iconBytesCache[packageName];
      if (bytes == null) {
        bytes = base64Decode(base64);
        _iconBytesCache[packageName] = bytes;
      }
      return Image.memory(
        bytes,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One row — [ListView.builder] + [ValueKey] keeps rebuilds off the extension header sliver.
class _InstalledAppTile extends StatefulWidget {
  const _InstalledAppTile({
    super.key,
    required this.packageName,
    required this.label,
    required this.iconBase64,
    required this.blocked,
    required this.hasActiveExtension,
    required this.onToggle,
    required this.onCancel,
    required this.timerTick,
    required this.remainingSeconds,
    required this.buildIcon,
  });

  final String packageName;
  final String label;
  final String? iconBase64;
  final bool blocked;
  final bool hasActiveExtension;
  final VoidCallback onToggle;
  final VoidCallback onCancel;
  final ValueNotifier<int> timerTick;
  final int? Function() remainingSeconds;
  final Widget? Function(String packageName, String? base64) buildIcon;

  @override
  State<_InstalledAppTile> createState() => _InstalledAppTileState();
}

class _InstalledAppTileState extends State<_InstalledAppTile> {
  @override
  Widget build(BuildContext context) {
    debugPrint('[GenetBlocked] app tile build: package=${widget.packageName}');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            secondary: widget.buildIcon(widget.packageName, widget.iconBase64),
            title: Text(widget.label),
            value: widget.blocked,
            onChanged: (v) {
              if (v == widget.blocked) return;
              widget.onToggle();
            },
            activeThumbColor: AppTheme.primaryBlue,
          ),
          if (widget.hasActiveExtension)
            ValueListenableBuilder<int>(
              valueListenable: widget.timerTick,
              builder: (context, _, _) {
                final sec = widget.remainingSeconds();
                if (sec == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer,
                        size: 16,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'הארכה פעילה – זמן שנותר: ${_formatRemainingParent(sec)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: widget.onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('ביטול הארכה'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
