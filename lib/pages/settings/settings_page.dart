import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Embeddable settings panel — displayed inside the main layout
/// when the user clicks the Settings button in GlobalBar.
/// No Scaffold or AppBar — GlobalBar stays on top.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.all(AppTheme.spacing.lg),
      children: [
        _section(theme, 'Connection', [
          _infoTile(theme, 'API Endpoint', 'http://localhost:9090'),
          _infoTile(theme, 'WebSocket', 'ws://localhost:9090/ws'),
        ]),
        SizedBox(height: AppTheme.spacing.lg),
        _section(theme, 'Appearance', [
          const ListTile(
            title: Text('Theme'),
            subtitle: Text('Follow system'),
            trailing: Icon(Icons.brightness_auto),
            dense: true,
          ),
        ]),
        SizedBox(height: AppTheme.spacing.lg),
        _section(theme, 'About', [
          _infoTile(theme, 'Version', '1.0.0-dev'),
          _infoTile(theme, 'Engine', 'Swift/NIO + KnotWebService'),
        ]),
      ],
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: AppTheme.fontSize.lg, fontWeight: FontWeight.bold, color: theme.hintColor)),
      SizedBox(height: AppTheme.spacing.sm),
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radius.lg),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(children: children),
      ),
    ],
  );

  Widget _infoTile(ThemeData theme, String label, String value) => ListTile(
    title: Text(label),
    trailing: Text(value, style: TextStyle(color: theme.hintColor, fontSize: AppTheme.fontSize.lg)),
    dense: true,
  );
}
