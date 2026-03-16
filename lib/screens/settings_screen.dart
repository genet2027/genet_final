import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/genet_config.dart';
import '../core/pin_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/rounded_card.dart';
import 'backup_support_screen.dart';
import 'night_mode_settings_screen.dart';
import 'pin_login_screen.dart';

const String _kPermissionLockKey = 'genet_permission_lock_enabled';

/// Settings tab content: entries to Night Mode, Permission Lock, Backup & Support, and Logout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _permissionLockEnabled = false;
  bool _loaded = false;
  List<String> _missingPermissions = [];
  bool _deviceAdminEnabled = false;
  bool _batteryOptimizationIgnored = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionLock();
    _loadPermissionsSection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPermissionsSection();
  }

  Future<void> _loadPermissionLock() async {
    final v = await GenetConfig.getPermissionLockEnabled();
    if (mounted) setState(() { _permissionLockEnabled = v; _loaded = true; });
  }

  Future<void> _loadPermissionsSection() async {
    if (!Platform.isAndroid) return;
    final missing = await GenetConfig.getMissingPermissions();
    final deviceAdmin = await GenetConfig.getIsDeviceAdminEnabled();
    final battery = await GenetConfig.isIgnoringBatteryOptimizations();
    if (mounted) setState(() {
      _missingPermissions = missing;
      _deviceAdminEnabled = deviceAdmin;
      _batteryOptimizationIgnored = battery;
    });
  }

  Future<bool> _verifyOrCreatePin(BuildContext context, {required bool isCreate}) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isCreate ? 'יצירת קוד PIN' : 'אימות קוד PIN'),
          content: isCreate
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'קוד PIN חדש'),
                    ),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'אימות קוד PIN'),
                    ),
                  ],
                )
              : TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'קוד PIN'),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            FilledButton(
              onPressed: () async {
                final pin = pinController.text;
                if (pin.length < 4) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('לפחות 4 ספרות')));
                  return;
                }
                if (isCreate) {
                  if (pin != confirmController.text) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('הקודים לא תואמים')));
                    return;
                  }
                  await PinStorage.savePin(pin);
                  if (mounted) GenetConfig.setPin(pin);
                } else {
                  final ok = await PinStorage.verifyPin(pin);
                  if (!ok) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('קוד PIN שגוי')));
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('אישור'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _onPermissionLockToggle(bool value) async {
    final hasPin = await PinStorage.hasPin();
    final ok = await _verifyOrCreatePin(context, isCreate: !hasPin);
    if (!ok || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionLockKey, value);
    await GenetConfig.setPermissionLockEnabled(value);
    if (mounted) setState(() => _permissionLockEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NightModeSettingsScreen(),
            ),
          ),
          icon: Icons.bedtime_rounded,
          title: 'מצב לילה (חופשת שינה)',
          subtitle: 'שעות שינה ורמת התנהגות',
        ),
        const SizedBox(height: 12),
        RoundedCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, color: AppTheme.primaryBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('נעילת הרשאות / Lock permissions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            'חוסם גישה למסכי הרשאות מערכת (Accessibility/Usage/Overlay) כדי למנוע עקיפה.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    if (_loaded)
                      Switch(
                        value: _permissionLockEnabled,
                        onChanged: _onPermissionLockToggle,
                        activeThumbColor: AppTheme.primaryBlue,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: Text(
              'הרשאות מערכת',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          _PermissionRow(
            title: 'Accessibility Service',
            enabled: !_missingPermissions.contains('accessibility'),
            onOpenSettings: () async {
              await GenetConfig.openAccessibilitySettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Usage Access',
            enabled: !_missingPermissions.contains('usage'),
            onOpenSettings: () async {
              await GenetConfig.openUsageAccessSettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Display Over Other Apps (Overlay)',
            enabled: !_missingPermissions.contains('overlay'),
            onOpenSettings: () async {
              await GenetConfig.openOverlaySettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Ignore Battery Optimization',
            enabled: _batteryOptimizationIgnored,
            onOpenSettings: () async {
              await GenetConfig.openBatteryOptimizationSettings();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            title: 'Device Admin',
            enabled: _deviceAdminEnabled,
            onOpenSettings: () async {
              await GenetConfig.enableDeviceAdmin();
              await _loadPermissionsSection();
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        RoundedCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BackupSupportScreen(),
            ),
          ),
          icon: Icons.backup_rounded,
          title: 'גיבוי ותמיכה',
          subtitle: 'ייצוא/ייבוא גיבוי, דיווח בעיה, צור קשר',
        ),
        const SizedBox(height: 32),
        RoundedCard(
          onTap: () => _logout(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.logout_rounded,
                    color: Colors.red.shade400, size: 28),
                const SizedBox(width: 16),
                Text(
                  'יציאה',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      (route) => false,
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.enabled,
    required this.onOpenSettings,
  });
  final String title;
  final bool enabled;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      fontSize: 13,
                      color: enabled ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('פתח הגדרות'),
            ),
          ],
        ),
      ),
    );
  }
}
