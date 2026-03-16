import 'package:flutter/material.dart';

import '../core/config/genet_config.dart';
import '../theme/app_theme.dart';

/// מסך שחזור הרשאות: מוצג כאשר הילד ניסה לפתוח אפליקציה חסומה וחסרות הרשאות קריטיות.
/// ניתן לצאת בלי לאשר (לא חוסם את כל המכשיר); בפתיחה הבאה של אפליקציה חסומה יוצג שוב.
class PermissionRecoveryScreen extends StatefulWidget {
  const PermissionRecoveryScreen({super.key});

  @override
  State<PermissionRecoveryScreen> createState() => _PermissionRecoveryScreenState();
}

class _PermissionRecoveryScreenState extends State<PermissionRecoveryScreen> with WidgetsBindingObserver {
  List<String> _missing = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final list = await GenetConfig.getMissingPermissions();
    if (mounted) {
      setState(() {
        _missing = list;
        _loading = false;
      });
      if (list.isEmpty) Navigator.of(context).pop();
    }
  }

  Future<void> _open(String key) async {
    if (key == 'accessibility') {
      await GenetConfig.openAccessibilitySettings();
    } else if (key == 'overlay') {
      await GenetConfig.openOverlaySettings();
    } else if (key == 'usage') {
      await GenetConfig.openUsageAccessSettings();
    }
  }

  static String _label(String key) {
    if (key == 'accessibility') return 'נגישות (Accessibility)';
    if (key == 'overlay') return 'הצגה מעל אפליקציות (Overlay)';
    if (key == 'usage') return 'גישה לשימוש (Usage Access)';
    return key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.build_circle_outlined, size: 64, color: Colors.orange.shade700),
              const SizedBox(height: 16),
              const Text(
                'שחזור הרשאות',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'ניסית לפתוח אפליקציה חסומה. כדי שהחסימה תעבוד, נדרשות ההרשאות הבאות.',
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
              if (!_loading && _missing.isNotEmpty)
                ..._missing.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton.icon(
                        onPressed: () => _open(e),
                        icon: const Icon(Icons.settings),
                        label: Text('הגדרות: ${_label(e)}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    )),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('אחר כך'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
