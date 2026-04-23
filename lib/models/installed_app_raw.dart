/// Raw row from native [genet/installed_apps] scan (Step 1 — no Flutter filtering).
class InstalledAppRaw {
  const InstalledAppRaw({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
    required this.category,
    required this.isLaunchable,
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
  /// Play store category string from [ApplicationInfo.category], or `"unknown"`.
  final String category;
  final bool isLaunchable;

  final String versionName;
  final int versionCode;
  final String installerPackage;
  final int? installedTime;
  final int? updatedTime;
  final int lastSeenAt;

  static InstalledAppRaw? tryParse(Map<String, dynamic> map) {
    final packageName = (map['packageName'] as String? ?? '').trim();
    if (packageName.isEmpty) return null;
    final name = (map['appName'] as String? ?? '').trim();
    final appName = name.isEmpty ? packageName : name;
    final category = (map['category'] as String? ?? 'unknown').trim();
    return InstalledAppRaw(
      packageName: packageName,
      appName: appName,
      isSystemApp: map['isSystemApp'] == true,
      isLaunchable: map['isLaunchable'] != false,
      category: category.isEmpty ? 'unknown' : category,
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

  /// Shape expected by [InstalledApp.fromNativeMap] (existing sync / classification).
  Map<String, dynamic> toLegacyNativeMap() {
    return {
      'package': packageName,
      'name': appName,
      'isSystemApp': isSystemApp,
      'isLaunchable': isLaunchable,
      'category': category.toLowerCase(),
      'versionName': versionName,
      'versionCode': versionCode,
      'installerPackage': installerPackage,
      'installedTime': installedTime,
      'updatedTime': updatedTime,
      'lastSeenAt': lastSeenAt,
    };
  }
}
