/// Connection status for a child in the parent's list.
class ChildConnectionStatus {
  static const String connected = 'connected';
  static const String pending = 'pending';
  static const String disconnected = 'disconnected';
}

/// Child entity in parent's list: unique childId, profile fields (from child self-identify or edit), link code, connection status.
class ChildEntity {
  const ChildEntity({
    required this.childId,
    required this.name,
    this.firstName = '',
    this.lastName = '',
    this.age = 0,
    this.grade = '',
    this.schoolCode = '',
    required this.linkCode,
    this.isConnected = true,
    this.connectionStatus = ChildConnectionStatus.connected,
  });

  final String childId;
  final String name;
  final String firstName;
  final String lastName;
  final int age;
  final String grade;
  final String schoolCode;
  final String linkCode;
  final bool isConnected;
  final String connectionStatus;

  /// Display label for connection status (Hebrew).
  String get connectionStatusLabel {
    switch (connectionStatus) {
      case ChildConnectionStatus.connected:
        return 'מחובר';
      case ChildConnectionStatus.pending:
        return 'ממתין לחיבור';
      case ChildConnectionStatus.disconnected:
        return 'מנותק';
      default:
        return isConnected ? 'מחובר' : 'מנותק';
    }
  }

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'name': name,
        'firstName': firstName,
        'lastName': lastName,
        'age': age,
        'grade': grade,
        'schoolCode': schoolCode,
        'linkCode': linkCode,
        'isConnected': isConnected,
        'connectionStatus': connectionStatus,
      };

  static ChildEntity fromJson(Map<String, dynamic> json) {
    final isConn = json['isConnected'] as bool? ?? true;
    final status = json['connectionStatus'] as String? ?? (isConn ? ChildConnectionStatus.connected : ChildConnectionStatus.disconnected);
    return ChildEntity(
      childId: json['childId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      age: (json['age'] as num?)?.toInt() ?? 0,
      grade: json['grade'] as String? ?? '',
      schoolCode: json['schoolCode'] as String? ?? '',
      linkCode: json['linkCode'] as String? ?? '',
      isConnected: isConn,
      connectionStatus: status,
    );
  }

  ChildEntity copyWith({
    String? childId,
    String? name,
    String? firstName,
    String? lastName,
    int? age,
    String? grade,
    String? schoolCode,
    String? linkCode,
    bool? isConnected,
    String? connectionStatus,
  }) {
    return ChildEntity(
      childId: childId ?? this.childId,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      age: age ?? this.age,
      grade: grade ?? this.grade,
      schoolCode: schoolCode ?? this.schoolCode,
      linkCode: linkCode ?? this.linkCode,
      isConnected: isConnected ?? this.isConnected,
      connectionStatus: connectionStatus ?? this.connectionStatus,
    );
  }
}
