import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical parent identity stored at `genet_parents/{parentId}` (profile fields only).
class ParentProfile {
  const ParentProfile({
    required this.parentId,
    this.firstName,
    this.lastName,
    this.displayName,
    this.createdAt,
    this.updatedAt,
  });

  final String parentId;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isComplete =>
      (firstName != null && firstName!.trim().isNotEmpty) &&
      (lastName != null && lastName!.trim().isNotEmpty);

  String get computedDisplayName {
    final fn = firstName?.trim() ?? '';
    final ln = lastName?.trim() ?? '';
    final combined = '$fn $ln'.trim();
    return combined.isNotEmpty ? combined : '';
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'displayName': displayName,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  static ParentProfile fromMap(String parentId, Map<String, dynamic> map) {
    return ParentProfile(
      parentId: parentId,
      firstName: map['firstName'] as String?,
      lastName: map['lastName'] as String?,
      displayName: map['displayName'] as String?,
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
