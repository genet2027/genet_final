import 'dart:math';

import 'package:flutter/foundation.dart';

import '../enums/behavior_event_type.dart';
import '../models/behavior_event.dart';
import 'behavior_local_store.dart';
import 'behavior_sync_service.dart';

class BehaviorLogger {
  BehaviorLogger({
    BehaviorLocalStore? localStore,
    BehaviorSyncService? syncService,
    Duration? cooldownWindow,
  }) : _localStore = localStore ?? BehaviorLocalStore.instance,
       _syncService = syncService ?? BehaviorSyncService(),
       _cooldownWindow = cooldownWindow ?? const Duration(seconds: 30);

  final BehaviorLocalStore _localStore;
  final BehaviorSyncService _syncService;
  final Duration _cooldownWindow;
  final Random _random = Random();

  Future<void> logEvent({
    required String childId,
    required BehaviorEventType eventType,
    String? appPackage,
    String? appName,
    Map<String, dynamic>? metadata,
  }) async {
    if (childId.isEmpty) return;
    try {
      await _localStore.init();
      final now = DateTime.now();
      final isDuplicate = await _isDuplicateRecentlyLogged(
        childId: childId,
        eventType: eventType,
        appPackage: appPackage,
        now: now,
      );
      if (isDuplicate) {
        debugPrint(
          '[BehaviorLogger] duplicate skipped childId=$childId eventType=$eventType appPackage=${appPackage ?? ''}',
        );
        return;
      }

      final event = BehaviorEvent(
        id: _generateId(childId, now),
        childId: childId,
        eventType: eventType,
        appPackage: appPackage,
        appName: appName,
        timestamp: now,
        metadata: metadata ?? const <String, dynamic>{},
        syncStatus: BehaviorSyncStatus.pending,
      );
      await _localStore.saveEvent(event);
      debugPrint(
        '[BehaviorLogger] saved event childId=$childId eventType=$eventType id=${event.id}',
      );
      _syncService.syncPendingEventsForChild(childId);
    } catch (error, stackTrace) {
      debugPrint('[BehaviorLogger] logEvent failed: $error $stackTrace');
    }
  }

  Future<bool> _isDuplicateRecentlyLogged({
    required String childId,
    required BehaviorEventType eventType,
    required String? appPackage,
    required DateTime now,
  }) async {
    final recentEvents = await _localStore.getEventsForChildInRange(
      childId,
      now.subtract(_cooldownWindow),
      now,
    );
    return recentEvents.any(
      (event) =>
          event.eventType == eventType && event.appPackage == appPackage,
    );
  }

  String _generateId(String childId, DateTime timestamp) {
    final sanitizedChildId = childId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final randomPart = _random.nextInt(1 << 32).toRadixString(16);
    return 'behavior_${sanitizedChildId}_${timestamp.microsecondsSinceEpoch}_$randomPart';
  }
}
