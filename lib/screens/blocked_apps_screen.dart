import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/genet_config.dart';
import '../theme/app_theme.dart';

const String _kBlockedAppsKey = 'genet_blocked_apps';
const MethodChannel _channel = MethodChannel('com.example.genet_final/config');

/// מסך רשימת אפליקציות חסומות — רק אפליקציות מותקנות במכשיר (Launcher).
class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen({super.key});

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  List<Map<String, dynamic>> _installedApps = [];
  final List<String> _blockedPackages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
    _loadInstalledApps();
  }

  Future<void> _loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kBlockedAppsKey) ?? [];
    setState(() => _blockedPackages
      ..clear()
      ..addAll(list));
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _loading = true);
    final list = await _getInstalledApps();
    setState(() {
      _installedApps = list;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _getInstalledApps() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (raw == null) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<void> _saveBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBlockedAppsKey, _blockedPackages);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('אפליקציות חסומות'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadInstalledApps,
            tooltip: 'רענן',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
