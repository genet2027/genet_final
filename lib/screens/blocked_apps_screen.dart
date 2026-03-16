import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/genet_config.dart';
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
  bool _loading = true;
  String? _selectedChildId;
  String? _parentId;
  Timer? _extensionTimer;
  StreamSubscription<Map<String, dynamic>?>? _childDocSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _extensionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final sid = _selectedChildId;
      final map = await getExtensionApprovedUntil(sid);
      if (mounted) setState(() => _approvedUntil = map);
    });
  }

  void _listenToChildDoc() {
    _childDocSub?.cancel();
    final parentId = _parentId;
    final childId = _selectedChildId;
    if (parentId == null || childId == null) return;
    _childDocSub = watchParentChildDocStream(parentId, childId).listen((_) {
      if (mounted) {
        _loadExtensionRequests();
        _loadApprovedUntil();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _extensionTimer?.cancel();
    _childDocSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _selectedChildId = await getSelectedChildId();
    _parentId = await getParentId();
    _children = await getChildren();
    await _loadBlocked();
    await _loadInstalledApps();
    await _loadExtensionRequests();
    await _loadApprovedUntil();
    if (mounted) _listenToChildDoc();
  }

  Future<void> _loadApprovedUntil() async {
    final map = await getExtensionApprovedUntil(_selectedChildId);
    if (mounted) setState(() => _approvedUntil = map);
  }

  Future<void> _loadBlocked() async {
    final sid = _selectedChildId;
    var list = <String>[];
    if (sid != null && sid.isNotEmpty) {
      list = await getBlockedPackagesForChild(sid);
    }
    final genetPkg = await GenetConfig.getPackageName();
    if (genetPkg.isNotEmpty) list = list.where((p) => p != genetPkg).toList();
    if (mounted) {
      setState(
        () => _blockedPackages
          ..clear()
          ..addAll(list),
      );
    }
  }

  Future<void> _loadExtensionRequests() async {
    final list = await getExtensionRequests();
    if (mounted) setState(() => _extensionRequests = list);
  }

  Future<void> _loadInstalledApps() async {
    if (mounted) setState(() => _loading = true);
    final list = await _getInstalledApps();
    if (mounted) {
      setState(() {
        _installedApps = list;
        _loading = false;
      });
    }
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
    await setBlockedPackagesForChild(sid, _blockedPackages);
    if (parentId != null) {
      await syncBlockedPackagesToFirebase(parentId, sid, _blockedPackages);
    }
  }

  Future<void> _toggleBlock(String packageName) async {
    if (_selectedChildId == null || _selectedChildId!.isEmpty) return;
    final genetPkg = await GenetConfig.getPackageName();
    if (genetPkg.isNotEmpty && packageName == genetPkg) return;
    setState(() {
      if (_blockedPackages.contains(packageName)) {
        _blockedPackages.remove(packageName);
      } else {
        _blockedPackages.add(packageName);
      }
      _saveBlocked();
    });
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
      setState(() => _approvedUntil = Map.from(map));
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
    final childIds = _currentChildIds;
    final pendingRequests = _extensionRequests
        .where((r) =>
            r.status == ExtensionRequestStatus.pending &&
            (r.childId.isEmpty ? (_selectedChildId != null && childIds.contains(_selectedChildId)) : childIds.contains(r.childId)))
        .toList();
    final otherRequests = _extensionRequests
        .where((r) =>
            r.status != ExtensionRequestStatus.pending &&
            (r.childId.isEmpty ? (_selectedChildId != null && childIds.contains(_selectedChildId)) : childIds.contains(r.childId)))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('אפליקציות חסומות'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () async {
                    await _loadAll();
                  },
            tooltip: 'רענן',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_selectedChildId == null || _selectedChildId!.isEmpty) ...[
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
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (pendingRequests.isEmpty && otherRequests.isEmpty)
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (req.childDisplayName.isNotEmpty)
                                    Text(
                                      req.childDisplayName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
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
                              onPressed: () => _rejectRequest(req),
                              child: const Text('דחייה'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                              ),
                              onPressed: () => _approveRequest(req),
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
                            margin: const EdgeInsets.only(bottom: 6),
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
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    req.status ==
                                            ExtensionRequestStatus.approved
                                        ? 'אושר'
                                        : 'נדחה',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          req.status ==
                                              ExtensionRequestStatus.approved
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
                if (_selectedChildId != null && _selectedChildId!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'בחר את האפליקציות שתיחסמנה',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ..._installedApps.map((app) {
                  final packageName = app['package'] as String? ?? '';
                  final name = app['name'] as String? ?? packageName;
                  final iconBase64 = app['icon'] as String?;
                  final blocked = _blockedPackages.contains(packageName);
                  final hasActiveExtension = blocked && _remainingSeconds(packageName) != null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          secondary: _buildAppIcon(iconBase64),
                          title: Text(name),
                          value: blocked,
                          onChanged: (_) => _toggleBlock(packageName),
                          activeThumbColor: AppTheme.primaryBlue,
                        ),
                        if (hasActiveExtension)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Icon(Icons.timer, size: 16, color: Colors.green.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  'הארכה פעילה – זמן שנותר: ${_formatRemainingParent(_remainingSeconds(packageName)!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () => _cancelExtension(packageName),
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
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'הערה: חסימת אפליקציות בפועל דורשת הרשאות מערכת Android.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                ],
              ],
            ),
    );
  }

  Widget? _buildAppIcon(String? base64) {
    if (base64 == null || base64.isEmpty) return null;
    try {
      final bytes = base64Decode(base64);
      return Image.memory(bytes, width: 40, height: 40, fit: BoxFit.contain);
    } catch (_) {
      return null;
    }
  }
}
