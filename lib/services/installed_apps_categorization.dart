import 'package:flutter/foundation.dart';

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

/// Result of relevance decision: optional winning heuristic family for [InstalledApp.category].
class InstalledAppRelevanceOutcome {
  const InstalledAppRelevanceOutcome(this.decision, {this.winningHeuristicCategory});

  final InstalledAppRelevanceDecision decision;
  /// When non-null, the app was included via that heuristic path (not store-category fallback).
  final String? winningHeuristicCategory;
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

void _logBrowser(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsBrowser] $msg');
  }
}

void _logSocial(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsSocial] $msg');
  }
}

void _logVideo(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsVideo] $msg');
  }
}

void _logGames(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsGames] $msg');
  }
}

void _logMessaging(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsMessaging] $msg');
  }
}

void _logMusic(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsMusic] $msg');
  }
}

/// Display-name fallback when package is not in [InstalledApp.isKnownBrowserPackage] lists.
bool _looksLikeRealBrowserAppName(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  var n = appName.trim().toLowerCase();
  n = n.replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty) return false;
  if (n.contains('webview') || n.contains('trichrome') || n.contains('custom tab')) {
    return false;
  }
  if (n.contains('remote desktop')) return false;

  const needles = <String>[
    'samsung internet',
    'microsoft edge',
    'mozilla firefox',
    'google chrome',
    'tor browser',
    'kiwi browser',
    'uc browser',
    'pure browser',
    'pure lite browser',
    'opera mini',
    'opera gx',
    'opera touch',
    'opera browser',
    'firefox focus',
    'firefox beta',
    'duckduckgo',
    'vivaldi',
    'aloha browser',
    'ecosia browser',
    'yandex browser',
    'brave browser',
    'edge browser',
    'firefox',
    'chrome',
    'opera',
    'brave',
    'vivaldi',
    'yandex',
    'ecosia',
    'aloha',
    'edge',
  ];
  for (final s in needles) {
    if (n.contains(s)) return true;
  }
  if (n.contains('browser') &&
      !n.contains('package') &&
      !n.contains('installer') &&
      !n.contains('webview')) {
    return true;
  }
  if (n.contains('internet') && n.contains('samsung')) return true;
  return false;
}

/// Name-only social signal; package matches use [InstalledApp.isKnownSocialPackage] first.
bool _looksLikeSocialAppNameForRelevance(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  return InstalledApp.looksLikeSocialAppName(appName);
}

/// Name-only streaming signal; package matches use [InstalledApp.isKnownVideoApp] first.
bool _looksLikeVideoAppNameForRelevance(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  return InstalledApp.looksLikeVideoAppName(appName);
}

/// Name-only game signal; package matches use [InstalledApp.isKnownGamePackage] first.
bool _looksLikeGameAppNameForRelevance(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  return InstalledApp.looksLikeGameAppName(appName);
}

/// Name-only chat signal; package matches use [InstalledApp.isKnownMessagingPackage] first.
bool _looksLikeMessagingAppNameForRelevance(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  return InstalledApp.looksLikeMessagingAppName(appName);
}

/// Name-only music signal; package matches use [InstalledApp.isKnownMusicPackage] first.
bool _looksLikeMusicAppNameForRelevance(String appName) {
  if (looksLikeTechnicalOrUtilityNoise(appName)) return false;
  return InstalledApp.looksLikeMusicAppName(appName);
}

/// Parent blocklist–driven relevance: approved categories + browser/social/music/video/games/messaging heuristics + stock SMS.
/// Used for full scan and realtime add ([installedAppForRelevantRaw] / [categorizeInstalledApps]).
InstalledAppRelevanceOutcome _decideInstalledAppRelevanceOutcome(InstalledAppRaw app) {
  final pkg = app.packageName.toLowerCase();
  final rawCat = app.category;
  final appName = app.appName;

  if (app.isLaunchable != true) {
    _logCategoryFilter(
      'exclude pkg=$pkg app=$appName rawCategory=$rawCat reason=not_launchable',
    );
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isWebViewEnginePackage(pkg)) {
    _logBrowser('exclude pkg=$pkg app=$appName reason=webview_engine');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownBrowserPackage(pkg)) {
    _logBrowser('include pkg=$pkg app=$appName reason=browser_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'browser',
    );
  }

  if (InstalledApp.browserPackageLooksLikeEngineOrHelper(pkg)) {
    _logBrowser('exclude pkg=$pkg app=$appName reason=browser_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (_looksLikeRealBrowserAppName(appName)) {
    _logBrowser('include pkg=$pkg app=$appName reason=browser_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'browser',
    );
  }

  if (InstalledApp.socialPackageLooksLikeFalsePositive(pkg)) {
    _logSocial('exclude pkg=$pkg app=$appName reason=social_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownSocialPackage(pkg)) {
    _logSocial('include pkg=$pkg app=$appName reason=social_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'social',
    );
  }

  if (_looksLikeSocialAppNameForRelevance(appName)) {
    _logSocial('include pkg=$pkg app=$appName reason=social_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'social',
    );
  }

  if (InstalledApp.musicPackageLooksLikeFalsePositive(pkg)) {
    _logMusic('exclude pkg=$pkg app=$appName reason=music_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownMusicPackage(pkg)) {
    _logMusic('include pkg=$pkg app=$appName reason=music_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'music',
    );
  }

  if (_looksLikeMusicAppNameForRelevance(appName)) {
    _logMusic('include pkg=$pkg app=$appName reason=music_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'music',
    );
  }

  if (InstalledApp.videoPackageLooksLikeFalsePositive(pkg)) {
    _logVideo('exclude pkg=$pkg app=$appName reason=video_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownVideoApp(pkg)) {
    _logVideo('include pkg=$pkg app=$appName reason=video_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'video',
    );
  }

  if (_looksLikeVideoAppNameForRelevance(appName)) {
    _logVideo('include pkg=$pkg app=$appName reason=video_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'video',
    );
  }

  if (InstalledApp.gamePackageLooksLikeFalsePositive(pkg)) {
    _logGames('exclude pkg=$pkg app=$appName reason=game_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownGamePackage(pkg)) {
    _logGames('include pkg=$pkg app=$appName reason=game_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'games',
    );
  }

  if (_looksLikeGameAppNameForRelevance(appName)) {
    _logGames('include pkg=$pkg app=$appName reason=game_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'games',
    );
  }

  if (InstalledApp.messagingPackageLooksLikeFalsePositive(pkg)) {
    _logMessaging('exclude pkg=$pkg app=$appName reason=messaging_false_positive');
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (InstalledApp.isKnownMessagingPackage(pkg)) {
    _logMessaging('include pkg=$pkg app=$appName reason=messaging_package_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'messaging',
    );
  }

  if (_looksLikeMessagingAppNameForRelevance(appName)) {
    _logMessaging('include pkg=$pkg app=$appName reason=messaging_name_match');
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'messaging',
    );
  }

  if (InstalledApp.isStockSmsUiPackage(pkg)) {
    _logCategoryFilter(
      'include pkg=$pkg app=$appName rawCategory=$rawCat normalized=Messaging reason=stock_sms_ui',
    );
    return const InstalledAppRelevanceOutcome(
      InstalledAppRelevanceDecision.clearlyRelevant,
      winningHeuristicCategory: 'messaging',
    );
  }

  if (app.isSystemApp) {
    _logCategoryFilter(
      'exclude pkg=$pkg app=$appName rawCategory=$rawCat reason=system_app',
    );
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (looksLikeTechnicalOrUtilityNoise(appName)) {
    final normEarly = normalizeInstalledAppCategory(rawCat);
    _logCategoryFilter(
      'exclude pkg=$pkg app=$appName rawCategory=$rawCat normalized=$normEarly reason=technical_noise_helper',
    );
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  final normalized = normalizeInstalledAppCategory(rawCat);

  const approvedNormalized = <String>{
    'social',
    'video',
    'entertainment',
    'communication',
    'game',
    'audio',
  };

  if (normalized == 'unknown') {
    _logCategoryFilter(
      'exclude pkg=$pkg app=$appName rawCategory=$rawCat normalized=unknown reason=not_approved_category',
    );
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  if (!approvedNormalized.contains(normalized)) {
    _logCategoryFilter(
      'exclude pkg=$pkg app=$appName rawCategory=$rawCat normalized=$normalized reason=not_approved_category',
    );
    return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.notRelevant);
  }

  final label = _approvedParentBlockCategoryLabel(normalized);
  _logCategoryFilter(
    'include pkg=$pkg app=$appName rawCategory=$rawCat normalized=$label reason=approved_category',
  );
  return const InstalledAppRelevanceOutcome(InstalledAppRelevanceDecision.clearlyRelevant);
}

InstalledAppRelevanceDecision decideInstalledAppRelevance(InstalledAppRaw app) =>
    _decideInstalledAppRelevanceOutcome(app).decision;

/// Lowercase, trim; maps Play / OEM phrasing into known category tokens where possible.
String normalizeInstalledAppCategory(String? raw) {
  var s = (raw ?? '').trim().toLowerCase().replaceAll('_', ' ');
  if (s.isEmpty) return 'unknown';

  /// [InstalledApp.category] heuristic family tokens → canonical tokens (e.g. sync fingerprint).
  const heuristicStoredToNormalized = <String, String>{
    'browser': 'browser',
    'social': 'social',
    'video': 'video',
    'games': 'game',
    'messaging': 'communication',
    'music': 'audio',
  };
  final fromHeuristicStored = heuristicStoredToNormalized[s];
  if (fromHeuristicStored != null) return fromHeuristicStored;

  const directAliases = <String, String>{
    'music and audio': 'audio',
    'music & audio': 'audio',
    'games': 'game',
  };
  final aliased = directAliases[s];
  if (aliased != null) return aliased;

  if (s.contains('music') && s.contains('audio')) return 'audio';

  if (s.contains('entertainment') ||
      s.contains('streaming') ||
      s.contains('video') ||
      s.contains('movie') ||
      (s.contains('short') && s.contains('video'))) {
    return 'video';
  }
  if (s.contains('social')) return 'social';
  if (s.contains('communicat') || s.contains('messaging') || s.contains('messenger')) {
    return 'communication';
  }
  if (s.contains('game') || s.contains('arcade')) return 'game';

  if (_recognizedCategoryTokens.contains(s)) return s;
  return 'unknown';
}

String _approvedParentBlockCategoryLabel(String normalizedToken) {
  switch (normalizedToken) {
    case 'social':
      return 'Social';
    case 'video':
    case 'entertainment':
      return 'Video & Streaming';
    case 'game':
      return 'Games';
    case 'communication':
      return 'Messaging';
    case 'audio':
      return 'Music';
    default:
      return normalizedToken;
  }
}

void _logCategoryFilter(String msg) {
  if (kDebugMode) {
    debugPrint('[BlockedAppsCategoryFilter] $msg');
  }
}

/// Full decision pipeline for one row: null if not eligible / not relevant.
///
/// Realtime fast path must use this (not [categorizeInstalledApps] on a one-item list only) so
/// add/remove matches full-scan behavior without a temporary unclassified insert.
InstalledApp? installedAppForRelevantRaw(InstalledAppRaw? raw) {
  if (raw == null) return null;
  final outcome = _decideInstalledAppRelevanceOutcome(raw);
  if (outcome.decision == InstalledAppRelevanceDecision.notRelevant) return null;

  final category =
      outcome.winningHeuristicCategory ?? normalizeInstalledAppCategory(raw.category);
  final isUnknownCategory = false;

  return InstalledApp(
    packageName: raw.packageName,
    appName: raw.appName,
    isSystemApp: raw.isSystemApp,
    isLaunchable: raw.isLaunchable,
    category: category,
    isUnknownCategory: isUnknownCategory,
    versionName: raw.versionName,
    versionCode: raw.versionCode,
    installerPackage: raw.installerPackage,
    installedTime: raw.installedTime,
    updatedTime: raw.updatedTime,
    lastSeenAt: raw.lastSeenAt,
  );
}

/// Single public entry: [InstalledAppRaw] → [InstalledApp] for child relevant-app inventory.
///
/// Child sync, realtime engine, and periodic fallback must use this only — no parallel filter.
/// Uses [decideInstalledAppRelevance] (approved parent blocklist categories, browser/social/music/video/games/messaging/SMS detection, exclusions).
List<InstalledApp> categorizeInstalledApps(List<InstalledAppRaw> rawApps) {
  final byPackage = <String, InstalledApp>{};
  for (final raw in rawApps) {
    final app = installedAppForRelevantRaw(raw);
    if (app != null) {
      byPackage[raw.packageName] = app;
    }
  }
  final list = byPackage.values.toList()
    ..sort((a, b) {
      final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      if (byName != 0) return byName;
      return a.packageName.compareTo(b.packageName);
    });
  return list;
}
