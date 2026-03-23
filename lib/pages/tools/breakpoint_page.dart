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
          height: AppTheme.toolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLG),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Text('Breakpoints', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppTheme.spacingSM),
              Obx(() => Text(
                '${toolsCtrl.breakpointRules.length} rules',
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
            final rules = toolsCtrl.breakpointRules;
            if (rules.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause_circle_outline, size: 48, color: theme.hintColor),
                    const SizedBox(height: AppTheme.spacingSM),
                    Text(
                      'No Breakpoint rules',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: AppTheme.fontSizeMD,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      'Add a rule to pause matching requests for inspection',
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
                          style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD).copyWith(
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
                          fontSize: AppTheme.fontSizeSM,
                          color: theme.hintColor,
                        ),
                      ),
                      if (rule.comment.isNotEmpty) ...[
                        const SizedBox(width: AppTheme.spacingSM),
                        Text(
                          rule.comment,
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSM,
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
      title: Text(isEditing ? 'Edit Rule' : 'Add Breakpoint Rule'),
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
              style: AppTheme.monoStyle(context, fontSize: AppTheme.fontSizeMD),
              decoration: InputDecoration(
                hintText: '*.api.com/v1/*',
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
            Row(
              children: [
                // Method dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Method', style: TextStyle(
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
                                    child: Text(m, style: const TextStyle(fontSize: AppTheme.fontSizeSM)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _method = v ?? 'Any'),
                          decoration: InputDecoration(
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
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSM),
                // Break On dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Break On', style: TextStyle(
                        fontSize: AppTheme.fontSizeXS,
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
                                    child: Text(b, style: const TextStyle(fontSize: AppTheme.fontSizeSM)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _breakOn = v ?? 'both'),
                          decoration: InputDecoration(
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
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSM),
            Text('Comment', style: TextStyle(
              fontSize: AppTheme.fontSizeXS,
              color: theme.hintColor,
            )),
            const SizedBox(height: 2),
            SizedBox(
              height: 32,
              child: TextField(
                controller: _commentCtrl,
                style: const TextStyle(fontSize: AppTheme.fontSizeSM),
                decoration: InputDecoration(
                  hintText: 'Optional description',
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
}
