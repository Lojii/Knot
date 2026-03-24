import 'package:flutter/material.dart';
import '../api/ws_client.dart';
import '../theme/app_theme.dart';

class ConnectionIndicator extends StatelessWidget {
  final WsStatus status;
  const ConnectionIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final (color, label) = switch (status) {
      WsStatus.connected => (themeColors.statusConnected, 'Connected'),
      WsStatus.connecting => (themeColors.statusConnecting, 'Connecting...'),
      WsStatus.disconnected => (themeColors.statusDisconnected, 'Disconnected'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: AppTheme.spacing.xs),
        Text(label, style: TextStyle(fontSize: AppTheme.fontSize.sm, color: color)),
      ],
    );
  }
}
