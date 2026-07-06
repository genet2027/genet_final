enum DailyMissionCategory {
  studies,
  sport,
  home,
  sleep,
  other,
}

extension DailyMissionCategoryLabel on DailyMissionCategory {
  String get label {
    switch (this) {
      case DailyMissionCategory.studies:
        return 'לימודים';
      case DailyMissionCategory.sport:
        return 'ספורט';
      case DailyMissionCategory.home:
        return 'בית';
      case DailyMissionCategory.sleep:
        return 'שינה';
      case DailyMissionCategory.other:
        return 'אחר';
    }
  }
}

enum ChildMissionStatus {
  notStarted,
  submitted,
}

extension ChildMissionStatusLabel on ChildMissionStatus {
  String get label {
    switch (this) {
      case ChildMissionStatus.notStarted:
        return 'ממתינה לביצוע';
      case ChildMissionStatus.submitted:
        return 'ממתינה לאישור ההורה';
    }
  }
}

enum ParentApprovalStatus {
  none,
  approved,
  rejected,
}

extension ParentApprovalStatusLabel on ParentApprovalStatus {
  String get label {
    switch (this) {
      case ParentApprovalStatus.none:
        return 'ללא החלטה';
      case ParentApprovalStatus.approved:
        return 'אושרה';
      case ParentApprovalStatus.rejected:
        return 'נדחתה';
    }
  }
}

DailyMissionCategory _categoryFromStorageValue(String? value) {
  return DailyMissionCategory.values.firstWhere(
    (category) => category.name == value,
    orElse: () => DailyMissionCategory.other,
  );
}

ChildMissionStatus _childStatusFromStorageValue(String? value) {
  return ChildMissionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ChildMissionStatus.notStarted,
  );
}

ParentApprovalStatus _parentApprovalStatusFromStorageValue(String? value) {
  return ParentApprovalStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ParentApprovalStatus.none,
  );
}

String _validateTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(title, 'title', 'Title cannot be empty.');
  }
  return trimmed;
}

int _validateRewardXp(int rewardXp) {
  if (rewardXp < 1 || rewardXp > 100) {
    throw ArgumentError.value(
      rewardXp,
      'rewardXp',
      'rewardXp must be between 1 and 100.',
    );
  }
  return rewardXp;
}

int _rewardXpFromMap(dynamic value) {
  final parsed = (value as num?)?.toInt() ?? 10;
  return parsed.clamp(1, 100);
}

DateTime _dateTimeFromMap(
  dynamic value, {
  required DateTime fallback,
}) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

DateTime? _nullableDateTimeFromMap(dynamic value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

class DailyMission {
  DailyMission({
    required this.id,
    required String title,
    this.description,
    this.category = DailyMissionCategory.other,
    required int rewardXp,
    this.childStatus = ChildMissionStatus.notStarted,
    this.parentApprovalStatus = ParentApprovalStatus.none,
    required this.assignedDate,
    required this.createdAt,
    required this.updatedAt,
    this.submittedByChildAt,
    this.approvedByParentAt,
    this.rejectedByParentAt,
    this.rewardGranted = false,
    this.rewardGrantedAt,
  })  : title = _validateTitle(title),
        rewardXp = _validateRewardXp(rewardXp);

  final String id;
  final String title;
  final String? description;
  final DailyMissionCategory category;
  final int rewardXp;
  final ChildMissionStatus childStatus;
  final ParentApprovalStatus parentApprovalStatus;
  final DateTime assignedDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? submittedByChildAt;
  final DateTime? approvedByParentAt;
  final DateTime? rejectedByParentAt;
  final bool rewardGranted;
  final DateTime? rewardGrantedAt;

  bool get isWaitingForChild => childStatus == ChildMissionStatus.notStarted;

  bool get isWaitingForParentApproval =>
      childStatus == ChildMissionStatus.submitted &&
      parentApprovalStatus == ParentApprovalStatus.none;

  bool get isApproved => parentApprovalStatus == ParentApprovalStatus.approved;

  bool get isRejected => parentApprovalStatus == ParentApprovalStatus.rejected;

  bool get canGrantReward => isApproved && !rewardGranted;

  String get displayStatusLabel {
    if (isRejected) return 'נדחתה';
    if (isApproved && rewardGranted) return 'אושרה והתגמול ניתן';
    if (isApproved) return 'אושרה וממתינה לתגמול';
    if (isWaitingForParentApproval) return 'ממתינה לאישור ההורה';
    return 'ממתינה לביצוע';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category.name,
      'rewardXp': rewardXp,
      'childStatus': childStatus.name,
      'parentApprovalStatus': parentApprovalStatus.name,
      'assignedDate': assignedDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'submittedByChildAt': submittedByChildAt?.toIso8601String(),
      'approvedByParentAt': approvedByParentAt?.toIso8601String(),
      'rejectedByParentAt': rejectedByParentAt?.toIso8601String(),
      'rewardGranted': rewardGranted,
      'rewardGrantedAt': rewardGrantedAt?.toIso8601String(),
    };
  }

  factory DailyMission.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    final title = (map['title'] as String? ?? '').trim();

    return DailyMission(
      id: map['id'] as String? ?? '',
      title: title.isEmpty ? 'משימה' : title,
      description: map['description'] as String?,
      category: _categoryFromStorageValue(map['category'] as String?),
      rewardXp: _rewardXpFromMap(map['rewardXp']),
      childStatus: _childStatusFromStorageValue(map['childStatus'] as String?),
      parentApprovalStatus: _parentApprovalStatusFromStorageValue(
        map['parentApprovalStatus'] as String?,
      ),
      assignedDate: _dateTimeFromMap(
        map['assignedDate'],
        fallback: now,
      ),
      createdAt: _dateTimeFromMap(
        map['createdAt'],
        fallback: now,
      ),
      updatedAt: _dateTimeFromMap(
        map['updatedAt'],
        fallback: now,
      ),
      submittedByChildAt: _nullableDateTimeFromMap(map['submittedByChildAt']),
      approvedByParentAt: _nullableDateTimeFromMap(map['approvedByParentAt']),
      rejectedByParentAt: _nullableDateTimeFromMap(map['rejectedByParentAt']),
      rewardGranted: map['rewardGranted'] as bool? ?? false,
      rewardGrantedAt: _nullableDateTimeFromMap(map['rewardGrantedAt']),
    );
  }

  DailyMission copyWith({
    String? id,
    String? title,
    String? description,
    bool clearDescription = false,
    DailyMissionCategory? category,
    int? rewardXp,
    ChildMissionStatus? childStatus,
    ParentApprovalStatus? parentApprovalStatus,
    DateTime? assignedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? submittedByChildAt,
    bool clearSubmittedByChildAt = false,
    DateTime? approvedByParentAt,
    bool clearApprovedByParentAt = false,
    DateTime? rejectedByParentAt,
    bool clearRejectedByParentAt = false,
    bool? rewardGranted,
    DateTime? rewardGrantedAt,
    bool clearRewardGrantedAt = false,
  }) {
    return DailyMission(
      id: id ?? this.id,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      category: category ?? this.category,
      rewardXp: rewardXp ?? this.rewardXp,
      childStatus: childStatus ?? this.childStatus,
      parentApprovalStatus: parentApprovalStatus ?? this.parentApprovalStatus,
      assignedDate: assignedDate ?? this.assignedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedByChildAt: clearSubmittedByChildAt
          ? null
          : (submittedByChildAt ?? this.submittedByChildAt),
      approvedByParentAt: clearApprovedByParentAt
          ? null
          : (approvedByParentAt ?? this.approvedByParentAt),
      rejectedByParentAt: clearRejectedByParentAt
          ? null
          : (rejectedByParentAt ?? this.rejectedByParentAt),
      rewardGranted: rewardGranted ?? this.rewardGranted,
      rewardGrantedAt: clearRewardGrantedAt
          ? null
          : (rewardGrantedAt ?? this.rewardGrantedAt),
    );
  }
}
