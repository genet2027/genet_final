import 'package:shared_preferences/shared_preferences.dart';

import '../models/installed_app.dart';
import '../repositories/parent_child_sync_repository.dart' show normalizeIdentifier;

/// Parent-only: packages hidden from the relevant-apps list (X button). Persisted per selected child.
class ParentInstalledAppExclusions {
  ParentInstalledAppExclusions._();

  static String _keyForChild(String normalizedChildId) =>
      'genet_parent_relevant_excluded_$normalizedChildId';

  static Future<Set<String>> excludedPackages(String? childId) async {
    final id = normalizeIdentifier(childId);
    if (id == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyForChild(id));
    if (list == null || list.isEmpty) return {};
    return list.toSet();
  }

  static Future<void> addToExcluded(String? childId, String packageName) async {
    final id = normalizeIdentifier(childId);
    final pkg = packageName.trim();
    if (id == null || pkg.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final next = await excludedPackages(id)..add(pkg);
    await prefs.setStringList(_keyForChild(id), next.toList()..sort());
  }

  static Future<void> removeFromExcluded(String? childId, String packageName) async {
    final id = normalizeIdentifier(childId);
    final pkg = packageName.trim();
    if (id == null || pkg.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final next = await excludedPackages(id)..remove(pkg);
    if (next.isEmpty) {
      await prefs.remove(_keyForChild(id));
    } else {
      await prefs.setStringList(_keyForChild(id), next.toList()..sort());
    }
  }

  static Future<bool> isExcluded(String? childId, String packageName) async {
    final ex = await excludedPackages(childId);
    return ex.contains(packageName.trim());
  }

  static Future<List<InstalledApp>> filterExcluded(
    String? childId,
    List<InstalledApp> apps,
  ) async {
    final ex = await excludedPackages(childId);
    if (ex.isEmpty) return List<InstalledApp>.from(apps);
    return apps.where((a) => !ex.contains(a.packageName)).toList();
  }
}
