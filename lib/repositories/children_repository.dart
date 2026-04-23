import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/child_entity.dart';
import '../models/child_model.dart';

export '../models/child_entity.dart' show ChildConnectionStatus;

const String _kChildrenListKey = 'genet_children_list';
const String _kSelectedChildIdKey = 'genet_selected_child_id';
const String _kLinkedChildIdKey = 'genet_linked_child_id';
const String _kLinkedChildNameKey = 'genet_linked_child_name';
const String _kLinkedChildFirstNameKey = 'genet_linked_child_first_name';
const String _kLinkedChildLastNameKey = 'genet_linked_child_last_name';
const String _kLocalChildIdKey = 'genet_local_child_id';

const String _kChildSelfProfileKey = 'genet_child_self_profile';

const String _kBlockedPackagesPrefix = 'genet_blocked_packages_';
const String _kBlockedPackagesLegacy = 'genet_blocked_packages';
const String _kExtensionApprovedPrefix = 'genet_extension_approved_until_';
const String _kExtensionApprovedLegacy = 'genet_extension_approved_until';

const String _defaultChildId = 'default';

final _rng = Random();
final StreamController<String?> _selectedChildIdController =
    StreamController<String?>.broadcast();

/// Generates a 4-digit numeric link code (0000-9999).
String generateLinkCode() {
  return (1000 + _rng.nextInt(9000)).toString();
}

/// Generates a unique child id (timestamp-based + random).
String generateChildId() {
  return 'c_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(99999)}';
}

/// Parent: list of children.
Future<List<ChildEntity>> getChildren() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kChildrenListKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => ChildEntity.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveChildren(List<ChildEntity> list) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kChildrenListKey, jsonEncode(list.map((e) => e.toJson()).toList()));
}

/// Parent: selected (active) child id.
Future<String?> getSelectedChildId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSelectedChildIdKey);
}

Future<void> setSelectedChildId(String? childId) async {
  final prefs = await SharedPreferences.getInstance();
  if (childId == null) {
    await prefs.remove(_kSelectedChildIdKey);
  } else {
    await prefs.setString(_kSelectedChildIdKey, childId);
  }
  _selectedChildIdController.add(childId);
}

Stream<String?> watchSelectedChildId() => _selectedChildIdController.stream;

/// Child device: linked child id and name (after QR/code link).
Future<String?> getLinkedChildId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLinkedChildIdKey);
}

Future<String?> getLinkedChildName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLinkedChildNameKey);
}

Future<void> setLinkedChild(
  String? childId,
  String? childName, {
  String? firstName,
  String? lastName,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (childId == null) {
    await prefs.remove(_kLinkedChildIdKey);
    await prefs.remove(_kLinkedChildNameKey);
    await prefs.remove(_kLinkedChildFirstNameKey);
    await prefs.remove(_kLinkedChildLastNameKey);
    // Keep _kLocalChildIdKey so re-connect uses same childId (no duplicate on parent).
  } else {
    await prefs.setString(_kLinkedChildIdKey, childId);
    await prefs.setString(_kLinkedChildNameKey, childName ?? '');
    await prefs.setString(_kLocalChildIdKey, childId);
    if (firstName != null) await prefs.setString(_kLinkedChildFirstNameKey, firstName);
    if (lastName != null) await prefs.setString(_kLinkedChildLastNameKey, lastName);
  }
}

/// Child device: persistent child id for this profile (survives link removal so re-connect reuses same id).
Future<String?> getLocalChildId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLocalChildIdKey);
}

Future<String?> getLinkedChildFirstName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLinkedChildFirstNameKey);
}

Future<String?> getLinkedChildLastName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLinkedChildLastNameKey);
}

/// Per-child blocked packages key.
String blockedPackagesKeyForChild(String childId) => '$_kBlockedPackagesPrefix$childId';

/// Per-child extension approved until key.
String extensionApprovedKeyForChild(String childId) => '$_kExtensionApprovedPrefix$childId';

/// Parent: get blocked packages for a child. Child device: use getLinkedChildId() then this.
Future<List<String>> getBlockedPackagesForChild(String childId) async {
  final prefs = await SharedPreferences.getInstance();
  final list = prefs.getStringList(blockedPackagesKeyForChild(childId)) ?? [];
  return list;
}

Future<void> setBlockedPackagesForChild(String childId, List<String> packages) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(blockedPackagesKeyForChild(childId), packages);
}

/// Parent: get extension approved-until map for a child. Child device: use linked child id.
Future<Map<String, int>> getExtensionApprovedForChild(String childId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(extensionApprovedKeyForChild(childId));
  if (raw == null || raw.isEmpty) return {};
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  } catch (_) {
    return {};
  }
}

Future<void> setExtensionApprovedForChild(String childId, Map<String, int> map) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(extensionApprovedKeyForChild(childId), jsonEncode(map));
}

/// Ensures at least one child exists. Migrates legacy single profile and blocked/extension data to default child.
Future<void> ensureDefaultChild() async {
  final children = await getChildren();
  if (children.isNotEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  ChildEntity defaultChild;
  final existingProfile = await ChildModel.load();
  if (existingProfile != null &&
      (existingProfile.name.isNotEmpty ||
          existingProfile.age > 0 ||
          existingProfile.grade.isNotEmpty ||
          existingProfile.schoolCode.isNotEmpty)) {
    defaultChild = ChildEntity(
      childId: _defaultChildId,
      name: existingProfile.name.isEmpty ? 'ילד' : existingProfile.name,
      age: existingProfile.age,
      grade: existingProfile.grade,
      schoolCode: existingProfile.schoolCode,
      linkCode: generateLinkCode(),
      isConnected: true,
      connectionStatus: ChildConnectionStatus.connected,
    );
  } else {
    defaultChild = ChildEntity(
      childId: _defaultChildId,
      name: 'ילד',
      linkCode: generateLinkCode(),
      isConnected: true,
      connectionStatus: ChildConnectionStatus.connected,
    );
  }

  await saveChildren([defaultChild]);
  await setSelectedChildId(_defaultChildId);

  // Migrate legacy blocked list to default child
  var blocked = prefs.getStringList(_kBlockedPackagesLegacy) ?? [];
  if (blocked.isEmpty) blocked = prefs.getStringList('genet_blocked_apps') ?? [];
  if (blocked.isNotEmpty) {
    await setBlockedPackagesForChild(_defaultChildId, blocked);
  }

  // Migrate legacy extension approved to default child
  final approvedRaw = prefs.getString(_kExtensionApprovedLegacy);
  if (approvedRaw != null && approvedRaw.isNotEmpty) {
    try {
      final map = jsonDecode(approvedRaw) as Map<String, dynamic>;
      final approved = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      if (approved.isNotEmpty) await setExtensionApprovedForChild(_defaultChildId, approved);
    } catch (_) {}
  }
}

/// Find child by link code (parent device). Returns null if not found.
Future<ChildEntity?> findChildByLinkCode(String linkCode) async {
  final list = await getChildren();
  final code = linkCode.trim();
  for (final c in list) {
    if (c.linkCode == code) return c;
  }
  return null;
}

/// Find child by childId.
Future<ChildEntity?> getChildById(String childId) async {
  final list = await getChildren();
  try {
    return list.firstWhere((c) => c.childId == childId);
  } catch (_) {
    return null;
  }
}

/// Add or update child by childId. If childId exists, updates that record; otherwise appends. Prevents duplicates.
Future<void> addOrUpdateChild(ChildEntity child) async {
  final list = await getChildren();
  final index = list.indexWhere((c) => c.childId == child.childId);
  final updated = List<ChildEntity>.from(list);
  if (index >= 0) {
    updated[index] = child;
  } else {
    updated.add(child);
  }
  await saveChildren(updated);
}

/// Remove child from parent's list. Clears selected child if it was this one; optionally selects first remaining.
Future<void> removeChild(String childId) async {
  final list = await getChildren();
  final filtered = list.where((c) => c.childId != childId).toList();
  if (filtered.length == list.length) return;
  await saveChildren(filtered);
  final selected = await getSelectedChildId();
  if (selected == childId) {
    await setSelectedChildId(filtered.isNotEmpty ? filtered.first.childId : null);
  }
}

/// Child device: self-entered profile (before linking). Used when child connects so parent receives details.
const String kChildSelfProfileFirstName = 'firstName';
const String kChildSelfProfileLastName = 'lastName';
const String kChildSelfProfileAge = 'age';
const String kChildSelfProfileSchoolCode = 'schoolCode';

Future<Map<String, dynamic>> getChildSelfProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kChildSelfProfileKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return Map<String, dynamic>.from(map);
  } catch (_) {
    return {};
  }
}

Future<bool> hasChildSelfProfile() async {
  final p = await getChildSelfProfile();
  final first = p[kChildSelfProfileFirstName] as String? ?? '';
  final last = p[kChildSelfProfileLastName] as String? ?? '';
  return first.trim().isNotEmpty || last.trim().isNotEmpty;
}

Future<void> saveChildSelfProfile({
  required String firstName,
  required String lastName,
  required int age,
  required String schoolCode,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kChildSelfProfileKey,
    jsonEncode({
      kChildSelfProfileFirstName: firstName,
      kChildSelfProfileLastName: lastName,
      kChildSelfProfileAge: age,
      kChildSelfProfileSchoolCode: schoolCode,
    }),
  );
}
