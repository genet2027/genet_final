import '../enums/behavior_event_type.dart';

enum BehaviorSyncStatus { pending, synced }

String behaviorSyncStatusToStorageValue(BehaviorSyncStatus status) {
  switch (status) {
    case BehaviorSyncStatus.pending:
      return 'pending';
    case BehaviorSyncStatus.synced:
      return 'synced';
  }
}

BehaviorSyncStatus behaviorSyncStatusFromStorageValue(String value) {
  switch (value) {
    case 'synced':
      return BehaviorSyncStatus.synced;
    case 'pending':
    default:
      return BehaviorSyncStatus.pending;
  }
}

class BehaviorEvent {
  const BehaviorEvent({
    required this.id,
    required this.childId,
    required this.eventType,
    required this.timestamp,
    required this.metadata,
    required this.syncStatus,
    this.appPackage,
    this.appName,
  });

  final String id;
  final String childId;
  final BehaviorEventType eventType;
  final String? appPackage;
  final String? appName;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final BehaviorSyncStatus syncStatus;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'childId': childId,
      'eventType': behaviorEventTypeToStorageValue(eventType),
      'appPackage': appPackage,
      'appName': appName,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'syncStatus': behaviorSyncStatusToStorageValue(syncStatus),
    };
  }

  factory BehaviorEvent.fromMap(Map<String, dynamic> map) {
    return BehaviorEvent(
      id: map['id'] as String? ?? '',
      childId: map['childId'] as String? ?? '',
      eventType: behaviorEventTypeFromStorageValue(
        map['eventType'] as String? ?? '',
      ),
      appPackage: map['appPackage'] as String?,
      appName: map['appName'] as String?,
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      metadata:
          (map['metadata'] as Map?)
              ?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
          const <String, dynamic>{},
      syncStatus: behaviorSyncStatusFromStorageValue(
        map['syncStatus'] as String? ?? '',
      ),
    );
  }

  BehaviorEvent copyWith({
    String? id,
    String? childId,
    BehaviorEventType? eventType,
    String? appPackage,
    bool clearAppPackage = false,
    String? appName,
    bool clearAppName = false,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    BehaviorSyncStatus? syncStatus,
  }) {
    return BehaviorEvent(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      eventType: eventType ?? this.eventType,
      appPackage: clearAppPackage ? null : (appPackage ?? this.appPackage),
      appName: clearAppName ? null : (appName ?? this.appName),
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
