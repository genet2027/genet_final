import '../../core/extension_requests.dart';

/// SYNC: each set must match [kFixedBlockableApps][i].packageNames in
/// [fixed_blockable_apps_catalog.dart] (same package IDs, same families).
const List<Set<String>> _kFixedCatalogPackageFamilies = [
  {'com.google.android.youtube'},
  {'com.facebook.katana', 'com.facebook.lite'},
  {'com.instagram.android'},
];

/// Single normalization for package IDs used in blocked-app policy (trim only).
String? normalizeBlockedPackageId(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

/// Sibling package IDs for [packageName] within a fixed-catalog family, or `{normalized}` alone.
Set<String> fixedCatalogAliasGroupForPackage(String? packageName) {
  final n = normalizeBlockedPackageId(packageName);
  if (n == null) return const <String>{};
  for (final family in _kFixedCatalogPackageFamilies) {
    if (family.contains(n)) {
      return Set<String>.from(family);
    }
  }
  return <String>{n};
}

/// All package IDs that count as blocked for matching, including fixed-catalog aliases
/// when any member of that family appears in [rawBlocked].
Set<String> effectiveBlockedPackageIds(Iterable<String> rawBlocked) {
  final normalized = <String>{};
  for (final r in rawBlocked) {
    final n = normalizeBlockedPackageId(r);
    if (n != null) normalized.add(n);
  }
  final out = Set<String>.from(normalized);
  for (final family in _kFixedCatalogPackageFamilies) {
    if (family.any(normalized.contains)) {
      out.addAll(family);
    }
  }
  return out;
}

/// Whether [packageName] is blocked by [rawBlocked], after normalization + catalog expansion.
bool isPackageBlockedByRawList(String? packageName, Iterable<String> rawBlocked) {
  final n = normalizeBlockedPackageId(packageName);
  if (n == null) return false;
  return effectiveBlockedPackageIds(rawBlocked).contains(n);
}

/// Max extension approved-until across [packageName] and fixed-catalog aliases.
int maxApprovedUntilMsForPackage(String? packageName, Map<String, int> approvedUntil) {
  var maxV = 0;
  for (final p in fixedCatalogAliasGroupForPackage(packageName)) {
    final v = approvedUntil[p] ?? 0;
    if (v > maxV) maxV = v;
  }
  return maxV;
}

bool hasPendingExtensionForPackage(
  String packageName,
  List<ExtensionRequest> extensionRequests,
) {
  final group = fixedCatalogAliasGroupForPackage(packageName);
  for (final r in extensionRequests) {
    final rp = normalizeBlockedPackageId(r.packageName);
    if (rp != null &&
        group.contains(rp) &&
        r.status == ExtensionRequestStatus.pending) {
      return true;
    }
  }
  return false;
}
