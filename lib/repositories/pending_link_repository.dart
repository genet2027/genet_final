import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/firebase_auth_guard.dart';
import '../models/child_entity.dart';
import 'children_repository.dart';

const String _kCollection = 'genet_pending_links';
const String _kStatus = 'status';
const String _kPending = 'pending';
const String _kLinked = 'linked';
const String _kCreatedAt = 'createdAt';
const String _kChildId = 'childId';
const String _kFirstName = 'firstName';
const String _kLastName = 'lastName';
const String _kAge = 'age';
const String _kSchoolCode = 'schoolCode';
const String _kLinkedAt = 'linkedAt';
const String _kParentId = 'parentId';

Future<void> _pendingLinkFirestoreWrite(Future<void> Function() write) async {
  requireFirebaseUser();
  debugPrint('[GENET][LINK_CHILD] Attempting to write pending link');
  try {
    await write();
    debugPrint('[GENET][LINK_CHILD] Write success');
  } catch (e) {
    if (e is FirebaseException) {
      debugPrint('[GENET][LINK_CHILD][ERROR] code=${e.code} message=${e.message}');
    } else {
      debugPrint('[GENET][LINK_CHILD][ERROR] unknown=$e');
    }
    rethrow;
  }
}

/// Parent: create a pending connection with a 4-digit code. Returns the code.
/// [parentId] is written so child can read it after connecting.
Future<String> createPendingLink({String? parentId}) async {
  final code = generateLinkCode();
  final data = <String, dynamic>{
    _kStatus: _kPending,
    _kCreatedAt: FieldValue.serverTimestamp(),
  };
  if (parentId != null && parentId.isNotEmpty) data[_kParentId] = parentId;
  await _pendingLinkFirestoreWrite(
    () => FirebaseFirestore.instance.collection(_kCollection).doc(code).set(data),
  );
  return code;
}

/// Parent: write parentId to pending link doc so child device can read it after connecting.
Future<void> setPendingLinkParentId(String code, String parentId) async {
  await _pendingLinkFirestoreWrite(
    () => FirebaseFirestore.instance.collection(_kCollection).doc(code).update({
      _kParentId: parentId,
    }),
  );
}

/// Child: get parentId from pending link doc (after child has written profile). Returns null until parent writes it.
Future<String?> getPendingLinkParentId(String code) async {
  final snap = await FirebaseFirestore.instance.collection(_kCollection).doc(code).get();
  if (!snap.exists) return null;
  return snap.data()?[_kParentId] as String?;
}

/// Child: stream pending link doc until parentId is set (with timeout). Returns parentId or null.
Stream<String?> watchPendingLinkParentId(String code, {Duration timeout = const Duration(seconds: 30)}) async* {
  if (code.isEmpty) {
    yield null;
    return;
  }
  final stopAt = DateTime.now().add(timeout);
  await for (final snap in FirebaseFirestore.instance.collection(_kCollection).doc(code).snapshots()) {
    if (DateTime.now().isAfter(stopAt)) {
      yield null;
      return;
    }
    if (!snap.exists) continue;
    final id = snap.data()?[_kParentId] as String?;
    if (id != null && id.isNotEmpty) {
      yield id;
      return;
    }
  }
}

/// Parent: listen for a child linking with this code. When linked, onChildLinked is called with the child entity.
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? listenPendingLink(
  String code,
  void Function(ChildEntity child) onChildLinked,
) {
  return FirebaseFirestore.instance
      .collection(_kCollection)
      .doc(code)
      .snapshots()
      .listen((snap) {
    if (!snap.exists) return;
    final data = snap.data()!;
    if (data[_kStatus] != _kLinked) return;
    final childId = data[_kChildId] as String? ?? '';
    if (childId.isEmpty) return;
    final firstName = data[_kFirstName] as String? ?? '';
    final lastName = data[_kLastName] as String? ?? '';
    final name = [firstName, lastName].join(' ').trim();
    final child = ChildEntity(
      childId: childId,
      name: name.isEmpty ? 'ילד' : name,
      firstName: firstName,
      lastName: lastName,
      age: (data[_kAge] as num?)?.toInt() ?? 0,
      schoolCode: data[_kSchoolCode] as String? ?? '',
      linkCode: code,
      isConnected: true,
      connectionStatus: ChildConnectionStatus.connected,
    );
    onChildLinked(child);
  });
}

/// Child: write self profile to pending link. Code = 4-digit from QR or manual entry.
Future<void> writeChildProfileToPendingLink(
  String code,
  String childId,
  String firstName,
  String lastName,
  int age,
  String schoolCode,
) async {
  await _pendingLinkFirestoreWrite(
    () => FirebaseFirestore.instance.collection(_kCollection).doc(code).update({
      _kStatus: _kLinked,
      _kChildId: childId,
      _kFirstName: firstName,
      _kLastName: lastName,
      _kAge: age,
      _kSchoolCode: schoolCode,
      _kLinkedAt: FieldValue.serverTimestamp(),
    }),
  );
}

/// Check if a code exists and is still pending (parent created it, child not yet linked).
Future<bool> isPendingLink(String code) async {
  final snap = await FirebaseFirestore.instance
      .collection(_kCollection)
      .doc(code)
      .get();
  if (!snap.exists) return false;
  return snap.data()?[_kStatus] == _kPending;
}
