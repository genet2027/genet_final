import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kSleepLockEnabledKey = 'genet_sleep_lock_enabled';
const String _kSleepLockStartKey = 'genet_sleep_lock_start';
const String _kSleepLockEndKey = 'genet_sleep_lock_end';
const String _kBlockedAppsKey = 'genet_blocked_apps';
const String _kPendingExtensionRequestsKey = 'genet_pending_extension_requests';

/// אפליקציות חסומות וזמני שימוש – מסך הילד. זמני נעילה + רשימת חסומות + בקשת הארכה (15/30/60 דקות).
class BlockedAppsTimesScreen extends StatefulWidget {
  const BlockedAppsTimesScreen({super.key});

  @override
  State<BlockedAppsTimesScreen> createState() => _BlockedAppsTimesScreenState();
}

class _BlockedAppsTimesScreenState extends State<BlockedAppsTimesScreen> {
  bool _lockEnabled = false;
  String _startTime = '20:00';
  String _endTime = '08:00';
  List<String> _blockedIds = [];
  static const List<Map<String, dynamic>> _allApps = [
    {'id': 'whatsapp', 'name': 'WhatsApp'},
    {'id': 'instagram', 'name': 'Instagram'},
    {'id': 'tiktok', 'name': 'TikTok'},
    {'id': 'youtube', 'name': 'YouTube'},
    {'id': 'games', 'name': 'משחקים'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lockEnabled = prefs.getBool(_kSleepLockEnabledKey) ?? false;
      _startTime = prefs.getString(_kSleepLockStartKey) ?? '20:00';
      _endTime = prefs.getString(_kSleepLockEndKey) ?? '08:00';
      _blockedIds = prefs.getStringList(_kBlockedAppsKey) ?? [];
    });
  }

  void _showExtensionBottomSheet(String appId, String appName) {
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
                  onTap: () => _sendExtensionRequest(appId, appName, 15),
                  onClose: () => Navigator.pop(context),
                ),
                _ExtensionOption(
                  label: '30 דקות',
                  onTap: () => _sendExtensionRequest(appId, appName, 30),
                  onClose: () => Navigator.pop(context),
                ),
                _ExtensionOption(
                  label: '60 דקות',
                  onTap: () => _sendExtensionRequest(appId, appName, 60),
                  onClose: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendExtensionRequest(String appId, String appName, int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingExtensionRequestsKey);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = List<Map<String, dynamic>>.from(
            (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }
    list.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'appId': appId,
      'appName': appName,
      'minutes': minutes,
    });
    await prefs.setString(_kPendingExtensionRequestsKey, jsonEncode(list));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הבקשה נשלחה וממתינה לאישור ההורה')),
      );
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
        body: ListView(
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
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (_blockedIds.isEmpty)
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
              ..._allApps.where((app) => _blockedIds.contains(app['id'])).map((app) {
                  final id = app['id'] as String;
                  final name = app['name'] as String;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 16),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showExtensionBottomSheet(id, name),
                            icon: const Icon(Icons.schedule, size: 18),
                            label: const Text('בקשת הארכה'),
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
