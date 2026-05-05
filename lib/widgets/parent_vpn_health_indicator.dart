import 'package:flutter/material.dart';

import '../repositories/child_vpn_health_parse.dart';

Color parentVpnHealthDotColor(ChildVpnHealthSeverity severity) {
  switch (severity) {
    case ChildVpnHealthSeverity.protected:
      return Colors.green;
    case ChildVpnHealthSeverity.protectionLost:
      return Colors.red;
    case ChildVpnHealthSeverity.permissionRequired:
      return Colors.orange.shade700;
    case ChildVpnHealthSeverity.unknown:
      return Colors.grey.shade600;
    case ChildVpnHealthSeverity.stale:
      return Colors.grey.shade600;
  }
}

/// Compact dot + primary label; optional second line for policy apply status only.
class ParentVpnHealthIndicator extends StatelessWidget {
  const ParentVpnHealthIndicator({
    super.key,
    required this.health,
    this.applyStatusLabel,
    this.compact = false,
  });

  final ChildVpnHealthParsed health;
  /// `vpnApplyStatus` (on/off/error) — secondary, not the health signal.
  final String? applyStatusLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dotColor = parentVpnHealthDotColor(health.severity);
    final children = <Widget>[
      Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              health.label,
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      if (applyStatusLabel != null && applyStatusLabel!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 18),
          child: Text(
            'מצב מדיניות: $applyStatusLabel',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: Colors.grey.shade600,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
