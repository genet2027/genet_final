import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

const String _kSleepLockEnabledKey = 'genet_sleep_lock_enabled';
const String _kSleepLockStartKey = 'genet_sleep_lock_start';
const String _kSleepLockEndKey = 'genet_sleep_lock_end';

/// מסך הגדרת Sleep Lock Mode - בחירת טווח שעות
class SleepLockScreen extends StatefulWidget {
  const SleepLockScreen({super.key});

  @override
  State<SleepLockScreen> createState() => _SleepLockScreenState();
}

class _SleepLockScreenState extends State<SleepLockScreen> {
  bool _enabled = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled = prefs.getBool(_kSleepLockEnabledKey) ?? false;
      final startStr = prefs.getString(_kSleepLockStartKey);
      final endStr = prefs.getString(_kSleepLockEndKey);
      if (startStr != null) {
        final parts = startStr.split(':');
        _startTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
      if (endStr != null) {
        final parts = endStr.split(':');
        _endTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSleepLockEnabledKey, _enabled);
    await prefs.setString(
      _kSleepLockStartKey,
      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
    );
    await prefs.setString(
      _kSleepLockEndKey,
      '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
    );
  }

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _saveSettings();
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _saveSettings();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep Lock Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('הפעל Sleep Lock'),
                subtitle: Text(
                  _enabled ? 'פעיל - ${_formatTime(_startTime)} עד ${_formatTime(_endTime)}' : 'כבוי',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                value: _enabled,
                onChanged: (v) {
                  setState(() {
                    _enabled = v;
                    _saveSettings();
                  });
                },
                activeColor: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'שעת התחלה',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_formatTime(_startTime), style: const TextStyle(fontSize: 24)),
              trailing: const Icon(Icons.access_time),
              onTap: _pickStartTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: AppTheme.lightBlue.withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            const Text(
              'שעת סיום',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppTheme.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_formatTime(_endTime), style: const TextStyle(fontSize: 24)),
              trailing: const Icon(Icons.access_time),
              onTap: _pickEndTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: AppTheme.lightBlue.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'בטווח השעות הנבחר, המכשיר יהיה נעול (דוגמה: 22:00 - 07:00)',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
