import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/parent_profile.dart';

const String _kParentsCollection = 'genet_parents';

/// Top-level document `genet_parents/{parentId}` — profile fields for future registration UX.
DocumentReference<Map<String, dynamic>> _parentDocRef(String parentId) {
  return FirebaseFirestore.instance.collection(_kParentsCollection).doc(parentId);
}

/// Firestore-backed parent profile read. Returns `null` if missing or on read failure (no throw).
Future<ParentProfile?> getParentProfile(String parentId) async {
  final id = parentId.trim();
  if (id.isEmpty) return null;
  try {
    final testHook = debugGetParentProfileForTests;
    if (testHook != null) {
      return await testHook(id);
    }
    final snap = await _parentDocRef(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return ParentProfile.fromMap(id, snap.data()!);
  } catch (e, st) {
    developer.log('getParentProfile: $e $st', name: 'Sync');
    return null;
  }
}

/// Writes profile fields; trims names, sets `displayName` to `"firstName lastName"` (trimmed).
/// Creates `createdAt` + `updatedAt` on first write; subsequent writes update `updatedAt` only.
Future<void> saveParentProfile({
  required String parentId,
  required String firstName,
  required String lastName,
}) async {
  final id = parentId.trim();
  final fn = firstName.trim();
  final ln = lastName.trim();
  final displayName = '$fn $ln'.trim();
  if (id.isEmpty) return;

  final testHook = debugSaveParentProfileForTests;
  if (testHook != null) {
    await testHook(parentId: id, firstName: fn, lastName: ln);
    return;
  }

  final ref = _parentDocRef(id);
  final snap = await ref.get();
  final payload = <String, dynamic>{
    'firstName': fn,
    'lastName': ln,
    'displayName': displayName,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (snap.exists) {
    await ref.update(payload);
  } else {
    await ref.set({
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// True only when [profile] is non-null and both names are non-empty after trim.
bool isParentProfileComplete(ParentProfile? profile) {
  return profile != null && profile.isComplete;
}

/// Line to show after "מחובר להורה: " on the child home card (`null` ⇒ short label only).
///
/// Uses stored [ParentProfile.displayName] when non-empty, otherwise [ParentProfile.computedDisplayName].
String? parentProfileDisplayLineForChildUi(ParentProfile? profile) {
  if (profile == null) return null;
  final stored = profile.displayName?.trim();
  if (stored != null && stored.isNotEmpty) return stored;
  final computed = profile.computedDisplayName;
  if (computed.isNotEmpty) return computed;
  return null;
}

/// Hebrew headline for the child connection card when [isCanonicallyConnected] is true.
String connectedParentHeadlineForChild({
  required bool isCanonicallyConnected,
  String? parentProfileDisplayLine,
}) {
  if (!isCanonicallyConnected) return '';
  final s = parentProfileDisplayLine?.trim();
  if (s != null && s.isNotEmpty) return 'מחובר להורה: $s';
  return 'מחובר להורה';
}

// --- Test-only hooks (deterministic widget tests; always null in production) ---

@visibleForTesting
Future<ParentProfile?> Function(String normalizedParentId)? debugGetParentProfileForTests;

@visibleForTesting
Future<void> Function({
  required String parentId,
  required String firstName,
  required String lastName,
})?
debugSaveParentProfileForTests;
