import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../core/pin_storage.dart';
import '../theme/app_theme.dart';

/// מסך חובה: הרשאות חסרות. לא ניתן לצאת עד שההרשאות פעילות או עד אישור הורה + חלון תחזוקה.
class RequiredPermissionsScreen extends StatefulWidget {
  const RequiredPermissionsScreen({
    super.key,
    this.onDismiss,
  });
  final VoidCallback? onDismiss;

  @override
  State<RequiredPermissionsScreen> createState() => _RequiredPermissionsScreenState();
}

class _RequiredPermissionsScreenState extends State<RequiredPermissionsScreen> with WidgetsBindingObserver {
  List<String> _missing = [];
  bool _loading = true;
  Timer? _maintenanceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maintenanceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final list = await GenetConfig.getMissingPermissions();
    final filtered = list.where((e) => e != 'accessibility').toList();
    if (mounted) {
      setState(() {
        _missing = filtered;
        _loading = false;
      });
      if (filtered.isEmpty) {
        widget.onDismiss?.call();
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _openFirstMissing() async {
    if (_missing.isEmpty) return;
    final first = _missing.first;
    if (first == 'overlay') {
      await GenetConfig.openOverlaySettings();
    } else if (first == 'usage') {
      await GenetConfig.openUsageAccessSettings();
    }
  }

  Future<void> _parentApproval() async {
    final ok = await _verifyPin(context);
    if (!ok || !mounted) return;
    final endMs = DateTime.now().millisecondsSinceEpoch + 60000;
    await GenetConfig.setMaintenanceWindowEnd(endMs);
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer(const Duration(seconds: 60), () async {
      await GenetConfig.setMaintenanceWindowEnd(0);
      if (mounted) setState(() {});
    });
    await _openFirstMissing();
  }

  Future<bool> _verifyPin(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('אימות קוד PIN'),
          content: TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'קוד PIN'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            FilledButton(
              onPressed: () async {
                final ok = await PinStorage.verifyPin(controller.text);
                if (!ctx.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('קוד PIN שגוי')));
                  return;
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange.shade700),
                const SizedBox(height: 16),
                const Text(
                  'הרשאות מערכת',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'חסימה מבוססת VPN. כשהן חסרות, יש להפעיל גישה לשימוש והצגה מעל אפליקציות.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                if (!_loading) ...[
                  const SizedBox(height: 24),
                  ..._missing.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_label(e), style: TextStyle(color: Colors.red.shade700)),
                      )),
                ],
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _loading ? null : _openFirstMissing,
                  icon: const Icon(Icons.settings),
                  label: const Text('הפעל הרשאות'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _parentApproval,
                  icon: const Icon(Icons.lock),
                  label: const Text('אישור הורה (PIN) – חלון תחזוקה 60 שניות'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(String key) {
    if (key == 'overlay') return 'הצגה מעל אפליקציות (Overlay)';
    if (key == 'usage') return 'גישה לשימוש (Usage Access)';
    return key;
  }
}
