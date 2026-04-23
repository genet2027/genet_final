import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/night_mode_config.dart';
import '../theme/app_theme.dart';
import '../services/night_mode_service.dart';

class NightModeSettingsScreen extends StatefulWidget {
  const NightModeSettingsScreen({super.key});

  @override
  State<NightModeSettingsScreen> createState() =>
      _NightModeSettingsScreenState();
}

class _NightModeSettingsScreenState extends State<NightModeSettingsScreen> {
  bool _enabled = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 0);
  NightBehaviorLevel _behaviorLevel = NightBehaviorLevel.good;
  int _excellentMax = 3;
  bool _initialized = false;

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _applyFromConfig(NightModeConfig config) {
    _enabled = config.enabled;
    final startParts = config.startTime.split(':');
    _startTime = TimeOfDay(
      hour: startParts.isNotEmpty ? int.tryParse(startParts[0]) ?? 22 : 22,
      minute: startParts.length > 1 ? int.tryParse(startParts[1]) ?? 0 : 0,
    );
    final endParts = config.endTime.split(':');
    _endTime = TimeOfDay(
      hour: endParts.isNotEmpty ? int.tryParse(endParts[0]) ?? 7 : 7,
      minute: endParts.length > 1 ? int.tryParse(endParts[1]) ?? 0 : 0,
    );
    _behaviorLevel = config.behaviorLevel;
    _excellentMax = config.excellentMaxRequests;
  }

  Future<void> _pickStartTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _save(BuildContext context) async {
    final service = context.read<NightModeService>();
    final config = NightModeConfig(
      enabled: _enabled,
      startTime: _formatTime(_startTime),
      endTime: _formatTime(_endTime),
      behaviorLevel: _behaviorLevel,
      excellentMaxRequests: _excellentMax,
    );
    await service.saveConfig(config);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הגדרות מצב הלילה נשמרו')),
    );
  }

  String _behaviorLabel(NightBehaviorLevel level) {
    switch (level) {
      case NightBehaviorLevel.disruptive:
        return 'מפריע';
      case NightBehaviorLevel.good:
        return 'טוב';
      case NightBehaviorLevel.excellent:
        return 'מצוין';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('מצב לילה (חופשת שינה)')),
        body: Consumer<NightModeService>(
          builder: (context, service, _) {
            if (service.isLoaded && !_initialized) {
              _initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _applyFromConfig(service.config));
              });
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.08),
                  child: SwitchListTile(
                    title: const Text('הפעל מצב לילה'),
                    subtitle: Text(
                      _enabled
                          ? '${_formatTime(_startTime)} – ${_formatTime(_endTime)}'
                          : 'כבוי',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    activeThumbColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('שעת התחלה',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppTheme.darkBlue)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_formatTime(_startTime),
                      style: const TextStyle(fontSize: 24)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _pickStartTime(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: AppTheme.lightBlue.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 20),
                const Text('שעת סיום',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppTheme.darkBlue)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_formatTime(_endTime),
                      style: const TextStyle(fontSize: 24)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _pickEndTime(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: AppTheme.lightBlue.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 28),
                const Text('רמת התנהגות',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppTheme.darkBlue)),
                const SizedBox(height: 8),
                RadioGroup<NightBehaviorLevel>(
                  groupValue: _behaviorLevel,
                  onChanged: (NightBehaviorLevel? v) {
                    if (v != null) setState(() => _behaviorLevel = v);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final level in NightBehaviorLevel.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            elevation: 2,
                            shadowColor:
                                Colors.black.withValues(alpha: 0.08),
                            child: RadioListTile<NightBehaviorLevel>(
                              value: level,
                              title: Text(_behaviorLabel(level)),
                              subtitle: Text(
                                switch (level) {
                                  NightBehaviorLevel.disruptive =>
                                    '0 בקשות בלילה',
                                  NightBehaviorLevel.good => 'בקשה אחת בלילה',
                                  NightBehaviorLevel.excellent =>
                                    'עד $_excellentMax בקשות (ניתן להגדרה)',
                                },
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              activeColor: AppTheme.primaryBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_behaviorLevel == NightBehaviorLevel.excellent) ...[
                  const SizedBox(height: 16),
                  const Text('מספר בקשות מקסימלי (מצוין)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.darkBlue)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _excellentMax > 1
                            ? () => setState(() => _excellentMax--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      const SizedBox(width: 24),
                      Text('$_excellentMax',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 24),
                      IconButton.filled(
                        onPressed: _excellentMax < 10
                            ? () => setState(() => _excellentMax++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => _save(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('שמור'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
