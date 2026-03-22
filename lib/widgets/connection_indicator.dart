import 'package:flutter/material.dart';
import '../api/ws_client.dart';
import '../theme/app_theme.dart';

class ConnectionIndicator extends StatelessWidget {
  final WsStatus status;
  const ConnectionIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected => (AppTheme.statusConnected, 'Connected'),
      WsStatus.connecting => (AppTheme.statusConnecting, 'Connecting...'),
      WsStatus.disconnected => (AppTheme.statusDisconnected, 'Disconnected'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppTheme.spacingXS),
        Text(label, style: TextStyle(fontSize: AppTheme.fontSizeSM, color: color)),
      ],
    );
  }
}
