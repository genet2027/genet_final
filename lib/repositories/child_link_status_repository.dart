import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase_auth_guard.dart';

const String _kCollection = 'genet_child_parent_link';
const String _kStatus = 'status';
const String _kLinked = 'linked';
const String _kRemoved = 'removed';
const String _kUpdatedAt = 'updatedAt';

/// Child device: after linking, create/update doc so parent can later mark as removed.
Future<void> setChildLinkStatusLinked(String childId) async {
  requireFirebaseUser();
  await FirebaseFirestore.instance.collection(_kCollection).doc(childId).set({
    _kStatus: _kLinked,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Parent: when removing a child, mark link as removed so child device can react.
Future<void> setChildLinkStatusRemoved(String childId) async {
  requireFirebaseUser();
  await FirebaseFirestore.instance.collection(_kCollection).doc(childId).set({
    _kStatus: _kRemoved,
    _kUpdatedAt: FieldValue.serverTimestamp(),
  });
}

/// Child device: stream status for this childId. Emits 'linked' | 'removed' (or null if doc missing).
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
