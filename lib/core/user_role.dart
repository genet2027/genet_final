import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for device role: parent = control only, child = enforcement only.
const String kUserRoleKey = 'genet_user_role';
const String kUserRoleParent = 'parent';
const String kUserRoleChild = 'child';

Future<String?> getUserRole() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kUserRoleKey);
}

/// Persists role locally only. Call [GenetConfig.setChildMode] after this (or use [GenetConfig.commitUserRole]).
Future<void> setUserRole(String role) async {
  if (role != kUserRoleParent && role != kUserRoleChild) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kUserRoleKey, role);
}

bool isChildRole([String? role]) {
  final r = role;
  return r == kUserRoleChild;
}
