import 'package:shared_preferences/shared_preferences.dart';

import '../models/night_mode_config.dart';

/// Keys shared with sleep_lock_screen for start/end times.
const String kNightEnabledKey = 'genet_sleep_lock_enabled';
const String kNightStartKey = 'genet_sleep_lock_start';
const String kNightEndKey = 'genet_sleep_lock_end';
const String kNightBehaviorKey = 'genet_night_behavior';
const String kNightExcellentMaxKey = 'genet_night_excellent_max';
const String kNightLastDateKey = 'genet_night_last_date';
const String kNightUsedRequestsKey = 'genet_night_used_requests';

class NightModeRepository {
  Future<NightModeConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(kNightEnabledKey) ?? false;
    final start = prefs.getString(kNightStartKey) ?? '22:00';
    final end = prefs.getString(kNightEndKey) ?? '07:00';
    final behaviorStr = prefs.getString(kNightBehaviorKey);
    NightBehaviorLevel level = NightBehaviorLevel.good;
    if (behaviorStr == 'disruptive') level = NightBehaviorLevel.disruptive;
    if (behaviorStr == 'excellent') level = NightBehaviorLevel.excellent;
    final excellentMax = prefs.getInt(kNightExcellentMaxKey) ?? 3;
    return NightModeConfig(
      enabled: enabled,
      startTime: start,
      endTime: end,
      behaviorLevel: level,
      excellentMaxRequests: excellentMax,
    );
  }

  Future<void> saveConfig(NightModeConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kNightEnabledKey, config.enabled);
    await prefs.setString(kNightStartKey, config.startTime);
    await prefs.setString(kNightEndKey, config.endTime);
    await prefs.setString(kNightBehaviorKey, config.behaviorLevel.name);
    await prefs.setInt(kNightExcellentMaxKey, config.excellentMaxRequests);
  }

  /// Returns [lastNightDate, usedRequests]. Night date is the calendar date of the day when the night started (e.g. 22:00 Feb 18 → "2025-02-18").
  Future<({String lastNightDate, int usedRequests})> getNightCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(kNightLastDateKey) ?? '';
    final used = prefs.getInt(kNightUsedRequestsKey) ?? 0;
    return (lastNightDate: last, usedRequests: used);
  }

  /// Set counter for the given night date (used when resetting for a new night).
  Future<void> setNightCounter(String nightDate, int usedRequests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kNightLastDateKey, nightDate);
    await prefs.setInt(kNightUsedRequestsKey, usedRequests);
  }

  /// For backup export: current config as JSON-friendly map.
  Future<Map<String, dynamic>> getConfigForBackup() async {
    final config = await getConfig();
    return config.toJson();
  }

  /// Restore from backup JSON (only night_mode section).
  Future<void> restoreFromBackup(Map<String, dynamic> json) async {
    final config = NightModeConfig.fromJson(json);
    await saveConfig(config);
  }
}
