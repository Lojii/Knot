import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tools_controller.dart';
import '../../theme/app_theme.dart';

/// Inline panel for managing Map Local rules.
/// Serves matching requests with local file content instead of forwarding.
class MapLocalPanel extends StatelessWidget {
  const MapLocalPanel({super.key});

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
              Text('Map Local', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppTheme.spacingSM),
              Obx(() => Text(
                '${toolsCtrl.mapLocalRules.length} rules',
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
            final rules = toolsCtrl.mapLocalRules;
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: theme.hintColor),
                    const SizedBox(height: AppTheme.spacingSM),
                    Text(
                      'No Map Local rules',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSizeMD,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      'Add a rule to serve requests with local file content',
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
                  onToggle: () => toolsCtrl.toggleMapLocalRule(i),
                  onEdit: () => _showRuleDialog(context, index: i, rule: rule),
                  onDelete: () => toolsCtrl.removeMapLocalRule(i),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showRuleDialog(BuildContext context, {int? index, MapLocalRule? rule}) {
    showDialog(
      context: context,
      builder: (ctx) => _MapLocalRuleDialog(index: index, rule: rule),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final MapLocalRule rule;
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
            // Pattern and file path
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (rule.method != null && rule.method!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: theme.colorScheme.primary.withAlpha(26),
                          ),
                          child: Text(
                            rule.method!,
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeXS,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingXS),
                      ],
                      Expanded(
                        child: Text(
                          rule.urlPattern,
                          style: AppTheme.monoStyle(context,
                                  fontSize: AppTheme.fontSizeMD)
                              .copyWith(
                            color: rule.enabled ? null : theme.hintColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: theme.hintColor.withAlpha(26),
                        ),
                        child: Text(
                          '${rule.statusCode}',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeXS,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingXS),
                      Icon(Icons.folder_outlined,
                          size: 12, color: theme.hintColor),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          rule.filePath.isEmpty
                              ? '(no file)'
                              : rule.filePath,
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
              icon: Icon(Icons.delete_outline,
                  size: 16, color: theme.hintColor),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLocalRuleDialog extends StatefulWidget {
  final int? index;
  final MapLocalRule? rule;

  const _MapLocalRuleDialog({this.index, this.rule});

  @override
  State<_MapLocalRuleDialog> createState() => _MapLocalRuleDialogState();
}

class _MapLocalRuleDialogState extends State<_MapLocalRuleDialog> {
  late final TextEditingController _patternCtrl;
  late final TextEditingController _statusCodeCtrl;
  late final TextEditingController _filePathCtrl;
  late final TextEditingController _headersCtrl;
  String _method = 'Any';

  static const _methods = ['Any', 'GET', 'POST', 'PUT', 'DELETE'];

  bool get isEditing => widget.index != null;

  @override
  void initState() {
    super.initState();
    _patternCtrl =
        TextEditingController(text: widget.rule?.urlPattern ?? '');
    _statusCodeCtrl = TextEditingController(
        text: '${widget.rule?.statusCode ?? 200}');
    _filePathCtrl =
        TextEditingController(text: widget.rule?.filePath ?? '');
    _headersCtrl =
        TextEditingController(text: widget.rule?.responseHeaders ?? '');
    _method = widget.rule?.method ?? 'Any';
    if (_method.isEmpty) _method = 'Any';
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _statusCodeCtrl.dispose();
    _filePathCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) return;

    final rule = MapLocalRule(
      enabled: widget.rule?.enabled ?? true,
      urlPattern: pattern,
      method: _method == 'Any' ? null : _method,
      statusCode: int.tryParse(_statusCodeCtrl.text.trim()) ?? 200,
      filePath: _filePathCtrl.text.trim(),
      responseHeaders: _headersCtrl.text.trim(),
    );

    final toolsCtrl = Get.find<ToolsController>();
    if (isEditing) {
      toolsCtrl.updateMapLocalRule(widget.index!, rule);
    } else {
      toolsCtrl.addMapLocalRule(rule);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEditing ? 'Edit Rule' : 'Add Map Local Rule'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'URL Pattern',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSM,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            TextField(
              controller: _patternCtrl,
              style: AppTheme.monoStyle(context,
                  fontSize: AppTheme.fontSizeMD),
              decoration: InputDecoration(
                hintText: '*.api.com/v1/*',
                hintStyle: TextStyle(
                  color: theme.hintColor,
                  fontSize: AppTheme.fontSizeSM,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSM),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingSM,
                  vertical: AppTheme.spacingSM,
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: AppTheme.spacingLG),
            // Method dropdown
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Method',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeXS,
                            color: theme.hintColor,
                          )),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 32,
                        child: DropdownButtonFormField<String>(
                          initialValue: _method,
                          items: _methods
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m,
                                        style: const TextStyle(
                                            fontSize:
                                                AppTheme.fontSizeSM)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _method = v ?? 'Any'),
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSM),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingSM,
                              vertical: AppTheme.spacingXS,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSM),
                Expanded(
                  child: _field(
                      'Status Code', _statusCodeCtrl, '200'),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSM),
            _field('Response File Path', _filePathCtrl,
                '/path/to/response.json'),
            const SizedBox(height: AppTheme.spacingSM),
            Text('Response Headers (JSON)',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeXS,
                  color: theme.hintColor,
                )),
            const SizedBox(height: 2),
            SizedBox(
              height: 64,
              child: TextField(
                controller: _headersCtrl,
                maxLines: 3,
                style: AppTheme.monoStyle(context,
                    fontSize: AppTheme.fontSizeSM),
                decoration: InputDecoration(
                  hintText: '{"Content-Type": "application/json"}',
                  hintStyle: TextStyle(
                    color: theme.hintColor,
                    fontSize: AppTheme.fontSizeXS,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSM),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSM,
                    vertical: AppTheme.spacingXS,
                  ),
                ),
              ),
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

  Widget _field(
      String label, TextEditingController ctrl, String hint) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: AppTheme.fontSizeXS,
                color: theme.hintColor)),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: TextField(
            controller: ctrl,
            style: AppTheme.monoStyle(context,
                fontSize: AppTheme.fontSizeSM),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: AppTheme.fontSizeXS,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusSM),
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
