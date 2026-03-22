import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(theme, 'Connection', [
            _infoTile(theme, 'API Endpoint', 'http://localhost:9090'),
            _infoTile(theme, 'WebSocket', 'ws://localhost:9090/ws'),
          ]),
          const SizedBox(height: 16),
          _section(theme, 'Appearance', [
            const ListTile(
              title: Text('Theme'),
              subtitle: Text('Follow system'),
              trailing: Icon(Icons.brightness_auto),
              dense: true,
            ),
          ]),
          const SizedBox(height: 16),
          _section(theme, 'About', [
            _infoTile(theme, 'Version', '1.0.0-dev'),
            _infoTile(theme, 'Engine', 'Swift/NIO + KnotWebService'),
          ]),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.hintColor)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(children: children),
      ),
    ],
  );

  Widget _infoTile(ThemeData theme, String label, String value) => ListTile(
    title: Text(label),
    trailing: Text(value, style: TextStyle(color: theme.hintColor, fontSize: 13)),
    dense: true,
  );
}
