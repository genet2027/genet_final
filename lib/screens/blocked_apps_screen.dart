import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/genet_config.dart';
import '../core/extension_requests.dart';
import '../theme/app_theme.dart';

const String _kBlockedPackagesKey = 'genet_blocked_packages';
const MethodChannel _channel = MethodChannel('com.example.genet_final/config');

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadBlocked();
    await _loadInstalledApps();
    await _loadExtensionRequests();
  }

  Future<void> _loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    var list = prefs.getStringList(_kBlockedPackagesKey) ?? [];
    if (list.isEmpty) {
      final legacy = prefs.getStringList('genet_blocked_apps') ?? [];
      if (legacy.isNotEmpty) {
        await prefs.setStringList(_kBlockedPackagesKey, legacy);
        await GenetConfig.setBlockedApps(legacy);
        list = legacy;
      }
    }
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBlockedPackagesKey, _blockedPackages);
    await GenetConfig.setBlockedApps(_blockedPackages);
  }

  void _toggleBlock(String packageName) {
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
    final untilMs =
        DateTime.now().millisecondsSinceEpoch + req.minutes * 60 * 1000;
    final map = await getExtensionApprovedUntil();
    map[req.packageName] = untilMs;
    await saveExtensionApprovedUntil(map);
    await GenetConfig.setExtensionApproved(map);
    final list = await getExtensionRequests();
    final idx = list.indexWhere((e) => e.id == req.id);
    if (idx >= 0)
      list[idx] = list[idx].copyWith(status: ExtensionRequestStatus.approved);
    await saveExtensionRequests(list);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${req.appName} אושר זמנית ל־${req.minutes} דקות'),
        ),
      );
      _loadExtensionRequests();
    }
  }

  Future<void> _rejectRequest(ExtensionRequest req) async {
    final list = await getExtensionRequests();
    final idx = list.indexWhere((e) => e.id == req.id);
    if (idx >= 0)
      list[idx] = list[idx].copyWith(status: ExtensionRequestStatus.rejected);
    await saveExtensionRequests(list);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('בקשת הארכה ל־${req.appName} נדחתה')),
      );
      _loadExtensionRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = _extensionRequests
        .where((r) => r.status == ExtensionRequestStatus.pending)
        .toList();
    final otherRequests = _extensionRequests
        .where((r) => r.status != ExtensionRequestStatus.pending)
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
                                      '${req.appName} – ${req.minutes} דקות',
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

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: SwitchListTile(
                      secondary: _buildAppIcon(iconBase64),
                      title: Text(name),
                      value: blocked,
                      onChanged: (_) => _toggleBlock(packageName),
                      activeThumbColor: AppTheme.primaryBlue,
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'הערה: חסימת אפליקציות בפועל דורשת הרשאות מערכת Android.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
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
