import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'children_repository.dart';

const String _kChildrenCollection = 'genet_children';

/// Child device profile at `genet_children/{childId}` (profile only; not parent connection docs).
class ChildProfile {
  const ChildProfile({
    required this.childId,
    this.firstName,
    this.lastName,
    this.fullName,
    this.birthDate,
    this.age,
    this.phone,
    this.role,
    this.authUid,
    this.profileCompleted,
    this.createdAt,
    this.updatedAt,
  });

  final String childId;
  final String? firstName;
  final String? lastName;
  final String? fullName;
  final DateTime? birthDate;
  final int? age;
  final String? phone;
  final String? role;
  final String? authUid;
  final bool? profileCompleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isComplete => profileCompleted == true;

  static ChildProfile fromMap(String childId, Map<String, dynamic> map) {
    return ChildProfile(
      childId: childId,
      firstName: map['firstName'] as String?,
      lastName: map['lastName'] as String?,
      fullName: map['fullName'] as String?,
      birthDate: _readTimestamp(map['birthDate']),
      age: (map['age'] as num?)?.toInt(),
      phone: map['phone'] as String?,
      role: map['role'] as String?,
      authUid: map['authUid'] as String?,
      profileCompleted: map['profileCompleted'] as bool?,
      createdAt: _readTimestamp(map['createdAt']),
      updatedAt: _readTimestamp(map['updatedAt']),
    );
  }

  static DateTime? _readTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

DocumentReference<Map<String, dynamic>> _childDocRef(String childId) {
  return FirebaseFirestore.instance.collection(_kChildrenCollection).doc(childId);
}

Future<ChildProfile?> getChildProfile(String childId) async {
  final id = childId.trim();
  if (id.isEmpty) return null;
  try {
    final testHook = debugGetChildProfileForTests;
    if (testHook != null) {
      return await testHook(id);
    }
    final snap = await _childDocRef(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return ChildProfile.fromMap(id, snap.data()!);
  } catch (e, st) {
    developer.log('getChildProfile: $e $st', name: 'Sync');
    return null;
  }
}

Future<bool> isChildProfileComplete() async {
  final childId = await getLocalChildId();
  if (childId != null && childId.isNotEmpty) {
    final profile = await getChildProfile(childId);
    if (profile?.profileCompleted == true) return true;
  }
  return hasChildSelfProfile();
}

/// Full registration profile at `genet_children/{childId}` (merge; no connection docs).
Future<void> saveRegistrationChildProfile({
  required String childId,
  required String authUid,
  required String firstName,
  required String lastName,
  required DateTime birthDate,
  required int age,
  required String phone,
}) async {
  final id = childId.trim();
  final fn = firstName.trim();
  final ln = lastName.trim();
  final fullName = '$fn $ln'.trim();
  if (id.isEmpty || authUid.trim().isEmpty) return;

  final testHook = debugSaveRegistrationChildProfileForTests;
  if (testHook != null) {
    await testHook(
      childId: id,
      authUid: authUid,
      firstName: fn,
      lastName: ln,
      birthDate: birthDate,
      age: age,
      phone: phone.trim(),
    );
    return;
  }

  final ref = _childDocRef(id);
  try {
    final snap = await ref.get();
    final payload = <String, dynamic>{
      'firstName': fn,
      'lastName': ln,
      'fullName': fullName,
      'birthDate': Timestamp.fromDate(birthDate),
      'age': age,
      'phone': phone.trim(),
      'role': 'child',
      'authUid': authUid,
      'childId': id,
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(payload, SetOptions(merge: true));
  } catch (e) {
    debugPrint('[GENET][CHILD_PROFILE_REPO][ERROR] saveRegistrationChildProfile failed: $e');
    debugPrint('[GENET][CHILD_PROFILE_REPO][ERROR] childId=$id');
    rethrow;
  }
}

@visibleForTesting
Future<ChildProfile?> Function(String normalizedChildId)? debugGetChildProfileForTests;

@visibleForTesting
Future<void> Function({
  required String childId,
  required String authUid,
  required String firstName,
  required String lastName,
  required DateTime birthDate,
  required int age,
  required String phone,
})?
debugSaveRegistrationChildProfileForTests;
