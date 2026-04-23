import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/children_repository.dart';

/// מקור נתונים משותף לבקשות הארכה – מסך הילד שולח, מסך ההורה מאשר/דוחה.
const String kExtensionRequestsKey = 'genet_extension_requests';
const String kExtensionApprovedUntilKey = 'genet_extension_approved_until';

class ExtensionRequestStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
}

Future<List<ExtensionRequest>> getExtensionRequests() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kExtensionRequestsKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => ExtensionRequest.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveExtensionRequests(List<ExtensionRequest> list) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kExtensionRequestsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
}

/// Extension approved-until per child. Use this instead of legacy global getter.
Future<Map<String, int>> getExtensionApprovedUntil([String? childId]) async {
  if (childId != null && childId.isNotEmpty) {
    return getExtensionApprovedForChild(childId);
  }
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kExtensionApprovedUntilKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  } catch (_) {
    return {};
  }
}

/// Save extension approved-until for a specific child.
Future<void> saveExtensionApprovedUntil(Map<String, int> map, [String? childId]) async {
  if (childId != null && childId.isNotEmpty) {
    await setExtensionApprovedForChild(childId, map);
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kExtensionApprovedUntilKey, jsonEncode(map));
}

class ExtensionRequest {
  ExtensionRequest({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.minutes,
    required this.status,
    required this.requestedAt,
    this.childId = '',
    this.childName = '',
    this.childFirstName = '',
    this.childLastName = '',
  });

  final String id;
  final String packageName;
  final String appName;
  final int minutes;
  final String status;
  final int requestedAt;
  final String childId;
  final String childName;
  final String childFirstName;
  final String childLastName;

  String get childDisplayName {
    if (childFirstName.isNotEmpty || childLastName.isNotEmpty) {
      return [childFirstName, childLastName].join(' ').trim();
    }
    return childName;
  }

  factory ExtensionRequest.fromJson(Map<String, dynamic> json) {
    final createdOrRequested =
        (json['createdAt'] as num?)?.toInt() ??
        (json['requestedAt'] as num?)?.toInt() ??
        0;
    return ExtensionRequest(
      id: json['id'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? ExtensionRequestStatus.pending,
      requestedAt: createdOrRequested,
      childId: json['childId'] as String? ?? '',
      childName: json['childName'] as String? ?? '',
      childFirstName: json['childFirstName'] as String? ?? '',
      childLastName: json['childLastName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'appName': appName,
        'minutes': minutes,
        'status': status,
        'requestedAt': requestedAt,
        'createdAt': requestedAt,
        'childId': childId,
        'childName': childName,
        'childFirstName': childFirstName,
        'childLastName': childLastName,
      };

  ExtensionRequest copyWith({String? status}) => ExtensionRequest(
        id: id,
        packageName: packageName,
        appName: appName,
        minutes: minutes,
        status: status ?? this.status,
        requestedAt: requestedAt,
        childId: childId,
        childName: childName,
        childFirstName: childFirstName,
        childLastName: childLastName,
      );
}
