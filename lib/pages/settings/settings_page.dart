import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/cert_controller.dart';
import '../../theme/app_theme.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeCtrl = Get.find<ThemeController>();
    final certCtrl = Get.find<CertController>();

    return ListView(
      padding: EdgeInsets.all(AppTheme.spacing.lg),
      children: [
        // ── Appearance ──
        _section(theme, 'settings.appearance'.tr, [
          Obx(() => ListTile(
            title: Text('settings.theme'.tr),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode, size: 16),
                  label: Text('settings.light'.tr),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto, size: 16),
                  label: Text('settings.follow_system'.tr),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode, size: 16),
                  label: Text('settings.dark'.tr),
                ),
              ],
              selected: {themeCtrl.themeMode.value},
              onSelectionChanged: (modes) {
                themeCtrl.setThemeMode(modes.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            dense: true,
          )),
        ]),

        SizedBox(height: AppTheme.spacing.lg),

        // ── HTTPS Certificate ──
        _section(theme, 'settings.certificate'.tr, [
          Obx(() {
            final status = certCtrl.status.value;
            final (icon, color, label) = switch (status) {
              CertStatus.trusted => (Icons.verified, const Color(0xFF34C759), 'settings.cert_trusted'.tr),
              CertStatus.installed => (Icons.warning_amber, const Color(0xFFFF9F0A), 'settings.cert_installed'.tr),
              CertStatus.none => (Icons.cancel_outlined, const Color(0xFFFF3B30), 'settings.cert_not_installed'.tr),
              CertStatus.checking => (Icons.hourglass_empty, theme.hintColor, 'settings.cert_checking'.tr),
            };

            return ListTile(
              leading: Icon(icon, color: color, size: 20),
              title: Text('settings.ca_certificate'.tr),
              subtitle: Text(label, style: TextStyle(fontSize: AppTheme.fontSize.xs, color: color)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status != CertStatus.trusted && status != CertStatus.checking)
                    TextButton.icon(
                      onPressed: () => _installCert(context, certCtrl),
                      icon: const Icon(Icons.security, size: 14),
                      label: Text('settings.install'.tr),
                    ),
                  if (status == CertStatus.trusted)
                    const Icon(Icons.check_circle, color: Color(0xFF34C759), size: 18),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _exportCert(context, certCtrl),
                    icon: const Icon(Icons.download, size: 14),
                    label: Text('settings.export'.tr),
                  ),
                ],
              ),
              dense: true,
            );
          }),
          ListTile(
            title: Text('settings.cert_hint'.tr,
                style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor)),
            dense: true,
          ),
        ]),

        SizedBox(height: AppTheme.spacing.lg),

        // ── Connection ──
        _section(theme, 'settings.connection'.tr, [
          _infoTile(theme, 'settings.api_endpoint'.tr, 'http://localhost:9090'),
          _infoTile(theme, 'settings.websocket'.tr, 'ws://localhost:9090/ws'),
        ]),

        SizedBox(height: AppTheme.spacing.lg),

        // ── About ──
        _section(theme, 'settings.about'.tr, [
          _infoTile(theme, 'settings.version'.tr, '1.0.0-dev'),
          _infoTile(theme, 'settings.engine'.tr, 'Swift/NIO + KnotWebService'),
        ]),
      ],
    );
  }

  Future<void> _installCert(BuildContext context, CertController certCtrl) async {
    final success = await certCtrl.install();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'settings.cert_install_success'.tr : 'settings.cert_install_cancelled'.tr),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _exportCert(BuildContext context, CertController certCtrl) async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final savePath = '$home/Desktop/KnotCA.der';
    final success = await certCtrl.exportToFile(savePath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'settings.cert_exported'.trParams({'path': savePath})
          : 'settings.cert_export_failed'.tr),
      duration: const Duration(seconds: 3),
    ));
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
