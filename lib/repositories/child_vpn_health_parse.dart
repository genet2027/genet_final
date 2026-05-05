import 'package:cloud_firestore/cloud_firestore.dart';

import 'child_vpn_status_report.dart';

/// Visual / semantic bucket for parent VPN health UI.
enum ChildVpnHealthSeverity {
  protected,
  protectionLost,
  permissionRequired,
  unknown,
  stale,
}

/// Parsed VPN health for parent UI (Firestore child doc `vpnStatus` map).
class ChildVpnHealthParsed {
  const ChildVpnHealthParsed({
    required this.severity,
    required this.label,
    required this.isStale,
    required this.rawState,
    required this.protectionLost,
  });

  final ChildVpnHealthSeverity severity;
  final String label;
  final bool isStale;

  /// Normalized state string when map was valid (`active`, …); null if missing/legacy.
  final String? rawState;

  /// From map when parseable.
  final bool protectionLost;
}

/// Best-effort parse of Firestore Timestamp / int millis / seconds / [DateTime].
DateTime? parseVpnTimelike(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is Timestamp) {
    try {
      return v.toDate();
    } catch (_) {
      return null;
    }
  }
  if (v is int) {
    final ms = v.abs() < 10000000000 ? v * 1000 : v;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
    } catch (_) {
      return null;
    }
  }
  if (v is num) {
    final i = v.toInt();
    final ms = i.abs() < 10000000000 ? i * 1000 : i;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
    } catch (_) {
      return null;
    }
  }
  try {
    final seconds = (v as dynamic).seconds;
    if (seconds is int) {
      final nanos = (v as dynamic).nanoseconds;
      final n = nanos is int ? nanos : 0;
      return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000 + n ~/ 1000000,
        isUtc: false,
      );
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic>? _asStringKeyedMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    try {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Defensive parse of child doc `vpnStatus` field (map or legacy string).
ChildVpnHealthParsed parseChildVpnHealth({
  required dynamic vpnStatusRaw,
  required DateTime now,
  Duration staleThreshold = const Duration(minutes: 2),
}) {
  if (vpnStatusRaw is String) {
    return const ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.unknown,
      label: 'VPN status unknown',
      isStale: false,
      rawState: null,
      protectionLost: true,
    );
  }

  final map = _asStringKeyedMap(vpnStatusRaw);
  if (map == null) {
    return const ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.unknown,
      label: 'VPN status unknown',
      isStale: false,
      rawState: null,
      protectionLost: true,
    );
  }

  final stateRaw = map['state'];
  final state = stateRaw is String ? stateRaw.trim().toLowerCase() : '';
  final protectionLost = map['protectionLost'] == true;

  final checkedAt = parseVpnTimelike(map['lastCheckedAt']);
  final bool isStale = checkedAt == null ||
      now.difference(checkedAt) >= staleThreshold;

  if (isStale) {
    return ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.stale,
      label: 'VPN status stale',
      isStale: true,
      rawState: state.isEmpty ? null : state,
      protectionLost: protectionLost,
    );
  }

  if (state == ChildVpnReportState.active && !protectionLost) {
    return ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.protected,
      label: 'VPN protected',
      isStale: false,
      rawState: state,
      protectionLost: false,
    );
  }

  if (protectionLost) {
    String label;
    switch (state) {
      case ChildVpnReportState.inactive:
        label = 'VPN inactive';
        break;
      case ChildVpnReportState.permissionRequired:
        label = 'VPN permission needed';
        break;
      default:
        label = 'VPN status unknown';
    }
    return ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.protectionLost,
      label: label,
      isStale: false,
      rawState: state.isEmpty ? null : state,
      protectionLost: true,
    );
  }

  if (state == ChildVpnReportState.permissionRequired) {
    return ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.permissionRequired,
      label: 'VPN permission needed',
      isStale: false,
      rawState: state,
      protectionLost: false,
    );
  }

  if (state == ChildVpnReportState.inactive) {
    return ChildVpnHealthParsed(
      severity: ChildVpnHealthSeverity.protectionLost,
      label: 'VPN inactive',
      isStale: false,
      rawState: state,
      protectionLost: false,
    );
  }

  return ChildVpnHealthParsed(
    severity: ChildVpnHealthSeverity.unknown,
    label: 'VPN status unknown',
    isStale: false,
    rawState: state.isEmpty ? null : state,
    protectionLost: protectionLost,
  );
}
