import 'package:flutter/material.dart';
import '../api/ws_client.dart';

class ConnectionIndicator extends StatelessWidget {
  final WsStatus status;
  const ConnectionIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      WsStatus.connected => (Colors.green, 'Connected'),
      WsStatus.connecting => (Colors.orange, 'Connecting...'),
      WsStatus.disconnected => (Colors.red, 'Disconnected'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
