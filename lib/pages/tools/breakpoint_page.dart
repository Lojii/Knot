import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/tools_controller.dart';
import '../../theme/app_theme.dart';

/// Inline panel for managing Breakpoint rules.
/// Pauses matching requests so the user can inspect/modify before forwarding.
class BreakpointPanel extends StatelessWidget {
  const BreakpointPanel({super.key});

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
              Text('Breakpoints', style: theme.textTheme.titleSmall),
              SizedBox(width: AppTheme.spacing.sm),
              Obx(() => Text(
                '${toolsCtrl.breakpointRules.length} rules',
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
            final rules = toolsCtrl.breakpointRules;
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause_circle_outline, size: 48, color: theme.hintColor),
                    SizedBox(height: AppTheme.spacing.sm),
                    Text(
                      'empty.no_breakpoints'.tr,
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSize.md,
                      ),
                    ),
                    SizedBox(height: AppTheme.spacing.xs),
                    Text(
                      'empty.no_breakpoints_desc'.tr,
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
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final rule = rules[i];
                return _RuleRow(
                  rule: rule,
                  onToggle: () => toolsCtrl.toggleBreakpointRule(i),
                  onEdit: () => _showRuleDialog(context, index: i, rule: rule),
                  onDelete: () => toolsCtrl.removeBreakpointRule(i),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showRuleDialog(BuildContext context, {int? index, BreakpointRule? rule}) {
    showDialog(
      context: context,
      builder: (ctx) => _BreakpointRuleDialog(index: index, rule: rule),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final BreakpointRule rule;
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
            // Pattern and break type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (rule.method != null && rule.method!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                          style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSize.md).copyWith(
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
                      Icon(Icons.pause_circle_outline, size: 12, color: theme.hintColor),
                      const SizedBox(width: 4),
                      Text(
                        'Break on: ${rule.breakOn}',
                        style: TextStyle(
                          fontSize: AppTheme.fontSize.sm,
                          color: theme.hintColor,
                        ),
                      ),
                      if (rule.comment.isNotEmpty) ...[
                        SizedBox(width: AppTheme.spacing.sm),
                        Text(
                          rule.comment,
                          style: TextStyle(
                            fontSize: AppTheme.fontSize.sm,
                            color: theme.hintColor,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

class _BreakpointRuleDialog extends StatefulWidget {
  final int? index;
  final BreakpointRule? rule;

  const _BreakpointRuleDialog({this.index, this.rule});

  @override
  State<_BreakpointRuleDialog> createState() => _BreakpointRuleDialogState();
}

class _BreakpointRuleDialogState extends State<_BreakpointRuleDialog> {
  late final TextEditingController _patternCtrl;
  late final TextEditingController _commentCtrl;
  String _method = 'Any';
  String _breakOn = 'both';

  static const _methods = ['Any', 'GET', 'POST', 'PUT', 'DELETE'];
  static const _breakOptions = ['request', 'response', 'both'];

  bool get isEditing => widget.index != null;

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.rule?.urlPattern ?? '');
    _commentCtrl = TextEditingController(text: widget.rule?.comment ?? '');
    _method = widget.rule?.method ?? 'Any';
    if (_method.isEmpty) _method = 'Any';
    _breakOn = widget.rule?.breakOn ?? 'both';
    if (!_breakOptions.contains(_breakOn)) _breakOn = 'both';
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) return;

    final rule = BreakpointRule(
      enabled: widget.rule?.enabled ?? true,
      urlPattern: pattern,
      method: _method == 'Any' ? null : _method,
      breakOn: _breakOn,
      comment: _commentCtrl.text.trim(),
    );

    final toolsCtrl = Get.find<ToolsController>();
    if (isEditing) {
      toolsCtrl.updateBreakpointRule(widget.index!, rule);
    } else {
      toolsCtrl.addBreakpointRule(rule);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEditing ? 'breakpoint.edit_rule'.tr : 'breakpoint.add_rule'.tr),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'breakpoint.url_pattern'.tr,
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
                hintText: '*.api.com/v1/*',
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
            Row(
              children: [
                // Method dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('breakpoint.method'.tr, style: TextStyle(
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
                                    child: Text(m, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _method = v ?? 'Any'),
                          decoration: InputDecoration(
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
                  ),
                ),
                SizedBox(width: AppTheme.spacing.sm),
                // Break On dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('breakpoint.break_on'.tr, style: TextStyle(
                        fontSize: AppTheme.fontSize.xs,
                        color: theme.hintColor,
                      )),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 32,
                        child: DropdownButtonFormField<String>(
                          initialValue: _breakOn,
                          items: _breakOptions
                              .map((b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(b, style: TextStyle(fontSize: AppTheme.fontSize.sm)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _breakOn = v ?? 'both'),
                          decoration: InputDecoration(
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
                  ),
                ),
              ],
            ),
            SizedBox(height: AppTheme.spacing.sm),
            Text('breakpoint.comment'.tr, style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
              color: theme.hintColor,
            )),
            const SizedBox(height: 2),
            SizedBox(
              height: 32,
              child: TextField(
                controller: _commentCtrl,
                style: TextStyle(fontSize: AppTheme.fontSize.sm),
                decoration: InputDecoration(
                  hintText: 'breakpoint.optional_desc'.tr,
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
}
