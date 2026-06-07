import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../repositories/children_repository.dart';

const String kGenetChildrenCollection = 'genet_children';
const String kQuestionnaireField = 'questionnaire';
const String kQuestionnaireCompletedField = 'questionnaireCompleted';

/// Canonical auth-bound child id for questionnaire reads/writes (`c_<firebaseUid>`).
Future<String?> resolveAuthBoundChildQuestionnaireId() async {
  return resolveAuthBoundChildIdFromAuth();
}

/// Reads `questionnaire` map from `genet_children/{childId}`.
Future<Map<String, dynamic>?> loadChildQuestionnaire(String childId) async {
  for (final id in genetChildDocIdsForQuestionnaire(childId)) {
    final snap = await FirebaseFirestore.instance
        .collection(kGenetChildrenCollection)
        .doc(id)
        .get();

    if (!snap.exists || snap.data() == null) continue;

    final raw = snap.data()![kQuestionnaireField];
    if (raw is! Map) continue;

    final map = Map<String, dynamic>.from(raw);
    if (map.isNotEmpty) return map;
  }
  return null;
}

/// Returns whether `questionnaireCompleted` is true on `genet_children/{childId}`.
Future<bool> isChildQuestionnaireCompleted(String childId) async {
  for (final id in genetChildDocIdsForQuestionnaire(childId)) {
    final snap = await FirebaseFirestore.instance
        .collection(kGenetChildrenCollection)
        .doc(id)
        .get();

    if (!snap.exists || snap.data() == null) continue;
    if (_questionnaireCompletedInDoc(snap.data())) return true;
  }
  return false;
}

/// Dashboard read: primary [childId], optional legacy uid fallback for `c_<uid>` ids.
List<String> genetChildDocIdsForQuestionnaire(String childId) {
  final id = childId.trim();
  if (id.isEmpty) return const [];
  final ids = <String>[id];
  if (id.startsWith('c_') && id.length > 2) {
    final authUid = id.substring(2);
    if (!ids.contains(authUid)) ids.add(authUid);
  } else if (!id.startsWith('c_')) {
    final prefixed = 'c_$id';
    if (!ids.contains(prefixed)) ids.add(prefixed);
  }
  return ids;
}

bool _questionnaireCompletedInDoc(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data[kQuestionnaireCompletedField] == true) return true;
  final questionnaire = _readQuestionnaireMap(data);
  if (questionnaire == null || questionnaire.isEmpty) return false;
  // Legacy docs may have answers without the completed flag.
  return questionnaire.values.any((value) {
    if (value == null) return false;
    return value.toString().trim().isNotEmpty;
  });
}

Map<String, dynamic>? _readQuestionnaireMap(Map<String, dynamic>? data) {
  if (data == null) return null;
  final raw = data[kQuestionnaireField];
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

GenetChildQuestionnaireViewState _resolveQuestionnaireViewState(
  List<String> docIds,
  Map<String, Map<String, dynamic>?> docsById,
) {
  GenetChildQuestionnaireViewState? resolved;
  String? reason;

  for (final id in docIds) {
    final data = docsById[id];
    if (_questionnaireCompletedInDoc(data)) {
      resolved = GenetChildQuestionnaireViewState(
        resolvedDocId: id,
        questionnaireCompleted: true,
        questionnaire: _readQuestionnaireMap(data),
      );
      reason = data?[kQuestionnaireCompletedField] == true
          ? 'questionnaireCompleted_true_on_$id'
          : 'legacy_questionnaire_has_values_on_$id';
      break;
    }
  }

  resolved ??= GenetChildQuestionnaireViewState(
    resolvedDocId: docIds.first,
    questionnaireCompleted: false,
    questionnaire: _readQuestionnaireMap(docsById[docIds.first]),
  );
  reason ??= _questionnaireDebugIncompleteReason(docsById, docIds);

  _logQuestionnaireDebugCardDecision(
    docIds: docIds,
    docsById: docsById,
    state: resolved,
    reason: reason,
  );

  return resolved;
}

String _questionnaireDebugIncompleteReason(
  Map<String, Map<String, dynamic>?> docsById,
  List<String> docIds,
) {
  for (final id in docIds) {
    final data = docsById[id];
    if (data == null) continue;
    if (data[kQuestionnaireCompletedField] == false) {
      return 'questionnaireCompleted_false_on_$id';
    }
    final questionnaire = _readQuestionnaireMap(data);
    if (questionnaire == null) {
      return 'questionnaire_map_missing_on_$id';
    }
    if (questionnaire.isEmpty) {
      return 'questionnaire_map_empty_on_$id';
    }
  }
  if (docIds.every((id) => docsById[id] == null)) {
    return 'all_docs_missing_or_null';
  }
  return 'no_completed_questionnaire_on_any_doc';
}

void _logQuestionnaireDebugCardDecision({
  required List<String> docIds,
  required Map<String, Map<String, dynamic>?> docsById,
  required GenetChildQuestionnaireViewState state,
  required String reason,
}) {
  for (final id in docIds) {
    final data = docsById[id];
    final questionnaire = _readQuestionnaireMap(data);
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD_DECISION] docId=$id '
      'questionnaireCompletedRaw=${data?[kQuestionnaireCompletedField]}',
    );
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD_DECISION] docId=$id '
      'questionnaireMapExists=${questionnaire != null}',
    );
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD_DECISION] docId=$id '
      'questionnaireMapKeys=${questionnaire?.keys.toList()}',
    );
  }
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD_DECISION] finalIsCompleted=${state.questionnaireCompleted}',
  );
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD_DECISION] reason=$reason',
  );
}

void _logQuestionnaireDebugCardReads({
  required String receivedChildId,
  required String primaryId,
  required DocumentSnapshot<Map<String, dynamic>> primarySnap,
  String? fallbackId,
  DocumentSnapshot<Map<String, dynamic>>? fallbackSnap,
}) {
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD] received childId=$receivedChildId',
  );
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD] primaryPath=genet_children/$primaryId',
  );
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD] primaryExists=${primarySnap.exists}',
  );
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][CARD] primaryData=${primarySnap.data()}',
  );
  if (fallbackId != null && fallbackSnap != null) {
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD] fallbackPath=genet_children/$fallbackId',
    );
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD] fallbackExists=${fallbackSnap.exists}',
    );
    debugPrint(
      '[GENET][QUESTIONNAIRE_DEBUG][CARD] fallbackData=${fallbackSnap.data()}',
    );
  }
}

Stream<DocumentSnapshot<Map<String, dynamic>>> _watchGenetChildDoc(String docId) {
  return FirebaseFirestore.instance
      .collection(kGenetChildrenCollection)
      .doc(docId)
      .snapshots();
}

/// Live questionnaire state for parent dashboard card.
class GenetChildQuestionnaireViewState {
  const GenetChildQuestionnaireViewState({
    required this.resolvedDocId,
    required this.questionnaireCompleted,
    required this.questionnaire,
  });

  final String resolvedDocId;
  final bool questionnaireCompleted;
  final Map<String, dynamic>? questionnaire;
}

/// Watches `genet_children/{childId}` for questionnaire data (read-only).
Stream<GenetChildQuestionnaireViewState> watchGenetChildQuestionnaireForDashboard(
  String childId,
) {
  final docIds = genetChildDocIdsForQuestionnaire(childId);
  if (docIds.isEmpty) {
    return Stream.error(StateError('childId is empty'));
  }

  if (docIds.length == 1) {
    final docId = docIds.first;
    return _watchGenetChildDoc(docId).map(
      (snap) {
        _logQuestionnaireDebugCardReads(
          receivedChildId: childId,
          primaryId: docId,
          primarySnap: snap,
        );
        return _resolveQuestionnaireViewState(
          docIds,
          {docId: snap.data()},
        );
      },
    );
  }

  final primaryId = docIds[0];
  final legacyId = docIds[1];
  return _watchGenetChildDoc(primaryId).asyncExpand((primarySnap) {
    return _watchGenetChildDoc(legacyId).map((legacySnap) {
      _logQuestionnaireDebugCardReads(
        receivedChildId: childId,
        primaryId: primaryId,
        primarySnap: primarySnap,
        fallbackId: legacyId,
        fallbackSnap: legacySnap,
      );
      return _resolveQuestionnaireViewState(
        docIds,
        {
          primaryId: primarySnap.data(),
          legacyId: legacySnap.data(),
        },
      );
    });
  });
}

/// Merges questionnaire answers into `genet_children/{childId}`.
Future<void> saveChildQuestionnaire({
  required String childId,
  required Map<String, dynamic> questionnaire,
}) async {
  final id = childId.trim();
  if (id.isEmpty) {
    throw StateError('childId is empty');
  }

  final authUid = FirebaseAuth.instance.currentUser?.uid;
  final payloadKeys = questionnaire.keys.toList()..sort();

  debugPrint('[GENET][QUESTIONNAIRE_DEBUG][SAVE] authUid=$authUid');
  debugPrint('[GENET][QUESTIONNAIRE_DEBUG][SAVE] canonicalChildId=$id');
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][SAVE] firestorePath=genet_children/$id',
  );
  debugPrint('[GENET][QUESTIONNAIRE_DEBUG][SAVE] payloadKeys=$payloadKeys');
  debugPrint('[GENET][QUESTIONNAIRE_DEBUG][SAVE] questionnaireCompleted=true');

  debugPrint(
    '[GENET][CHILD_QUESTIONNAIRE] saving questionnaire docId: $id',
  );

  final docRef = FirebaseFirestore.instance
      .collection(kGenetChildrenCollection)
      .doc(id);

  await docRef.set(
    {
      kQuestionnaireField: questionnaire,
      kQuestionnaireCompletedField: true,
    },
    SetOptions(merge: true),
  );

  final verifySnap = await docRef.get();
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][SAVE_VERIFY] exists=${verifySnap.exists}',
  );
  debugPrint(
    '[GENET][QUESTIONNAIRE_DEBUG][SAVE_VERIFY] data=${verifySnap.data()}',
  );
}
