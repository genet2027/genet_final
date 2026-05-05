import 'package:flutter_test/flutter_test.dart';
import 'package:genet_final/repositories/child_vpn_health_parse.dart';
import 'package:genet_final/repositories/child_vpn_status_report.dart';

void main() {
  final t0 = DateTime.utc(2026, 6, 15, 12, 0, 0);

  group('parseChildVpnHealth', () {
    test('active fresh -> green protected', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {
          'state': ChildVpnReportState.active,
          'protectionLost': false,
          'lastCheckedAt': t0.subtract(const Duration(seconds: 30)),
          'updatedBy': 'child',
        },
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.protected);
      expect(h.label, 'VPN protected');
      expect(h.isStale, false);
    });

    test('inactive with protectionLost -> red inactive', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {
          'state': ChildVpnReportState.inactive,
          'protectionLost': true,
          'lastCheckedAt': t0.subtract(const Duration(seconds: 10)),
        },
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.protectionLost);
      expect(h.label, 'VPN inactive');
    });

    test('permission_required without protectionLost -> orange path', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {
          'state': ChildVpnReportState.permissionRequired,
          'protectionLost': false,
          'lastCheckedAt': t0.subtract(const Duration(seconds: 5)),
        },
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.permissionRequired);
      expect(h.label, 'VPN permission needed');
    });

    test('missing map -> gray unknown', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: null,
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.unknown);
      expect(h.label, 'VPN status unknown');
    });

    test('active but older than 2 minutes -> stale gray', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {
          'state': ChildVpnReportState.active,
          'protectionLost': false,
          'lastCheckedAt': t0.subtract(const Duration(minutes: 3)),
        },
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.stale);
      expect(h.label, 'VPN status stale');
      expect(h.isStale, true);
    });

    test('exactly 2 minutes since check -> stale', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {
          'state': ChildVpnReportState.active,
          'protectionLost': false,
          'lastCheckedAt': t0.subtract(const Duration(minutes: 2)),
        },
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.stale);
    });

    test('legacy string does not crash -> unknown', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: 'on',
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.unknown);
      expect(h.label, 'VPN status unknown');
    });

    test('unexpected map shape: missing timestamp -> stale', () {
      final h = parseChildVpnHealth(
        vpnStatusRaw: {'unexpected': 1},
        now: t0,
      );
      expect(h.severity, ChildVpnHealthSeverity.stale);
      expect(h.label, 'VPN status stale');
    });
  });

  group('parseVpnTimelike', () {
    test('parses int as millis when large', () {
      final ms = DateTime.utc(2020, 1, 1).millisecondsSinceEpoch;
      final d = parseVpnTimelike(ms);
      expect(d, isNotNull);
      expect(d!.millisecondsSinceEpoch, ms);
    });

    test('parses int as unix seconds when small', () {
      const secs = 1577836800;
      final d = parseVpnTimelike(secs);
      expect(d, isNotNull);
      expect(d!.millisecondsSinceEpoch, secs * 1000);
    });
  });
}
