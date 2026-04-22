import 'package:flutter/foundation.dart';

import '../../models/installed_app.dart';
import 'blocked_package_matching.dart';

/// Parent blocked-apps UI: always show these apps; match child inventory by package.
class FixedBlockableAppDef {
  const FixedBlockableAppDef({
    required this.id,
    required this.displayName,
    required this.canonicalBlockPackage,
    required this.packageNames,
  });

  final String id;
  final String displayName;
  /// Used in [_blockedPackages] when the app is not installed on the child.
  final String canonicalBlockPackage;
  final Set<String> packageNames;

  InstalledApp placeholderApp() {
    return InstalledApp(
      packageName: canonicalBlockPackage,
      appName: displayName,
      isSystemApp: false,
      isLaunchable: true,
      category: 'social',
      isUnknownCategory: false,
      versionName: '',
      versionCode: 0,
      installerPackage: '',
      installedTime: null,
      updatedTime: null,
      lastSeenAt: 0,
    );
  }
}

/// Order: YouTube, Facebook, Instagram.
/// SYNC: [blocked_package_matching._kFixedCatalogPackageFamilies] must use the same package sets.
const List<FixedBlockableAppDef> kFixedBlockableApps = [
  FixedBlockableAppDef(
    id: 'youtube',
    displayName: 'YouTube',
    canonicalBlockPackage: 'com.google.android.youtube',
    packageNames: {'com.google.android.youtube'},
  ),
  FixedBlockableAppDef(
    id: 'facebook',
    displayName: 'Facebook',
    canonicalBlockPackage: 'com.facebook.katana',
    packageNames: {'com.facebook.katana', 'com.facebook.lite'},
  ),
  FixedBlockableAppDef(
    id: 'instagram',
    displayName: 'Instagram',
    canonicalBlockPackage: 'com.instagram.android',
    packageNames: {'com.instagram.android'},
  ),
];

final Set<String> kAllFixedBlockablePackages = kFixedBlockableApps
    .expand((d) => d.packageNames)
    .toSet();

/// One row in the parent blocked-apps list (fixed catalog and/or child inventory).
class ParentBlockedAppListRow {
  const ParentBlockedAppListRow({
    required this.isFixedCatalog,
    required this.displayName,
    required this.app,
    required this.blockPackageName,
    required this.matchPackages,
    required this.installedOnChild,
    required this.matchedInstalledPackageName,
    required this.allowRemoveFromList,
    required this.stableListKey,
  });

  final bool isFixedCatalog;
  final String displayName;
  final InstalledApp app;
  final String blockPackageName;
  final Set<String> matchPackages;
  final bool installedOnChild;
  final String? matchedInstalledPackageName;
  final bool allowRemoveFromList;
  final String stableListKey;

  /// Delegates to [effectiveBlockedPackageIds] (same path as child UI + ChildProtection).
  bool isBlocked(List<String> blockedPackages) {
    final eff = effectiveBlockedPackageIds(blockedPackages);
    return matchPackages.any(eff.contains);
  }
}

/// Fixed entries first (merged with inventory), then remaining dynamic apps in [visible] order.
List<ParentBlockedAppListRow> mergeFixedCatalogWithInstalled(List<InstalledApp> visible) {
  final rows = <ParentBlockedAppListRow>[];

  for (final def in kFixedBlockableApps) {
    InstalledApp? matched;
    for (final app in visible) {
      if (def.packageNames.contains(app.packageName)) {
        matched = app;
        break;
      }
    }
    final installed = matched != null;
    final blockPkg = matched?.packageName ?? def.canonicalBlockPackage;
    final appForRow = matched ?? def.placeholderApp();

    if (kDebugMode) {
      debugPrint(
        '[BlockedAppsFixedCatalog] injected ${def.displayName} installed=$installed '
        'package=${matched?.packageName}',
      );
    }

    rows.add(
      ParentBlockedAppListRow(
        isFixedCatalog: true,
        displayName: def.displayName,
        app: appForRow,
        blockPackageName: blockPkg,
        matchPackages: def.packageNames,
        installedOnChild: installed,
        matchedInstalledPackageName: matched?.packageName,
        allowRemoveFromList: false,
        stableListKey: 'fixed_${def.id}',
      ),
    );
  }

  for (final app in visible) {
    if (kAllFixedBlockablePackages.contains(app.packageName)) {
      continue;
    }
    rows.add(
      ParentBlockedAppListRow(
        isFixedCatalog: false,
        displayName: app.appName,
        app: app,
        blockPackageName: app.packageName,
        matchPackages: {app.packageName},
        installedOnChild: true,
        matchedInstalledPackageName: app.packageName,
        allowRemoveFromList: true,
        stableListKey: 'dyn_${app.packageName}',
      ),
    );
  }

  if (kDebugMode) {
    for (final r in rows) {
      debugPrint(
        '[BlockedAppsInstalledDot] row=${r.displayName} installedOnChild=${r.installedOnChild}',
      );
    }
  }

  return rows;
}
