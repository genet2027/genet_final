import 'package:flutter/foundation.dart';

import '../models/night_mode_config.dart';
import '../repositories/night_mode_repository.dart';

/// Service other screens can query: night window, allowed requests, remaining.
/// Per-night counter resets automatically when a new night window starts (date-based).
class NightModeService extends ChangeNotifier {
  NightModeService({NightModeRepository? repo})
      : _repo = repo ?? NightModeRepository();

  final NightModeRepository _repo;
  NightModeConfig _config = const NightModeConfig();
  String _lastNightDate = '';
  int _usedRequests = 0;
  bool _loaded = false;

  NightModeConfig get config => _config;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _config = await _repo.getConfig();
    final counter = await _repo.getNightCounter();
    _lastNightDate = counter.lastNightDate;
    _usedRequests = counter.usedRequests;
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveConfig(NightModeConfig config) async {
    _config = config;
    await _repo.saveConfig(config);
    notifyListeners();
  }

  /// Max requests allowed in one night based on behavior level.
  int getAllowedNightRequests() {
    switch (_config.behaviorLevel) {
      case NightBehaviorLevel.disruptive:
        return 0;
      case NightBehaviorLevel.good:
        return 1;
      case NightBehaviorLevel.excellent:
        return _config.excellentMaxRequests;
    }
  }

  /// Whether current time is inside the night window (start..end, crossing midnight).
  bool isNightTimeNow() {
    if (!_config.enabled) return false;
    return isWithinWindow(
      startTime: _config.startTime,
      endTime: _config.endTime,
      currentTime: DateTime.now(),
    );
  }

  /// Shared source of truth for sleep-lock/night window math across the app.
  static bool isWithinWindow({
    required String startTime,
    required String endTime,
    required DateTime currentTime,
  }) {
    final start = _parseTimeParts(startTime);
    final end = _parseTimeParts(endTime);
    final nowMinutes = currentTime.hour * 60 + currentTime.minute;
    final startMinutes = start.$1 * 60 + start.$2;
    final endMinutes = end.$1 * 60 + end.$2;
    if (startMinutes > endMinutes) {
      // e.g. 22:00 - 07:00
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  static (int, int) _parseTimeParts(String s) {
    final parts = s.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h, m);
  }

  /// Current night date: the calendar date when this night started.
  /// 22:00–24:00 → today; 00:00–07:00 → yesterday.
  String _currentNightDate() {
    final now = DateTime.now();
    final start = _parseTimeParts(_config.startTime);
    final end = _parseTimeParts(_config.endTime);
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = start.$1 * 60 + start.$2;
    final endMinutes = end.$1 * 60 + end.$2;
    if (startMinutes > endMinutes) {
      if (nowMinutes >= startMinutes) {
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      } else {
        final yesterday = now.subtract(const Duration(days: 1));
        return '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      }
    }
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Remaining requests for the current night. Resets counter if we're in a new night.
  int remainingNightRequests() {
    if (!_config.enabled) return getAllowedNightRequests();
    final allowed = getAllowedNightRequests();
    if (allowed == 0) return 0;
    final nightDate = _currentNightDate();
    if (nightDate != _lastNightDate) {
      _lastNightDate = nightDate;
      _usedRequests = 0;
      _repo.setNightCounter(_lastNightDate, _usedRequests);
    }
    final remaining = allowed - _usedRequests;
    return remaining < 0 ? 0 : remaining;
  }

  /// Call when the child uses one request at night. Returns false if none left.
  Future<bool> consumeOneNightRequest() async {
    if (!_config.enabled) return true;
    final nightDate = _currentNightDate();
    if (nightDate != _lastNightDate) {
      _lastNightDate = nightDate;
      _usedRequests = 0;
    }
    final allowed = getAllowedNightRequests();
    if (_usedRequests >= allowed) return false;
    _usedRequests++;
    await _repo.setNightCounter(_lastNightDate, _usedRequests);
    notifyListeners();
    return true;
  }

  /// Force refresh from repo (e.g. after backup restore).
  Future<void> refresh() async {
    await load();
  }
}
