import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/daily_mission.dart';

// TODO: Replace in-memory storage with Firestore implementation.
// TODO: Child submission flow will update childStatus only.
// TODO: Parent approval flow will grant XP only after approval.

/// Thrown when a child already has 3 missions assigned for the same day.
class DailyMissionLimitException implements Exception {
  const DailyMissionLimitException();

  @override
  String toString() =>
      'DailyMissionLimitException: maximum 3 missions per day per child.';
}

/// Shared daily missions repository (Firestore read + in-memory writes for later).
final dailyMissionsRepository = DailyMissionsRepository();

class DailyMissionsRepository {
  DailyMissionsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final List<DailyMission> _missions = [];
  bool _demoSeeded = false;

  CollectionReference<Map<String, dynamic>> _dailyMissionsCollection({
    required String parentId,
    required String childId,
  }) {
    return _firestore
        .collection('genet_parents')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('daily_missions');
  }

  String? _firestoreValueToIso(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  Map<String, dynamic> _firestoreDocToMap(
    String docId,
    Map<String, dynamic> data,
  ) {
    final map = Map<String, dynamic>.from(data);
    map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true
        ? map['id'] as String
        : docId;

    for (final key in [
      'assignedDate',
      'createdAt',
      'updatedAt',
      'submittedByChildAt',
      'approvedByParentAt',
      'rejectedByParentAt',
      'rewardGrantedAt',
    ]) {
      final iso = _firestoreValueToIso(map[key]);
      if (iso != null) {
        map[key] = iso;
      }
    }

    return map;
  }

  DailyMission _missionFromFirestoreDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    return DailyMission.fromMap(_firestoreDocToMap(docId, data));
  }

  List<DailyMission> _mapAndSortMissions(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final missions = snapshot.docs
        .map((doc) => _missionFromFirestoreDoc(doc.id, doc.data()))
        .toList();
    missions.sort((a, b) => b.assignedDate.compareTo(a.assignedDate));
    return missions;
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<int> _countMissionsForAssignedDay({
    required String parentId,
    required String childId,
    required DateTime assignedDate,
  }) async {
    final startOfDay = _startOfDay(assignedDate);
    final startOfNextDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _dailyMissionsCollection(
      parentId: parentId,
      childId: childId,
    )
        .where(
          'assignedDate',
          isGreaterThanOrEqualTo: startOfDay.toIso8601String(),
        )
        .where(
          'assignedDate',
          isLessThan: startOfNextDay.toIso8601String(),
        )
        .get();

    return snapshot.docs.length;
  }

  void _validateMissionForCreate(DailyMission mission) {
    if (mission.title.trim().isEmpty) {
      throw ArgumentError.value(mission.title, 'title', 'Title is required.');
    }
    if (mission.rewardXp < 1 || mission.rewardXp > 100) {
      throw ArgumentError.value(
        mission.rewardXp,
        'rewardXp',
        'rewardXp must be between 1 and 100.',
      );
    }
  }

  Future<DailyMission> createMission({
    required String parentId,
    required String childId,
    required DailyMission mission,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      throw ArgumentError('parentId and childId are required.');
    }

    _validateMissionForCreate(mission);

    try {
      final existingCount = await _countMissionsForAssignedDay(
        parentId: normalizedParentId,
        childId: normalizedChildId,
        assignedDate: mission.assignedDate,
      );
      if (existingCount >= 3) {
        throw const DailyMissionLimitException();
      }

      final missionId = mission.id.trim().isNotEmpty
          ? mission.id.trim()
          : 'mission_${DateTime.now().millisecondsSinceEpoch}';
      final missionToSave =
          mission.id == missionId ? mission : mission.copyWith(id: missionId);

      await _dailyMissionsCollection(
        parentId: normalizedParentId,
        childId: normalizedChildId,
      ).doc(missionId).set(missionToSave.toMap());

      debugPrint(
        '[GENET][DAILY_MISSIONS][CREATE] success parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$missionId',
      );
      return missionToSave;
    } on DailyMissionLimitException {
      debugPrint(
        '[GENET][DAILY_MISSIONS][CREATE] limit reached parentId=$normalizedParentId '
        'childId=$normalizedChildId assignedDate=${mission.assignedDate.toIso8601String()}',
      );
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '[GENET][DAILY_MISSIONS][CREATE] error parentId=$normalizedParentId '
        'childId=$normalizedChildId error=$error',
      );
      debugPrint('[GENET][DAILY_MISSIONS][CREATE] $stackTrace');
      rethrow;
    }
  }

  Stream<List<DailyMission>> watchDailyMissions({
    required String parentId,
    required String childId,
  }) {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      debugPrint(
        '[GENET][DAILY_MISSIONS] watch skipped: missing parentId or childId',
      );
      return Stream.value(const <DailyMission>[]);
    }

    debugPrint(
      '[GENET][DAILY_MISSIONS] watch start parentId=$normalizedParentId childId=$normalizedChildId',
    );

    return _dailyMissionsCollection(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    ).snapshots().map((snapshot) {
      try {
        return _mapAndSortMissions(snapshot);
      } catch (error, stackTrace) {
        debugPrint(
          '[GENET][DAILY_MISSIONS] map error parentId=$normalizedParentId '
          'childId=$normalizedChildId error=$error',
        );
        debugPrint('[GENET][DAILY_MISSIONS] $stackTrace');
        rethrow;
      }
    });
  }

  Future<List<DailyMission>> loadDailyMissionsOnce({
    required String parentId,
    required String childId,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    if (normalizedParentId.isEmpty || normalizedChildId.isEmpty) {
      debugPrint(
        '[GENET][DAILY_MISSIONS] loadOnce skipped: missing parentId or childId',
      );
      return const <DailyMission>[];
    }

    try {
      debugPrint(
        '[GENET][DAILY_MISSIONS] loadOnce start parentId=$normalizedParentId '
        'childId=$normalizedChildId',
      );
      final snapshot = await _dailyMissionsCollection(
        parentId: normalizedParentId,
        childId: normalizedChildId,
      ).get();
      final missions = _mapAndSortMissions(snapshot);
      debugPrint(
        '[GENET][DAILY_MISSIONS] loadOnce success count=${missions.length}',
      );
      return missions;
    } catch (error, stackTrace) {
      debugPrint(
        '[GENET][DAILY_MISSIONS] loadOnce error parentId=$normalizedParentId '
        'childId=$normalizedChildId error=$error',
      );
      debugPrint('[GENET][DAILY_MISSIONS] $stackTrace');
      rethrow;
    }
  }

  void _seedDemoMissionsIfNeeded() {
    if (_demoSeeded) return;
    _demoSeeded = true;

    final now = DateTime.now();
    _missions.addAll([
      DailyMission(
        id: 'demo_sleep',
        title: 'להתכונן לשינה בזמן',
        description: 'להניח את הטלפון בצד ולהתחיל להתארגן לשינה בזמן שנקבע.',
        category: DailyMissionCategory.sleep,
        rewardXp: 20,
        assignedDate: now,
        createdAt: now,
        updatedAt: now,
      ),
      DailyMission(
        id: 'demo_reading',
        title: 'לקרוא 10 דקות',
        description: 'קריאה קצרה לפני השינה.',
        category: DailyMissionCategory.studies,
        rewardXp: 15,
        assignedDate: now,
        createdAt: now,
        updatedAt: now,
      ),
      DailyMission(
        id: 'demo_room',
        title: 'לסדר את החדר',
        description: 'לסדר את השולחן, המיטה והרצפה.',
        category: DailyMissionCategory.home,
        rewardXp: 10,
        childStatus: ChildMissionStatus.submitted,
        parentApprovalStatus: ParentApprovalStatus.none,
        assignedDate: now,
        createdAt: now,
        updatedAt: now,
        submittedByChildAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _indexOfMission(String missionId) {
    return _missions.indexWhere((mission) => mission.id == missionId);
  }

  Future<List<DailyMission>> loadTodayMissions() async {
    _seedDemoMissionsIfNeeded();
    final today = DateTime.now();
    return List.unmodifiable(
      _missions.where((mission) => _isSameDay(mission.assignedDate, today)),
    );
  }

  Future<DailyMission?> getMission(String missionId) async {
    _seedDemoMissionsIfNeeded();
    final index = _indexOfMission(missionId);
    if (index == -1) return null;
    return _missions[index];
  }

  Future<List<DailyMission>> getAllMissions() async {
    _seedDemoMissionsIfNeeded();
    return List.unmodifiable(_missions);
  }

  /// Submits a daily mission for parent approval (Firestore update only).
  Future<void> submitMission({
    required String parentId,
    required String childId,
    required String missionId,
  }) async {
    // TODO: Parent approval will grant XP only after approval.
    // TODO: Prevent duplicate submissions from multiple devices.

    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    final normalizedMissionId = missionId.trim();
    if (normalizedParentId.isEmpty ||
        normalizedChildId.isEmpty ||
        normalizedMissionId.isEmpty) {
      throw ArgumentError('parentId, childId, and missionId are required.');
    }

    final docRef = _dailyMissionsCollection(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    ).doc(normalizedMissionId);

    try {
      final snapshot = await docRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint('[GENET][DAILY_MISSIONS][SUBMIT] mission not found');
        return;
      }

      final mission = _missionFromFirestoreDoc(
        normalizedMissionId,
        snapshot.data()!,
      );
      if (mission.childStatus != ChildMissionStatus.notStarted ||
          mission.parentApprovalStatus != ParentApprovalStatus.none) {
        debugPrint('[GENET][DAILY_MISSIONS][SUBMIT] ignored invalid state');
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      await docRef.update({
        'childStatus': ChildMissionStatus.submitted.name,
        'submittedByChildAt': nowIso,
        'updatedAt': nowIso,
      });

      debugPrint(
        '[GENET][DAILY_MISSIONS][SUBMIT] success parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GENET][DAILY_MISSIONS][SUBMIT] error parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId error=$error',
      );
      debugPrint('[GENET][DAILY_MISSIONS][SUBMIT] $stackTrace');
      rethrow;
    }
  }

  Future<void> approveMission({
    required String parentId,
    required String childId,
    required String missionId,
  }) async {
    // TODO: Connect XP service here and grant reward idempotently after parent approval.
    // TODO: Use transaction/batch when XP reward writing is implemented.

    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    final normalizedMissionId = missionId.trim();
    if (normalizedParentId.isEmpty ||
        normalizedChildId.isEmpty ||
        normalizedMissionId.isEmpty) {
      throw ArgumentError('parentId, childId, and missionId are required.');
    }

    final docRef = _dailyMissionsCollection(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    ).doc(normalizedMissionId);

    try {
      final snapshot = await docRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint('[GENET][DAILY_MISSIONS][APPROVE] mission not found');
        return;
      }

      final mission = _missionFromFirestoreDoc(
        normalizedMissionId,
        snapshot.data()!,
      );
      if (mission.childStatus != ChildMissionStatus.submitted ||
          mission.parentApprovalStatus != ParentApprovalStatus.none ||
          mission.rewardGranted) {
        debugPrint('[GENET][DAILY_MISSIONS][APPROVE] ignored invalid state');
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      await docRef.update({
        'parentApprovalStatus': ParentApprovalStatus.approved.name,
        'approvedByParentAt': nowIso,
        'updatedAt': nowIso,
      });

      debugPrint(
        '[GENET][DAILY_MISSIONS][APPROVE] success parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GENET][DAILY_MISSIONS][APPROVE] error parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId error=$error',
      );
      debugPrint('[GENET][DAILY_MISSIONS][APPROVE] $stackTrace');
      rethrow;
    }
  }

  Future<void> rejectMission({
    required String parentId,
    required String childId,
    required String missionId,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedChildId = childId.trim();
    final normalizedMissionId = missionId.trim();
    if (normalizedParentId.isEmpty ||
        normalizedChildId.isEmpty ||
        normalizedMissionId.isEmpty) {
      throw ArgumentError('parentId, childId, and missionId are required.');
    }

    final docRef = _dailyMissionsCollection(
      parentId: normalizedParentId,
      childId: normalizedChildId,
    ).doc(normalizedMissionId);

    try {
      final snapshot = await docRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint('[GENET][DAILY_MISSIONS][REJECT] mission not found');
        return;
      }

      final mission = _missionFromFirestoreDoc(
        normalizedMissionId,
        snapshot.data()!,
      );
      if (mission.childStatus != ChildMissionStatus.submitted ||
          mission.parentApprovalStatus != ParentApprovalStatus.none) {
        debugPrint('[GENET][DAILY_MISSIONS][REJECT] ignored invalid state');
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      await docRef.update({
        'parentApprovalStatus': ParentApprovalStatus.rejected.name,
        'rejectedByParentAt': nowIso,
        'updatedAt': nowIso,
      });

      debugPrint(
        '[GENET][DAILY_MISSIONS][REJECT] success parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GENET][DAILY_MISSIONS][REJECT] error parentId=$normalizedParentId '
        'childId=$normalizedChildId missionId=$normalizedMissionId error=$error',
      );
      debugPrint('[GENET][DAILY_MISSIONS][REJECT] $stackTrace');
      rethrow;
    }
  }

  Future<void> deleteMission(String missionId) async {
    _missions.removeWhere((mission) => mission.id == missionId);
  }
}

/// Picks the newest mission assigned for [day] (defaults to today).
DailyMission? pickNewestMissionForDay(
  List<DailyMission> missions, {
  DateTime? day,
}) {
  final targetDay = day ?? DateTime.now();
  final dayMissions = missions.where(
    (mission) {
      final assignedDate = mission.assignedDate;
      return assignedDate.year == targetDay.year &&
          assignedDate.month == targetDay.month &&
          assignedDate.day == targetDay.day;
    },
  ).toList();
  if (dayMissions.isEmpty) return null;
  dayMissions.sort((a, b) => b.assignedDate.compareTo(a.assignedDate));
  return dayMissions.first;
}
