import '../core/genet_vpn.dart';

/// Values written under Firestore `vpnStatus.state` (child health reporting).
abstract final class ChildVpnReportState {
  static const active = 'active';
  static const inactive = 'inactive';
  static const permissionRequired = 'permission_required';
  static const unknown = 'unknown';
}

/// Maps native [GenetVpn.getVpnProtectionStatus] labels to parent-alert states.
String mapProtectionStatusToVpnReportState(String? protectionStatus) {
  if (protectionStatus == null || protectionStatus.isEmpty) {
    return ChildVpnReportState.unknown;
  }
  switch (protectionStatus) {
    case GenetVpn.protectionProtected:
      return ChildVpnReportState.active;
    case GenetVpn.protectionVpnInactive:
      return ChildVpnReportState.inactive;
    case GenetVpn.protectionVpnRemoved:
      return ChildVpnReportState.permissionRequired;
    default:
      return ChildVpnReportState.unknown;
  }
}

/// Per product rules: only [ChildVpnReportState.active] means protection not lost.
bool vpnReportProtectionLost(String state) => state != ChildVpnReportState.active;

/// Dedupe Firestore writes: report when state changes, or [minQuietDuration] elapsed.
bool shouldReportChildVpnStatus({
  required String nextState,
  required String? lastReportedState,
  required DateTime now,
  required DateTime? lastReportedAt,
  Duration minQuietDuration = const Duration(seconds: 60),
}) {
  if (lastReportedState != nextState) return true;
  if (lastReportedAt == null) return true;
  return now.difference(lastReportedAt) >= minQuietDuration;
}
