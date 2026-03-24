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
          height: AppTheme.sizing.toolbarHeight,
          padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.lg),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text('Map Local', style: theme.textTheme.titleSmall),
              SizedBox(width: AppTheme.spacing.sm),
              Obx(() => Text(
                '${toolsCtrl.mapLocalRules.length} rules',
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
            final rules = toolsCtrl.mapLocalRules;
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: theme.hintColor),
                    SizedBox(height: AppTheme.spacing.sm),
                    Text(
                      'empty.no_map_local'.tr,
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSize.md,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacing.xs),
                    Text(
                      'empty.no_map_local_desc'.tr,
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
                              fontSize: AppTheme.fontSize.xs,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: AppTheme.spacing.xs),
                      ],
                      Expanded(
                        child: Text(
                          rule.urlPattern,
                          style: AppTheme.monoStyle(context,
                                  fontSize: AppTheme.fontSize.md)
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
                            fontSize: AppTheme.fontSize.xs,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                      SizedBox(width: AppTheme.spacing.xs),
                      Icon(Icons.folder_outlined,
                          size: 12, color: theme.hintColor),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          rule.filePath.isEmpty
                              ? 'map_local.no_file'.tr
                              : rule.filePath,
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
      title: Text(isEditing ? 'map_local.edit_rule'.tr : 'map_local.add_rule'.tr),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'map_local.url_pattern'.tr,
              style: TextStyle(
                fontSize: AppTheme.fontSize.sm,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
            SizedBox(height: AppTheme.spacing.xs),
            TextField(
              controller: _patternCtrl,
              style: AppTheme.monoStyle(context,
                  fontSize: AppTheme.fontSize.md),
              decoration: InputDecoration(
                hintText: '*.api.com/v1/*',
                hintStyle: TextStyle(
                  color: theme.hintColor,
                  fontSize: AppTheme.fontSize.sm,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.radius.sm),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.sm,
                  vertical: AppTheme.spacing.sm,
                ),
              ),
              autofocus: true,
            ),
            SizedBox(height: AppTheme.spacing.lg),
            // Method dropdown
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('map_local.method'.tr,
                          style: TextStyle(
                            fontSize: AppTheme.fontSize.xs,
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
                                        style: TextStyle(
                                            fontSize:
                                                AppTheme.fontSize.sm)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _method = v ?? 'Any'),
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radius.sm),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing.sm,
                              vertical: AppTheme.spacing.xs,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppTheme.spacing.sm),
                Expanded(
                  child: _field(
                      'map_local.status_code'.tr, _statusCodeCtrl, '200'),
                ),
              ],
            ),
            SizedBox(height: AppTheme.spacing.sm),
            _field('map_local.response_file'.tr, _filePathCtrl,
                '/path/to/response.json'),
            SizedBox(height: AppTheme.spacing.sm),
            Text('map_local.response_headers'.tr,
                style: TextStyle(
                  fontSize: AppTheme.fontSize.xs,
                  color: theme.hintColor,
                )),
            const SizedBox(height: 2),
            SizedBox(
              height: 64,
              child: TextField(
                controller: _headersCtrl,
                maxLines: 3,
                style: AppTheme.monoStyle(context,
                    fontSize: AppTheme.fontSize.sm),
                decoration: InputDecoration(
                  hintText: '{"Content-Type": "application/json"}',
                  hintStyle: TextStyle(
                    color: theme.hintColor,
                    fontSize: AppTheme.fontSize.xs,
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radius.sm),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing.sm,
                    vertical: AppTheme.spacing.xs,
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
          child: Text('action.cancel'.tr),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text('action.save'.tr),
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
                fontSize: AppTheme.fontSize.xs,
                color: theme.hintColor)),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: TextField(
            controller: ctrl,
            style: AppTheme.monoStyle(context,
                fontSize: AppTheme.fontSize.sm),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: AppTheme.fontSize.xs,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppTheme.radius.sm),
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
