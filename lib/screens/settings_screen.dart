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

class _SettingsScreenState extends State<SettingsScreen> {
  bool _permissionLockEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionLock();
  }

  Future<void> _loadPermissionLock() async {
    final v = await GenetConfig.getPermissionLockEnabled();
    if (mounted) setState(() { _permissionLockEnabled = v; _loaded = true; });
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
