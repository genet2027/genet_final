import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

const String _kBlockedAppsKey = 'genet_blocked_apps';

/// מסך רשימת אפליקציות חסומות
class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen({super.key});

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  // אפליקציות לדוגמה - בפועל ייטענו מהמערכת
  static const List<Map<String, dynamic>> _allApps = [
    {'id': 'whatsapp', 'name': 'WhatsApp', 'package': 'com.whatsapp'},
    {
      'id': 'instagram',
      'name': 'Instagram',
      'package': 'com.instagram.android',
    },
    {'id': 'tiktok', 'name': 'TikTok', 'package': 'com.zhiliaoapp.musically'},
    {
      'id': 'youtube',
      'name': 'YouTube',
      'package': 'com.google.android.youtube',
    },
    {'id': 'games', 'name': 'משחקים', 'package': 'com.android.vending'},
  ];

  final List<String> _blockedIds = [];

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kBlockedAppsKey) ?? [];
    setState(() => _blockedIds.addAll(list));
  }

  Future<void> _saveBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBlockedAppsKey, _blockedIds);
  }

  void _toggleBlock(String id) {
    setState(() {
      if (_blockedIds.contains(id)) {
        _blockedIds.remove(id);
      } else {
        _blockedIds.add(id);
      }
      _saveBlocked();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('אפליקציות חסומות')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'בחר את האפליקציות שתיחסמנה',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ..._allApps.map((app) {
            final id = app['id'] as String;
            final name = app['name'] as String;
            final blocked = _blockedIds.contains(id);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                title: Text(name),
                value: blocked,
                onChanged: (_) => _toggleBlock(id),
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
}
