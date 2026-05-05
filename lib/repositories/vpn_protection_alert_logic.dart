import 'child_vpn_status_report.dart';

/// Firestore `state` field for [vpn_protection_lost] alerts (inactive | permission_required | unknown).
String vpnProtectionLostAlertDocumentState(String reportedNextState) {
  switch (reportedNextState) {
    case ChildVpnReportState.inactive:
      return 'inactive';
    case ChildVpnReportState.permissionRequired:
      return 'permission_required';
    case ChildVpnReportState.unknown:
      return 'unknown';
    default:
      return 'unknown';
  }
}

/// Side effects to apply after a successful child `vpnStatus` write.
class VpnProtectionAlertDecision {
  const VpnProtectionAlertDecision._({
    required this.shouldCreate,
    required this.shouldResolve,
    this.createdAlertState,
  });

  final bool shouldCreate;
  final bool shouldResolve;

  /// When [shouldCreate]: value for alert doc `state`.
  final String? createdAlertState;

  static const VpnProtectionAlertDecision none = VpnProtectionAlertDecision._(
    shouldCreate: false,
    shouldResolve: false,
  );

  factory VpnProtectionAlertDecision.create({required String alertState}) {
    return VpnProtectionAlertDecision._(
      shouldCreate: true,
      shouldResolve: false,
      createdAlertState: alertState,
    );
  }

  static const VpnProtectionAlertDecision resolve = VpnProtectionAlertDecision._(
    shouldCreate: false,
    shouldResolve: true,
  );
}

/// Transition detection for VPN protection-lost alerts (unit-tested).
VpnProtectionAlertDecision evaluateVpnProtectionAlertTransition({
  required String? previousState,
  required bool? previousProtectionLost,
  required String nextState,
  required bool nextProtectionLost,
}) {
  final prevHealthy = previousState == ChildVpnReportState.active &&
      previousProtectionLost == false;
  final nextHealthy =
      nextState == ChildVpnReportState.active && nextProtectionLost == false;

  if (prevHealthy && nextProtectionLost) {
    return VpnProtectionAlertDecision.create(
      alertState: vpnProtectionLostAlertDocumentState(nextState),
    );
  }

  if (nextHealthy && previousState != null && !prevHealthy) {
    return VpnProtectionAlertDecision.resolve;
  }

  return VpnProtectionAlertDecision.none;
}
