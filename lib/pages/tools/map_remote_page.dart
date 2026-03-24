import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tools_controller.dart';
import '../../theme/app_theme.dart';

/// Inline panel for managing Map Remote rules.
/// Redirects matching requests to a different scheme/host/port/path.
class MapRemotePanel extends StatelessWidget {
  const MapRemotePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final toolsCtrl = Get.find<ToolsController>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Toolbar
        Container(
          height: AppTheme.sizing.toolbarHeight,
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.lg),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text('Map Remote', style: theme.textTheme.titleSmall),
              SizedBox(width: AppTheme.spacing.sm),
              Obx(() => Text(
                '${toolsCtrl.mapRemoteRules.length} rules',
                style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  color: theme.hintColor,
                ),
              )),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showRuleDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: Text('action.add_rule'.tr),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Rule list
        Expanded(
          child: Obx(() {
            final rules = toolsCtrl.mapRemoteRules;
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alt_route, size: 48, color: theme.hintColor),
                    SizedBox(height: AppTheme.spacing.sm),
                    Text(
                      'empty.no_map_remote'.tr,
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSize.md,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacing.xs),
                    Text(
                      'empty.no_map_remote_desc'.tr,
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSize.sm,
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacing.sm),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final rule = rules[i];
                return _RuleRow(
                  rule: rule,
                  onToggle: () => toolsCtrl.toggleMapRemoteRule(i),
                  onEdit: () => _showRuleDialog(context, index: i, rule: rule),
                  onDelete: () => toolsCtrl.removeMapRemoteRule(i),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showRuleDialog(BuildContext context, {int? index, MapRemoteRule? rule}) {
    showDialog(
      context: context,
      builder: (ctx) => _MapRemoteRuleDialog(index: index, rule: rule),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final MapRemoteRule rule;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacing.lg,
          vertical: AppTheme.spacing.sm,
        ),
        child: Row(
          children: [
            // Enable toggle
            SizedBox(
              width: 40,
              child: Switch(
                value: rule.enabled,
                onChanged: (_) => onToggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            SizedBox(width: AppTheme.spacing.sm),
            // Pattern and replacement
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.matchPattern,
                    style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md).copyWith(
                      color: rule.enabled ? null : theme.hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_forward, size: 12, color: theme.hintColor),
                      SizedBox(width: AppTheme.spacing.xs),
                      Expanded(
                        child: Text(
                          rule.replacementSummary,
                          style: TextStyle(
                            fontSize: AppTheme.fontSize.sm,
                            color: theme.hintColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Delete
            IconButton(
              icon: Icon(Icons.delete_outline, size: 16, color: theme.hintColor),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapRemoteRuleDialog extends StatefulWidget {
  final int? index;
  final MapRemoteRule? rule;

  const _MapRemoteRuleDialog({this.index, this.rule});

  @override
  State<_MapRemoteRuleDialog> createState() => _MapRemoteRuleDialogState();
}

class _MapRemoteRuleDialogState extends State<_MapRemoteRuleDialog> {
  late final TextEditingController _patternCtrl;
  late final TextEditingController _schemeCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _pathCtrl;

  bool get isEditing => widget.index != null;

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.rule?.matchPattern ?? '');
    _schemeCtrl = TextEditingController(text: widget.rule?.replaceScheme ?? '');
    _hostCtrl = TextEditingController(text: widget.rule?.replaceHost ?? '');
    _portCtrl = TextEditingController(
      text: widget.rule?.replacePort?.toString() ?? '',
    );
    _pathCtrl = TextEditingController(text: widget.rule?.replacePath ?? '');
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _schemeCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) return;

    final rule = MapRemoteRule(
      enabled: widget.rule?.enabled ?? true,
      matchPattern: pattern,
      replaceScheme: _schemeCtrl.text.trim().isEmpty ? null : _schemeCtrl.text.trim(),
      replaceHost: _hostCtrl.text.trim().isEmpty ? null : _hostCtrl.text.trim(),
      replacePort: int.tryParse(_portCtrl.text.trim()),
      replacePath: _pathCtrl.text.trim().isEmpty ? null : _pathCtrl.text.trim(),
    );

    final toolsCtrl = Get.find<ToolsController>();
    if (isEditing) {
      toolsCtrl.updateMapRemoteRule(widget.index!, rule);
    } else {
      toolsCtrl.addMapRemoteRule(rule);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEditing ? 'map_remote.edit_rule'.tr : 'map_remote.add_rule'.tr),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'map_remote.match_pattern'.tr,
              style: TextStyle(
                fontSize: AppTheme.fontSize.sm,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            SizedBox(height: AppTheme.spacing.xs),
            TextField(
              controller: _patternCtrl,
              style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md),
              decoration: InputDecoration(
                hintText: 'https://api.example.com/v1/*',
                hintStyle: TextStyle(
                  color: theme.hintColor,
                  fontSize: AppTheme.fontSize.sm,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.sm,
                  vertical: AppTheme.spacing.sm,
                ),
              ),
              autofocus: true,
            ),
            SizedBox(height: AppTheme.spacing.lg),
            Text(
              'map_remote.replace_with'.tr,
              style: TextStyle(
                fontSize: AppTheme.fontSize.sm,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            SizedBox(height: AppTheme.spacing.sm),
            _field('map_remote.scheme'.tr, _schemeCtrl, 'https'),
            SizedBox(height: AppTheme.spacing.sm),
            _field('map_remote.host'.tr, _hostCtrl, 'localhost'),
            SizedBox(height: AppTheme.spacing.sm),
            Row(
              children: [
                Expanded(child: _field('map_remote.port'.tr, _portCtrl, '8080')),
                SizedBox(width: AppTheme.spacing.sm),
                Expanded(child: _field('map_remote.path'.tr, _pathCtrl, '/api/v2/*')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('action.cancel'.tr),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text('action.save'.tr),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: AppTheme.fontSize.xs, color: theme.hintColor)),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: TextField(
            controller: ctrl,
            style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.sm),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: AppTheme.fontSize.xs,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius.sm),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm,
                vertical: AppTheme.spacing.xs,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
