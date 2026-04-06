class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
    required this.isLaunchable,
    required this.category,
    this.isUnknownCategory = false,
    required this.versionName,
    required this.versionCode,
    required this.installerPackage,
    required this.installedTime,
    required this.updatedTime,
    required this.lastSeenAt,
  });

  final String packageName;
  final String appName;
  final bool isSystemApp;
  final bool isLaunchable;
  final String category;
  /// True when store category could not be mapped to a known label ([normalizeInstalledAppCategory] → `unknown`).
  final bool isUnknownCategory;
  final String versionName;
  final int versionCode;
  final String installerPackage;
  final int? installedTime;
  final int? updatedTime;
  final int lastSeenAt;

  static const Set<String> _knownRelevantExactPackages = {
    'com.whatsapp',
    'com.whatsapp.w4b',
    'com.whatsapp.business',
    'com.instagram.android',
    'com.facebook.katana',
    'com.facebook.orca',
    'com.facebook.lite',
    'com.snapchat.android',
    'org.telegram.messenger',
    'org.thunderdog.challegram',
    'com.discord',
    'com.twitter.android',
    'com.twitter.twidere',
    'com.threads.android',
    'com.reddit.frontpage',
    'com.zhiliaoapp.musically',
    'com.google.android.youtube',
    'com.google.android.apps.youtube.music',
    'com.netflix.mediaclient',
    'com.disney.disneyplus',
    'com.amazon.avod.thirdpartyclient',
    'tv.twitch.android.app',
    'com.spotify.music',
    'com.roblox.client',
    'com.ss.android.ugc.trill',
  };

  static const List<String> _knownRelevantPackagePrefixes = [
    'com.instagram.',
    'com.facebook.',
    'com.google.android.youtube',
    'com.zhiliaoapp.',
    'org.telegram.',
    'com.discord',
    'com.snapchat.',
    'com.twitter.',
    'com.reddit.',
    'tv.twitch.',
    'com.spotify.',
    'com.roblox.',
    'com.supercell.',
    'com.king.',
    'com.moonactive.',
    'com.epicgames.',
    'com.activision.',
    'com.ea.',
    'com.miniclip.',
    'com.playrix.',
    'com.google.android.apps.youtube',
    'com.netflix.',
    'com.discord.',
    'com.whatsapp.',
    'com.spotify.',
  ];

  static const Set<String> _knownExcludedExactPackages = {
    'com.example.genet_final',
    'com.android.settings',
    'com.android.systemui',
    'com.google.android.gms',
    'com.google.android.gsf',
    'com.google.android.gsf.login',
    'com.google.android.packageinstaller',
    'com.android.packageinstaller',
    'com.android.permissioncontroller',
    'com.google.android.permissioncontroller',
    'com.android.printspooler',
    'com.android.vending',
    'com.google.android.gm',
    'com.google.android.googlequicksearchbox',
    'com.google.android.projection.gearhead',
    'com.google.android.safetycore',
    'com.google.android.apps.maps',
    'com.waze',
    'com.google.android.apps.photos',
    'com.android.dialer',
    'com.google.android.dialer',
    'com.android.contacts',
    'com.google.android.contacts',
    'com.google.android.calculator',
    'com.android.calculator2',
    'com.google.android.calendar',
    'com.google.android.deskclock',
    'com.sec.android.app.myfiles',
    'com.google.android.apps.nbu.files',
    'com.google.android.apps.docs',
    'com.google.android.apps.docs.editors.docs',
    'com.google.android.apps.docs.editors.sheets',
    'com.google.android.apps.docs.editors.slides',
    'com.google.android.apps.docs.editors.drive',
    'com.microsoft.office.word',
    'com.microsoft.office.excel',
    'com.microsoft.office.powerpoint',
  };

  static const List<String> _knownExcludedPackageTerms = [
    'inputmethod',
    'keyboard',
    'launcher',
    'documentsui',
    'filemanager',
    'filemanager',
    'packageinstaller',
    'permissioncontroller',
    'print',
    'updater',
    'service',
    'provider',
    'assistant',
    'devicecare',
    'devicepolicy',
    'verifier',
    'safetycore',
    'gearhead',
    'androidauto',
  ];

  static const List<String> _knownExcludedNameTerms = [
    'gmail',
    'mail',
    'maps',
    'waze',
    'phone',
    'contacts',
    'camera',
    'gallery',
    'photos',
    'files',
    'settings',
    'clock',
    'calculator',
    'calendar',
    'android auto',
    'key verifier',
    'safetycore',
    'launcher',
    'keyboard',
    'play store',
    'google app',
    'assistant',
    'drive',
    'docs',
    'sheets',
    'slides',
    'word',
    'excel',
    'powerpoint',
    'maps go',
    'google maps',
    'my files',
  ];

  static const List<String> _knownRelevantNameTerms = [
    'whatsapp',
    'instagram',
    'facebook',
    'messenger',
    'telegram',
    'snapchat',
    'tiktok',
    'discord',
    'twitter',
    'threads',
    'reddit',
    'youtube',
    'netflix',
    'spotify',
    'twitch',
    'disney',
    'prime video',
    'roblox',
    'brawl stars',
    'pubg',
    'fortnite',
    'clash of clans',
  ];

  static const Set<String> _relevantCategories = {
    'game',
    'social',
    'audio',
    'video',
  };

  static const Set<String> _storeInstallerPackages = {
    'com.android.vending',
    'com.sec.android.app.samsungapps',
    'com.amazon.venezia',
    'com.huawei.appmarket',
    'com.xiaomi.market',
    'com.oppo.market',
    'com.heytap.market',
    'com.transsion.phoenix',
  };

  static const List<String> _auditPackages = [
    'youtube',
    'instagram',
    'tiktok',
    'chrome',
    'whatsapp',
    'spotify',
    'netflix',
  ];

  /// WebView / Trichrome — not a standalone browser for parental listing.
  static const Set<String> _webViewEnginePackages = {
    'com.google.android.webview',
    'com.android.webview',
    'com.google.android.trichromelibrary',
  };

  static const Set<String> _knownBrowserExactPackages = {
    'com.android.chrome',
    'com.android.browser',
    'com.chrome.beta',
    'com.chrome.dev',
    'com.chrome.canary',
    'com.google.android.apps.chrome',
    'org.mozilla.firefox',
    'org.mozilla.fennec',
    'org.mozilla.firefox_beta',
    'com.opera.browser',
    'com.opera.mini.native',
    'com.opera.gx',
    'com.microsoft.emmx',
    'com.sec.android.app.sbrowser',
    'com.brave.browser',
    'com.duckduckgo.mobile.android',
    'org.torproject.torbrowser',
    'com.vivaldi.browser',
    'com.kiwibrowser.browser',
    'com.yandex.browser',
    'com.uc.browser.en',
    'com.ucmobile.intl',
    'com.ucmobile.lite',
    'com.ucmobile.x86',
    'com.qwant.mobilenext',
    'com.ecosia.android',
    'mark.via.gp',
    'com.apus.browser',
    'com.cake.browser',
    'com.stoutner.privacybrowser.standard',
    'org.bromite.bromite',
    'pure.lite.browser',
    'com.pure.browser.plus',
    'com.huawei.browser',
    'com.huawei.android.browser',
    'com.mi.global.browser',
    'com.heytap.browser',
    'com.coloros.browser',
    'com.oneplus.browser',
    'com.vivo.browser',
    'com.oplus.browser',
  };

  static const List<String> _knownBrowserPackagePrefixes = [
    'com.chrome.',
    'org.mozilla.',
    'com.opera.',
    'com.microsoft.emmx',
    'com.vivaldi.',
    'com.brave.',
    'com.duckduckgo.',
    'com.kiwibrowser',
    'com.yandex.browser',
    'com.sec.android.app.sbrowser',
    'com.huawei.browser',
  ];

  /// Default SMS/MMS UIs parents often want to manage alongside chat apps.
  static const Set<String> _stockSmsUiExactPackages = {
    'com.google.android.apps.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
  };

  static bool isLikelyBrowserPackage(String packageLower) {
    if (_webViewEnginePackages.contains(packageLower)) return false;
    for (final id in _knownBrowserExactPackages) {
      if (id.toLowerCase() == packageLower) return true;
    }
    return _knownBrowserPackagePrefixes.any(packageLower.startsWith);
  }

  static bool isStockSmsUiPackage(String packageLower) {
    return _stockSmsUiExactPackages.contains(packageLower);
  }

  static InstalledApp? fromNativeMap(Map<String, dynamic> map) {
    final packageName = (map['package'] as String? ?? '').trim();
    if (packageName.isEmpty) return null;
    final appName = (map['name'] as String? ?? '').trim();
    return InstalledApp(
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      category: (map['category'] as String? ?? '').trim().toLowerCase(),
      isUnknownCategory: map['isUnknownCategory'] == true,
      versionName: (map['versionName'] as String? ?? '').trim(),
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      installerPackage: (map['installerPackage'] as String? ?? '').trim(),
      installedTime: (map['installedTime'] as num?)?.toInt(),
      updatedTime: (map['updatedTime'] as num?)?.toInt(),
      lastSeenAt:
          (map['lastSeenAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  static InstalledApp? fromBackendMap(Map<String, dynamic> map) {
    final packageName = (map['packageName'] as String? ?? '').trim();
    if (packageName.isEmpty) return null;
    final appName = (map['appName'] as String? ?? '').trim();
    return InstalledApp(
      packageName: packageName,
      appName: appName.isEmpty ? packageName : appName,
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      category: (map['category'] as String? ?? '').trim().toLowerCase(),
      isUnknownCategory: map['isUnknownCategory'] == true,
      versionName: (map['versionName'] as String? ?? '').trim(),
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      installerPackage: (map['installerPackage'] as String? ?? '').trim(),
      installedTime: (map['installedTime'] as num?)?.toInt(),
      updatedTime: (map['updatedTime'] as num?)?.toInt(),
      lastSeenAt:
          (map['lastSeenAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toBackendMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'isSystemApp': isSystemApp,
      'isLaunchable': isLaunchable,
      'category': category,
      'isUnknownCategory': isUnknownCategory,
      'versionName': versionName,
      'versionCode': versionCode,
      'installerPackage': installerPackage,
      'installedTime': installedTime,
      'updatedTime': updatedTime,
      'lastSeenAt': lastSeenAt,
    };
  }

  String fingerprintPart() =>
      '$packageName|$appName|$isSystemApp|$isLaunchable|$category|$isUnknownCategory|$versionName|$versionCode|$installerPackage|${installedTime ?? 0}|${updatedTime ?? 0}';

  bool get installedFromStore {
    return _storeInstallerPackages.contains(installerPackage.toLowerCase());
  }

  bool get clearlyExcluded {
    final packageLower = packageName.toLowerCase();
    final nameLower = appName.toLowerCase();
    if (_knownExcludedExactPackages.contains(packageLower)) return true;
    if (_knownExcludedPackageTerms.any(packageLower.contains)) return true;
    if (_knownExcludedNameTerms.any(nameLower.contains)) return true;
    return false;
  }

  bool get clearlyIncluded {
    final packageLower = packageName.toLowerCase();
    final nameLower = appName.toLowerCase();
    if (_knownRelevantExactPackages.contains(packageLower)) return true;
    if (_knownRelevantPackagePrefixes.any(packageLower.startsWith)) return true;
    if (_knownRelevantNameTerms.any(nameLower.contains)) return true;
    return false;
  }

  bool get excludedBySystemMetadata {
    if (!isLaunchable) return true;
    final p = packageName.toLowerCase();
    if (_webViewEnginePackages.contains(p)) return true;
    if (isLikelyBrowserPackage(p)) return false;
    if (isStockSmsUiPackage(p)) return false;
    if (isSystemApp) return true;
    return false;
  }

  bool get relevantByCategory {
    return _relevantCategories.contains(category);
  }

  InstalledApp copyWith({
    String? packageName,
    String? appName,
    bool? isSystemApp,
    bool? isLaunchable,
    String? category,
    bool? isUnknownCategory,
    String? versionName,
    int? versionCode,
    String? installerPackage,
    int? installedTime,
    int? updatedTime,
    int? lastSeenAt,
  }) {
    return InstalledApp(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      isLaunchable: isLaunchable ?? this.isLaunchable,
      category: category ?? this.category,
      isUnknownCategory: isUnknownCategory ?? this.isUnknownCategory,
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      installerPackage: installerPackage ?? this.installerPackage,
      installedTime: installedTime ?? this.installedTime,
      updatedTime: updatedTime ?? this.updatedTime,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  bool isRelevantForParent() {
    if (!isLaunchable) return false;
    final p = packageName.toLowerCase();
    if (_webViewEnginePackages.contains(p)) return false;
    if (isLikelyBrowserPackage(p)) return true;
    if (isStockSmsUiPackage(p)) return true;

    if (excludedBySystemMetadata) return false;
    if (clearlyExcluded) return false;
    if (relevantByCategory) return true;
    if (clearlyIncluded) return true;
    return false;
  }

  bool get relevantForParent {
    return isRelevantForParent();
  }

  bool get shouldAuditClassification {
    final packageLower = packageName.toLowerCase();
    return _auditPackages.any(packageLower.contains);
  }

  static List<InstalledApp> fromNativeList(
    List<Map<String, dynamic>> raw,
  ) {
    final byPackage = <String, InstalledApp>{};
    for (final item in raw) {
      final app = InstalledApp.fromNativeMap(item);
      if (app == null) continue;
      byPackage[app.packageName] = app;
    }
    final list = byPackage.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }

  static List<InstalledApp> classifyAppsForParentalControl(
    List<InstalledApp> rawApps,
  ) {
    final byPackage = <String, InstalledApp>{};
    for (final app in rawApps) {
      if (!app.isRelevantForParent()) {
        continue;
      }
      byPackage[app.packageName] = app;
    }
    final list = byPackage.values.toList()
      ..sort((a, b) {
        final byName = a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
        if (byName != 0) return byName;
        return a.packageName.compareTo(b.packageName);
      });
    return list;
  }
}

class InstalledAppsInventory {
  const InstalledAppsInventory({
    required this.apps,
    required this.appCount,
    required this.rawInstalledAppCount,
    required this.appsHash,
    required this.lastSyncAt,
    required this.lastSyncTrigger,
  });

  final List<InstalledApp> apps;
  final int appCount;
  final int rawInstalledAppCount;
  final String appsHash;
  final int? lastSyncAt;
  final String lastSyncTrigger;
}
