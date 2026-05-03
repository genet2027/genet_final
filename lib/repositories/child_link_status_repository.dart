import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase_auth_guard.dart';

// -----------------------------------------------------------------------------
// genet_child_parent_link — LEGACY / OPTIONAL side-channel metadata
// -----------------------------------------------------------------------------
//
// 1. This Firestore collection is NOT the source of truth for parent–child
//    connection. Do not infer "connected" or "disconnected" from it for app
//    logic or UI.
//
// 2. The canonical connection document is:
//        genet_parents/{parentId}/children/{childId}
//    (e.g. connectionStatus, parentId, policy fields). That path is what the
//    active app uses for authoritative link state.
//
// 3. Active app connection state must NOT depend on [watchChildLinkStatus].
//    The child home and sync flows listen to the canonical child doc, not this
//    collection.
//
// 4. This file exists only to perform optional legacy writes (`linked` /
//    `removed` on a small doc keyed by childId) kept for historical parity or
//    external systems. It is side metadata, not the contract for "are we
//    linked?".
//
// 5. Do not add new runtime dependencies on this collection unless the feature
//    is intentionally re-designed with a single clear owner of truth (and
//    migration from the canonical doc is explicitly planned).
// -----------------------------------------------------------------------------

const String _kCollection = 'genet_child_parent_link';
const String _kStatus = 'status';
const String _kLinked = 'linked';
const String _kRemoved = 'removed';
const String _kUpdatedAt = 'updatedAt';

/// Optional legacy write: marks `genet_child_parent_link/{childId}` as `linked`.
/// Does not establish connection truth; canonical state lives under
/// `genet_parents/{parentId}/children/{childId}`.
Future<void> setChildLinkStatusLinked(String childId) async {
  requireFirebaseUser();
  await FirebaseFirestore.instance.collection(_kCollection).doc(childId).set({
    _kStatus: _kLinked,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Optional legacy write: marks `genet_child_parent_link/{childId}` as `removed`.
/// Child disconnect UX and enforcement still follow the canonical child doc;
/// this is not a substitute for updating that document.
Future<void> setChildLinkStatusRemoved(String childId) async {
  requireFirebaseUser();
  await FirebaseFirestore.instance.collection(_kCollection).doc(childId).set({
    _kStatus: _kRemoved,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Streams `status` from the legacy doc (`linked` | `removed`, or null if missing).
/// Not used by active connection flows; do not wire new features here without
/// a deliberate redesign — use the canonical child doc under `genet_parents/`.
Stream<String?> watchChildLinkStatus(String childId) {
  if (childId.isEmpty) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection(_kCollection)
      .doc(childId)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    return snap.data()?[_kStatus] as String?;
  });
}
