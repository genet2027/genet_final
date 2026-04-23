import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/children_repository.dart';
import '../repositories/parent_child_sync_repository.dart';
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
    final selectedId = await getSelectedChildId();
    if (selectedId != null && selectedId.isNotEmpty) {
      final remote = await getSleepLockFromFirebase(selectedId);
      if (remote != null && mounted) {
        developer.log(
          'SLEEP_LOCK parent load merged from Firebase childId=$selectedId isActive=${remote['isActive']} start=${remote['startTime']} end=${remote['endTime']}',
          name: 'Sync',
        );
        final rs = remote['startTime'] as String?;
        final re = remote['endTime'] as String?;
        if (remote['isActive'] is bool) {
          _enabled = remote['isActive'] as bool;
        }
        if (rs != null && rs.contains(':')) {
          final p = rs.split(':');
          _startTime = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
        }
        if (re != null && re.contains(':')) {
          final p = re.split(':');
          _endTime = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
        }
        await prefs.setBool(_kSleepLockEnabledKey, _enabled);
        await prefs.setString(_kSleepLockStartKey, _formatTime(_startTime));
        await prefs.setString(_kSleepLockEndKey, _formatTime(_endTime));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSleepLockEnabledKey, _enabled);
    final startS =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endS =
        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';
    await prefs.setString(_kSleepLockStartKey, startS);
    await prefs.setString(_kSleepLockEndKey, endS);
    final selectedId = await getSelectedChildId();
    if (selectedId != null && selectedId.isNotEmpty) {
      developer.log(
        'SLEEP_LOCK parent write selectedChildId=$selectedId path=child_settings/$selectedId/sleep_lock/settings',
        name: 'Sync',
      );
      await writeSleepLockToFirebase(
        selectedId,
        isActive: _enabled,
        startTime: startS,
        endTime: endS,
      );
    } else {
      developer.log('SLEEP_LOCK parent write skipped: no selectedChildId', name: 'Sync');
    }
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
                activeThumbColor: AppTheme.primaryBlue,
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
              tileColor: AppTheme.lightBlue.withValues(alpha: 0.5),
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
              tileColor: AppTheme.lightBlue.withValues(alpha: 0.5),
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
