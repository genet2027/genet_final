import '../features/blocked_apps/blocked_package_matching.dart';
import 'extension_requests.dart';

/// מקור אמת נגזר לכל אפליקציה חסומה: מצב חסימה, הארכה, הרשאות ו־recovery.
/// לא מאחסן נתונים – מחשב מהנתונים הקיימים (רשימת חסימה, extension_requests, הרשאות).
class BlockedAppState {
  const BlockedAppState({
    required this.packageName,
    required this.isBlocked,
    required this.isTemporarilyApproved,
    required this.extensionEndTime,
    required this.canRequestExtension,
    required this.missingPermissions,
    required this.requiresPermissionRecovery,
  });

  final String packageName;
  final bool isBlocked;
  final bool isTemporarilyApproved;
  final int extensionEndTime;
  final bool canRequestExtension;
  final List<String> missingPermissions;
  final bool requiresPermissionRecovery;

  /// מחשב מצב אפליקציה אחת מהנתונים הקיימים.
  static BlockedAppState forPackage({
    required String packageName,
    required List<String> blockedPackages,
    required Map<String, int> approvedUntil,
    required List<String> missingPermissions,
    required List<ExtensionRequest> extensionRequests,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isBlocked = isPackageBlockedByRawList(packageName, blockedPackages);
    final until = maxApprovedUntilMsForPackage(packageName, approvedUntil);
    final hasPending = hasPendingExtensionForPackage(packageName, extensionRequests);
    final isTemporarilyApproved = isBlocked && until > now;
    final canRequestExtension = isBlocked && !hasPending;
    final requiresPermissionRecovery = isBlocked && !isTemporarilyApproved && missingPermissions.isNotEmpty;

    return BlockedAppState(
      packageName: packageName,
      isBlocked: isBlocked,
      isTemporarilyApproved: isTemporarilyApproved,
      extensionEndTime: until,
      canRequestExtension: canRequestExtension,
      missingPermissions: missingPermissions,
      requiresPermissionRecovery: requiresPermissionRecovery,
    );
  }
}
