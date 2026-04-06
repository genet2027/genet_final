/// Native package add/remove forwarded on [genet/installed_apps] as [onPackageChanged].
class PackageChangeEvent {
  const PackageChangeEvent({
    required this.packageName,
    required this.action,
  });

  final String packageName;
  /// `"added"` | `"removed"`
  final String action;

  static PackageChangeEvent? tryParse(Map<String, dynamic> map) {
    final pkg = (map['packageName'] as String? ?? '').trim();
    if (pkg.isEmpty) return null;
    final action = (map['action'] as String? ?? '').trim().toLowerCase();
    if (action != 'added' && action != 'removed') return null;
    return PackageChangeEvent(packageName: pkg, action: action);
  }
}
