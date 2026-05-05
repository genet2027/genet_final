import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/repositories/child_vpn_status_report.dart';
import 'package:genet_final/repositories/vpn_protection_alert_logic.dart';

void main() {
  group('evaluateVpnProtectionAlertTransition', () {
    test('active healthy -> protection lost creates alert', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.active,
        previousProtectionLost: false,
        nextState: ChildVpnReportState.inactive,
        nextProtectionLost: true,
      );
      expect(d.shouldCreate, true);
      expect(d.shouldResolve, false);
      expect(d.createdAlertState, 'inactive');
    });

    test('permission_required lost maps alert state', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.active,
        previousProtectionLost: false,
        nextState: ChildVpnReportState.permissionRequired,
        nextProtectionLost: true,
      );
      expect(d.shouldCreate, true);
      expect(d.createdAlertState, 'permission_required');
    });

    test('no duplicate alert while staying in lost state', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.inactive,
        previousProtectionLost: true,
        nextState: ChildVpnReportState.inactive,
        nextProtectionLost: true,
      );
      expect(d.shouldCreate, false);
      expect(d.shouldResolve, false);
    });

    test('no create when previous was not healthy active', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.unknown,
        previousProtectionLost: true,
        nextState: ChildVpnReportState.inactive,
        nextProtectionLost: true,
      );
      expect(d.shouldCreate, false);
    });

    test('resolve when returning to active from lost', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.inactive,
        previousProtectionLost: true,
        nextState: ChildVpnReportState.active,
        nextProtectionLost: false,
      );
      expect(d.shouldResolve, true);
      expect(d.shouldCreate, false);
    });

    test('no resolve on first healthy report (no previous)', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: null,
        previousProtectionLost: null,
        nextState: ChildVpnReportState.active,
        nextProtectionLost: false,
      );
      expect(d.shouldResolve, false);
    });

    test('no resolve when staying healthy', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.active,
        previousProtectionLost: false,
        nextState: ChildVpnReportState.active,
        nextProtectionLost: false,
      );
      expect(d.shouldResolve, false);
      expect(d.shouldCreate, false);
    });

    test('unknown lost then active resolves', () {
      final d = evaluateVpnProtectionAlertTransition(
        previousState: ChildVpnReportState.unknown,
        previousProtectionLost: true,
        nextState: ChildVpnReportState.active,
        nextProtectionLost: false,
      );
      expect(d.shouldResolve, true);
    });
  });
}
