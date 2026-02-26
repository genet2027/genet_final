/// A message in the teacher–parent chat (reports). Stored locally.
class AppMessage {
  final String id;
  final String fromRole; // 'teacher' | 'parent'
  final String body;
  final DateTime createdAt;

  const AppMessage({
    required this.id,
    required this.fromRole,
    required this.body,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromRole': fromRole,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };

  static AppMessage fromJson(Map<String, dynamic> json) {
    return AppMessage(
      id: json['id'] as String,
      fromRole: json['fromRole'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  bool get isFromTeacher => fromRole == 'teacher';
  bool get isFromParent => fromRole == 'parent';
}
