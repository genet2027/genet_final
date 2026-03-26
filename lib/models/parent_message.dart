import 'package:cloud_firestore/cloud_firestore.dart';

class ParentMessage {
  const ParentMessage({
    required this.id,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String body;
  final DateTime updatedAt;

  bool get hasContent => body.trim().isNotEmpty;

  factory ParentMessage.create(String body) {
    final now = DateTime.now();
    return ParentMessage(
      id: 'pm_${now.microsecondsSinceEpoch}',
      body: body.trim(),
      updatedAt: now,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'body': body,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory ParentMessage.fromMap(Map<String, dynamic> map) {
    final rawUpdatedAt = map['updatedAt'];
    DateTime updatedAt;
    if (rawUpdatedAt is Timestamp) {
      updatedAt = rawUpdatedAt.toDate();
    } else if (rawUpdatedAt is DateTime) {
      updatedAt = rawUpdatedAt;
    } else if (rawUpdatedAt is int) {
      updatedAt = DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt);
    } else if (rawUpdatedAt is String) {
      updatedAt = DateTime.tryParse(rawUpdatedAt) ?? DateTime.now();
    } else {
      updatedAt = DateTime.now();
    }

    return ParentMessage(
      id:
          (map['id'] as String?)?.trim().isNotEmpty == true
              ? (map['id'] as String).trim()
              : 'pm_${updatedAt.microsecondsSinceEpoch}',
      body: (map['body'] as String? ?? '').trim(),
      updatedAt: updatedAt,
    );
  }
}
