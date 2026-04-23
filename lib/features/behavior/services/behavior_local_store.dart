import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/behavior_event.dart';

class BehaviorLocalStore {
  BehaviorLocalStore._();

  static final BehaviorLocalStore instance = BehaviorLocalStore._();
  static const String _storageKey = 'genet_behavior_events';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveEvent(BehaviorEvent event) async {
    await init();
    final events = await _readAllEvents();
    final existingIndex = events.indexWhere((item) => item.id == event.id);
    if (existingIndex >= 0) {
      events[existingIndex] = event;
    } else {
      events.add(event);
    }
    await _writeAllEvents(events);
  }

  Future<List<BehaviorEvent>> getPendingEvents() async {
    final events = await _readAllEvents();
    return events
        .where((event) => event.syncStatus == BehaviorSyncStatus.pending)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> markAsSynced(String eventId) async {
    final events = await _readAllEvents();
    final updated =
        events
            .map(
              (event) => event.id == eventId
                  ? event.copyWith(syncStatus: BehaviorSyncStatus.synced)
                  : event,
            )
            .toList();
    await _writeAllEvents(updated);
  }

  Future<List<BehaviorEvent>> getEventsForChild(String childId) async {
    final events = await _readAllEvents();
    return events
        .where((event) => event.childId == childId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<BehaviorEvent>> getEventsForChildInRange(
    String childId,
    DateTime start,
    DateTime end,
  ) async {
    final events = await getEventsForChild(childId);
    return events
        .where(
          (event) =>
              !event.timestamp.isBefore(start) &&
              !event.timestamp.isAfter(end),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<BehaviorEvent>> _readAllEvents() async {
    await init();
    final raw = _prefs!.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <BehaviorEvent>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => BehaviorEvent.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <BehaviorEvent>[];
    }
  }

  Future<void> _writeAllEvents(List<BehaviorEvent> events) async {
    await init();
    final encoded = jsonEncode(events.map((event) => event.toMap()).toList());
    await _prefs!.setString(_storageKey, encoded);
  }
}
