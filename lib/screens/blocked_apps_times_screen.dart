import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/extension_requests.dart';
import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
import '../theme/app_theme.dart';

const String _kSleepLockEnabledKey = 'genet_sleep_lock_enabled';
const String _kSleepLockStartKey = 'genet_sleep_lock_start';
const String _kSleepLockEndKey = 'genet_sleep_lock_end';

const MethodChannel _channel = MethodChannel('com.example.genet_final/config');

String _formatRemaining(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// אפליקציות חסומות וזמני שימוש – מסך הילד. מסונכרן עם רשימת ההורה. בקשת הארכה משויכת לאפליקציה.
class BlockedAppsTimesScreen extends StatefulWidget {
  const BlockedAppsTimesScreen({super.key});

  @override
  State<BlockedAppsTimesScreen> createState() => _BlockedAppsTimesScreenState();
}

class _BlockedAppsTimesScreenState extends State<BlockedAppsTimesScreen> {
  bool _lockEnabled = false;
  String _startTime = '20:00';
  String _endTime = '08:00';
  List<String> _blockedPackages = [];
  List<Map<String, dynamic>> _installedApps = [];
  List<ExtensionRequest> _requests = [];
  Map<String, int> _approvedUntil = {};
  bool _loading = true;
  String? _linkedChildId;
  Timer? _countdownTimer;
  StreamSubscription<SyncedChildData?>? _syncSub;

  @override
  void initState() {
    super.initState();
    _load();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final cid = _linkedChildId;
      final map = await getExtensionApprovedUntil(cid);
      if (mounted) setState(() => _approvedUntil = map);
    });
    getLinkedParentId().then((parentId) {
      getLinkedChildId().then((childId) {
        if (parentId != null && childId != null && mounted) {
          _syncSub = watchSyncedChildDataStream(parentId, childId).listen((data) {
            if (data != null && mounted) {
              setState(() {
                _blockedPackages = data.blockedPackages;
                _approvedUntil = Map.from(data.extensionApproved);
                _requests = data.extensionRequests;
              });
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final linkedId = await getLinkedChildId();
    var blocked = <String>[];
    Map<String, int> approvedUntil = {};
    if (linkedId != null && linkedId.isNotEmpty) {
      blocked = await getBlockedPackagesForChild(linkedId);
      approvedUntil = await getExtensionApprovedForChild(linkedId);
    } else {
      blocked = prefs.getStringList('genet_blocked_packages') ?? [];
      if (blocked.isEmpty) {
        final legacy = prefs.getStringList('genet_blocked_apps') ?? [];
        if (legacy.isNotEmpty) blocked = legacy;
      }
      approvedUntil = await getExtensionApprovedUntil();
    }
    List<Map<String, dynamic>> installed = [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw != null) installed = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (_) {}
    final requests = await getExtensionRequests();
    if (mounted) {
      setState(() {
        _linkedChildId = linkedId;
        _lockEnabled = prefs.getBool(_kSleepLockEnabledKey) ?? false;
        _startTime = prefs.getString(_kSleepLockStartKey) ?? '20:00';
        _endTime = prefs.getString(_kSleepLockEndKey) ?? '08:00';
        _blockedPackages = blocked;
        _installedApps = installed;
        _requests = linkedId != null && linkedId.isNotEmpty
            ? requests.where((r) => r.childId == linkedId).toList()
            : requests;
        _approvedUntil = approvedUntil;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _blockedAppsWithNames {
    return _installedApps.where((app) {
      final pkg = app['package'] as String? ?? '';
      return _blockedPackages.contains(pkg);
    }).toList();
  }

  String _requestStatusForPackage(String packageName) {
    final untilMs = _approvedUntil[packageName];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (untilMs != null && untilMs > now) return 'אושר זמנית';
    final r = _requests.where((e) => e.packageName == packageName).toList();
    if (r.isEmpty) return '';
    final last = r.last;
    if (last.status == ExtensionRequestStatus.pending) return 'ממתין לאישור';
    if (last.status == ExtensionRequestStatus.approved) return ''; // הארכה הסתיימה – לא להציג אושר זמנית
    return 'נדחה';
  }

  int? _remainingSeconds(String packageName) {
    final untilMs = _approvedUntil[packageName];
    if (untilMs == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (untilMs <= now) return null;
    return ((untilMs - now) / 1000).floor();
  }

  void _showExtensionBottomSheet(String packageName, String appName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'בקשת הארכה – $appName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _ExtensionOption(
                  label: '15 דקות',
                  onTap: () => _sendExtensionRequest(packageName, appName, 15),
                  onClose: () => Navigator.pop(context),
                ),
                _ExtensionOption(
                  label: '30 דקות',
                  onTap: () => _sendExtensionRequest(packageName, appName, 30),
                  onClose: () => Navigator.pop(context),
                ),
                _ExtensionOption(
                  label: '60 דקות',
                  onTap: () => _sendExtensionRequest(packageName, appName, 60),
                  onClose: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendExtensionRequest(String packageName, String appName, int minutes) async {
    final linkedId = await getLinkedChildId();
    final linkedParentId = await getLinkedParentId();
    final linkedName = await getLinkedChildName();
    final firstName = await getLinkedChildFirstName();
    final lastName = await getLinkedChildLastName();
    final list = await getExtensionRequests();
    final req = ExtensionRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      packageName: packageName,
      appName: appName,
      minutes: minutes,
      status: ExtensionRequestStatus.pending,
      requestedAt: DateTime.now().millisecondsSinceEpoch,
      childId: linkedId ?? '',
      childName: linkedName ?? '',
      childFirstName: firstName ?? '',
      childLastName: lastName ?? '',
    );
    list.add(req);
    await saveExtensionRequests(list);
    if (linkedParentId != null && linkedId != null) {
      await addExtensionRequestToFirebase(linkedParentId, linkedId, req);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הבקשה נשלחה וממתינה לאישור ההורה')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('אפליקציות חסומות וזמני שימוש'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'זמני נעילה',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lockEnabled
                                ? 'הטלפון נעול מ־$_startTime עד $_endTime'
                                : 'אין נעילה פעילה',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'אפליקציות חסומות',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (_blockedAppsWithNames.isEmpty)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('אין אפליקציות חסומות כרגע'),
                      ),
                    )
                  else
                    ..._blockedAppsWithNames.map((app) {
                      final pkg = app['package'] as String? ?? '';
                      final name = app['name'] as String? ?? pkg;
                      final status = _requestStatusForPackage(pkg);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
                                    Text(
                                      name,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (status.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          status,
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: status == 'נדחה'
                                                ? Colors.red.shade700
                                                : status == 'אושר זמנית'
                                                    ? Colors.green.shade700
                                                    : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    if (_remainingSeconds(pkg) != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.timer, size: 14, color: Colors.green.shade700),
                                            const SizedBox(width: 4),
                                            Text(
                                              'זמן שנותר: ${_formatRemaining(_remainingSeconds(pkg)!)}',
                                              textDirection: TextDirection.rtl,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _showExtensionBottomSheet(pkg, name),
                                icon: const Icon(Icons.schedule, size: 18),
                                label: const Text('בקשת הארכה'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}

class _ExtensionOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _ExtensionOption({
    required this.label,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, textDirection: TextDirection.rtl),
      onTap: () {
        onTap();
        onClose();
      },
    );
  }
}
