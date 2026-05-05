import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/core/genet_vpn.dart';
import 'package:genet_final/repositories/child_vpn_status_report.dart';

void main() {
  group('mapProtectionStatusToVpnReportState', () {
    test('protected -> active', () {
      expect(
        mapProtectionStatusToVpnReportState(GenetVpn.protectionProtected),
        ChildVpnReportState.active,
      );
    });

    test('inactive -> inactive', () {
      expect(
        mapProtectionStatusToVpnReportState(GenetVpn.protectionVpnInactive),
        ChildVpnReportState.inactive,
      );
    });

    test('removed -> permission_required', () {
      expect(
        mapProtectionStatusToVpnReportState(GenetVpn.protectionVpnRemoved),
        ChildVpnReportState.permissionRequired,
      );
    });

    test('null, empty, unexpected -> unknown', () {
      expect(mapProtectionStatusToVpnReportState(null), ChildVpnReportState.unknown);
      expect(mapProtectionStatusToVpnReportState(''), ChildVpnReportState.unknown);
      expect(mapProtectionStatusToVpnReportState('weird'), ChildVpnReportState.unknown);
    });
  });

  group('vpnReportProtectionLost', () {
    test('false only for active', () {
      expect(vpnReportProtectionLost(ChildVpnReportState.active), false);
      expect(vpnReportProtectionLost(ChildVpnReportState.inactive), true);
      expect(vpnReportProtectionLost(ChildVpnReportState.permissionRequired), true);
      expect(vpnReportProtectionLost(ChildVpnReportState.unknown), true);
    });
  });

  group('shouldReportChildVpnStatus', () {
    final t0 = DateTime.utc(2026, 4, 4, 12);

    test('always true when state changed', () {
      expect(
        shouldReportChildVpnStatus(
          nextState: ChildVpnReportState.inactive,
          lastReportedState: ChildVpnReportState.active,
          now: t0,
          lastReportedAt: t0,
        ),
        true,
      );
    });

    test('true when lastReportedAt is null (first heartbeat)', () {
      expect(
        shouldReportChildVpnStatus(
          nextState: ChildVpnReportState.active,
          lastReportedState: ChildVpnReportState.active,
          now: t0,
          lastReportedAt: null,
        ),
        true,
      );
    });

    test('false when same state and within 60s', () {
      expect(
        shouldReportChildVpnStatus(
          nextState: ChildVpnReportState.active,
          lastReportedState: ChildVpnReportState.active,
          now: t0.add(const Duration(seconds: 30)),
          lastReportedAt: t0,
        ),
        false,
      );
    });

    test('true when same state and >= 60s elapsed', () {
      expect(
        shouldReportChildVpnStatus(
          nextState: ChildVpnReportState.active,
          lastReportedState: ChildVpnReportState.active,
          now: t0.add(const Duration(seconds: 60)),
          lastReportedAt: t0,
        ),
        true,
      );
    });
  });
}
