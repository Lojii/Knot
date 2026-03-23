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
          height: AppTheme.toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text('Map Remote', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppTheme.spacingSM),
              Obx(() => Text(
                '${toolsCtrl.mapRemoteRules.length} rules',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeSM,
                  color: theme.hintColor,
                ),
              )),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showRuleDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Rule'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
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
                    const SizedBox(height: AppTheme.spacingSM),
                    Text(
                      'No Map Remote rules',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSizeMD,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      'Add a rule to redirect requests to a different server',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSizeSM,
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSM),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLG,
          vertical: AppTheme.spacingSM,
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
            const SizedBox(width: AppTheme.spacingSM),
            // Pattern and replacement
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.matchPattern,
                    style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD).copyWith(
                      color: rule.enabled ? null : theme.hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_forward, size: 12, color: theme.hintColor),
                      const SizedBox(width: AppTheme.spacingXS),
                      Expanded(
                        child: Text(
                          rule.replacementSummary,
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSM,
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
      title: Text(isEditing ? 'Edit Rule' : 'Add Map Remote Rule'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Match Pattern',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSM,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            TextField(
              controller: _patternCtrl,
              style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD),
              decoration: InputDecoration(
                hintText: 'https://api.example.com/v1/*',
                hintStyle: TextStyle(
                  color: theme.hintColor,
                  fontSize: AppTheme.fontSizeSM,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: AppTheme.spacingSM,
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: AppTheme.spacingLG),
            Text(
              'Replace With (empty = keep original)',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSM,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSM),
            _field('Scheme', _schemeCtrl, 'https'),
            const SizedBox(height: AppTheme.spacingSM),
            _field('Host', _hostCtrl, 'localhost'),
            const SizedBox(height: AppTheme.spacingSM),
            Row(
              children: [
                Expanded(child: _field('Port', _portCtrl, '8080')),
                const SizedBox(width: AppTheme.spacingSM),
                Expanded(child: _field('Path', _pathCtrl, '/api/v2/*')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: AppTheme.fontSizeXS, color: theme.hintColor)),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: TextField(
            controller: ctrl,
            style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeSM),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: AppTheme.fontSizeXS,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSM,
                vertical: AppTheme.spacingXS,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
