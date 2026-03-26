import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/behavior_event.dart';
import 'behavior_local_store.dart';

class BehaviorSyncService {
  BehaviorSyncService({
    BehaviorLocalStore? localStore,
    FirebaseFirestore? firestore,
  }) : _localStore = localStore ?? BehaviorLocalStore.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final BehaviorLocalStore _localStore;
  final FirebaseFirestore _firestore;

  Future<void> syncPendingEvents() async {
    try {
      await _localStore.init();
      final pendingEvents = await _localStore.getPendingEvents();
      for (final event in pendingEvents) {
        await _syncSingleEvent(event);
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[BehaviorSync] syncPendingEvents failed: $error $stackTrace',
      );
    }
  }

  Future<void> syncPendingEventsForChild(String childId) async {
    try {
      await _localStore.init();
      final pendingEvents = await _localStore.getPendingEvents();
      final childEvents = pendingEvents
          .where((event) => event.childId == childId)
          .toList();
      for (final event in childEvents) {
        await _syncSingleEvent(event);
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[BehaviorSync] syncPendingEventsForChild failed: $error $stackTrace',
      );
    }
  }

  Future<void> _syncSingleEvent(BehaviorEvent event) async {
    try {
      await _firestore
          .collection('behavior_logs')
          .doc(event.childId)
          .collection('events')
          .doc(event.id)
          .set(event.toMap(), SetOptions(merge: true));
      await _localStore.markAsSynced(event.id);
    } catch (error, stackTrace) {
      debugPrint(
        '[BehaviorSync] event sync failed id=${event.id}: $error $stackTrace',
      );
    }
  }
}
