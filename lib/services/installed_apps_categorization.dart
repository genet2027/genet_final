import '../models/installed_app.dart';
import '../models/installed_app_raw.dart';

/// Labels emitted by native [InstalledAppsChannel] / [InstalledAppRaw] plus [entertainment] if ever present as text.
const _recognizedCategoryTokens = <String>{
  'game',
  'social',
  'audio',
  'video',
  'image',
  'maps',
  'productivity',
  'entertainment',
  'communication',
};

/// Decision engine (Step 1): internal relevance for one raw row after eligibility.
enum InstalledAppRelevanceDecision {
  clearlyRelevant,
  possiblyRelevant,
  notRelevant,
}

/// Normalized display name for noise checks: lowercase, trim, collapse spaces.
String _normalizeDisplayNameForNoise(String appName) {
  var s = appName.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

/// Step 2 — conservative technical / utility noise on display name only (possiblyRelevant bucket).
bool looksLikeTechnicalOrUtilityNoise(String appName) {
  final n = _normalizeDisplayNameForNoise(appName);
  if (n.isEmpty) return false;

  const phrases = <String>{
    'system ui',
    'print service',
    'companion device manager',
    'package installer',
    'emergency info',
    'device policy',
    'device provisioning',
  };
  for (final p in phrases) {
    if (n.contains(p)) return true;
  }

  const tokens = <String>{
    'carrier',
    'sim',
    'shell',
    'updater',
    'feedback',
    'provisioning',
    'framework',
    'transport',
    'config',
  };
  for (final t in tokens) {
    if (n.contains(t)) return true;
  }

  if (RegExp(r'(^|\s)service(\s|$)').hasMatch(n)) return true;
  if (RegExp(r'(^|\s)setup(\s|$)').hasMatch(n)) return true;
  if (RegExp(r'(^|\s)test(\s|$)').hasMatch(n)) return true;

  return false;
}

/// Eligibility first, then category-based relevance. Single decision entry for the pipeline.
InstalledAppRelevanceDecision decideInstalledAppRelevance(InstalledAppRaw app) {
  if (app.isLaunchable != true) return InstalledAppRelevanceDecision.notRelevant;
  if (app.isSystemApp) return InstalledAppRelevanceDecision.notRelevant;

  final normalized = normalizeInstalledAppCategory(app.category);

  const clearlyRelevantCategories = <String>{
    'social',
    'video',
    'entertainment',
    'communication',
    'game',
  };
  if (clearlyRelevantCategories.contains(normalized)) {
    return InstalledAppRelevanceDecision.clearlyRelevant;
  }
  if (normalized == 'unknown') {
    if (looksLikeTechnicalOrUtilityNoise(app.appName)) {
      return InstalledAppRelevanceDecision.notRelevant;
    }
    return InstalledAppRelevanceDecision.possiblyRelevant;
  }
  return InstalledAppRelevanceDecision.notRelevant;
}

/// Lowercase, trim; only known store tokens kept — anything else becomes [unknown] (no guessing).
String normalizeInstalledAppCategory(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'unknown';
  if (_recognizedCategoryTokens.contains(s)) return s;
  return 'unknown';
}

/// Single public entry: [InstalledAppRaw] → [InstalledApp] for child relevant-app inventory.
///
/// Child sync, realtime engine, and periodic fallback must use this only — no parallel filter.
/// Uses [decideInstalledAppRelevance] (eligibility, clearly/possibly/not, Step‑2 name noise on unknowns).
List<InstalledApp> categorizeInstalledApps(List<InstalledAppRaw> rawApps) {
  final byPackage = <String, InstalledApp>{};
  for (final raw in rawApps) {
    final decision = decideInstalledAppRelevance(raw);
    if (decision == InstalledAppRelevanceDecision.notRelevant) continue;

    final normalized = normalizeInstalledAppCategory(raw.category);
    final isUnknownCategory = decision == InstalledAppRelevanceDecision.possiblyRelevant;

    byPackage[raw.packageName] = InstalledApp(
      packageName: raw.packageName,
      appName: raw.appName,
      isSystemApp: raw.isSystemApp,
      isLaunchable: raw.isLaunchable,
      category: normalized,
      isUnknownCategory: isUnknownCategory,
      versionName: raw.versionName,
      versionCode: raw.versionCode,
      installerPackage: raw.installerPackage,
      installedTime: raw.installedTime,
      updatedTime: raw.updatedTime,
      lastSeenAt: raw.lastSeenAt,
    );
  }
  final list = byPackage.values.toList()
    ..sort((a, b) {
      final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      if (byName != 0) return byName;
      return a.packageName.compareTo(b.packageName);
    });
  return list;
}
