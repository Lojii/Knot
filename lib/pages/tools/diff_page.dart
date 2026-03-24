import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/flow_summary.dart';
import '../../models/flow_detail.dart';
import '../../theme/app_theme.dart';

/// Side-by-side diff comparison of two flows.
class DiffPage extends StatefulWidget {
  const DiffPage({super.key});

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  FlowSummary? _flowA;
  FlowSummary? _flowB;
  Map<String, dynamic>? _detailA;
  Map<String, dynamic>? _detailB;
  String _bodyA = '';
  String _bodyB = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_flowA == null || _flowB == null) {
      return _buildPicker(context, theme);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(child: _buildDiffContent(theme)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spacing.md,
        vertical: AppTheme.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 18, color: theme.colorScheme.primary),
          SizedBox(width: AppTheme.spacing.sm),
          Text('Diff Comparison', style: theme.textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Change Flows'),
            onPressed: () => setState(() {
              _flowA = null;
              _flowB = null;
              _detailA = null;
              _detailB = null;
              _bodyA = '';
              _bodyB = '';
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(BuildContext context, ThemeData theme) {
    final flowCtrl = Get.find<FlowController>();
    final flows = flowCtrl.flows;

    return Padding(
      padding: EdgeInsets.all(AppTheme.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Diff Tool', style: theme.textTheme.titleMedium),
          SizedBox(height: AppTheme.spacing.sm),
          Text(
            'Select two flows to compare side by side.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          SizedBox(height: AppTheme.spacing.lg),
          if (flows.isEmpty)
            Text(
              'No flows available. Capture some traffic first.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            )
          else ...[
            Text('Flow A:', style: theme.textTheme.labelLarge),
            SizedBox(height: AppTheme.spacing.xs),
            _FlowDropdown(
              flows: flows,
              selected: _flowA,
              onChanged: (f) => setState(() => _flowA = f),
            ),
            SizedBox(height: AppTheme.spacing.md),
            Text('Flow B:', style: theme.textTheme.labelLarge),
            SizedBox(height: AppTheme.spacing.xs),
            _FlowDropdown(
              flows: flows,
              selected: _flowB,
              onChanged: (f) => setState(() => _flowB = f),
            ),
            SizedBox(height: AppTheme.spacing.lg),
            FilledButton.icon(
              icon: const Icon(Icons.compare_arrows, size: 16),
              label: const Text('Compare'),
              onPressed: _flowA != null && _flowB != null ? _loadAndCompare : null,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadAndCompare() async {
    if (_flowA == null || _flowB == null) return;
    setState(() => _isLoading = true);

    final taskCtrl = Get.find<TaskController>();
    final taskId = taskCtrl.currentTask.value?.id;
    if (taskId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final api = Get.find<FlowController>().api;

    try {
      final results = await Future.wait([
        api.getFlowDetail(taskId, _flowA!.flowId),
        api.getFlowDetail(taskId, _flowB!.flowId),
        api.getPayload(taskId, _flowA!.flowId, 'response', preview: true)
            .catchError((_) => ''),
        api.getPayload(taskId, _flowB!.flowId, 'response', preview: true)
            .catchError((_) => ''),
      ]);

      setState(() {
        _detailA = (results[0] as FlowDetail).raw;
        _detailB = (results[1] as FlowDetail).raw;
        _bodyA = results[2] as String;
        _bodyB = results[3] as String;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load flow details: $e')),
        );
      }
    }
  }

  Widget _buildDiffContent(ThemeData theme) {
    final sectionsA = _buildSections(_flowA!, _detailA ?? {}, _bodyA);
    final sectionsB = _buildSections(_flowB!, _detailB ?? {}, _bodyB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _DiffColumn(
            label: 'Flow A',
            sections: sectionsA,
            otherSections: sectionsB,
            theme: theme,
            isLeft: true,
          ),
        ),
        VerticalDivider(width: 1, color: theme.dividerColor),
        Expanded(
          child: _DiffColumn(
            label: 'Flow B',
            sections: sectionsB,
            otherSections: sectionsA,
            theme: theme,
            isLeft: false,
          ),
        ),
      ],
    );
  }

  List<_DiffSection> _buildSections(
    FlowSummary flow,
    Map<String, dynamic> detail,
    String body,
  ) {
    final metadata = detail['metadata'] as Map<String, dynamic>? ?? {};
    final sections = <_DiffSection>[];

    // URL section
    sections.add(_DiffSection(
      title: 'Request',
      lines: ['${flow.method} ${flow.uri}'],
    ));

    // Status
    sections.add(_DiffSection(
      title: 'Status',
      lines: ['${flow.status} (${flow.protocol})'],
    ));

    // Request headers
    final reqHeaders = (metadata['requestHeaders'] as List?) ?? [];
    final reqLines = <String>[];
    for (final h in reqHeaders) {
      final pair = h as List;
      final name = pair.first as String;
      final value = pair.last as String;
      if (name.startsWith(':')) continue;
      reqLines.add('$name: $value');
    }
    reqLines.sort();
    sections.add(_DiffSection(title: 'Request Headers', lines: reqLines));

    // Response headers
    final rspHeaders = (metadata['responseHeaders'] as List?) ?? [];
    final rspLines = <String>[];
    for (final h in rspHeaders) {
      final pair = h as List;
      final name = pair.first as String;
      final value = pair.last as String;
      if (name.startsWith(':')) continue;
      rspLines.add('$name: $value');
    }
    rspLines.sort();
    sections.add(_DiffSection(title: 'Response Headers', lines: rspLines));

    // Body
    final bodyLines = body.isNotEmpty ? body.split('\n') : <String>['(empty)'];
    sections.add(_DiffSection(title: 'Body', lines: bodyLines));

    return sections;
  }
}

class _DiffSection {
  final String title;
  final List<String> lines;
  const _DiffSection({required this.title, required this.lines});
}

class _DiffColumn extends StatelessWidget {
  final String label;
  final List<_DiffSection> sections;
  final List<_DiffSection> otherSections;
  final ThemeData theme;
  final bool isLeft;

  const _DiffColumn({
    required this.label,
    required this.sections,
    required this.otherSections,
    required this.theme,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.all(AppTheme.spacing.sm),
      itemCount: sections.length,
      itemBuilder: (context, idx) {
        final section = sections[idx];
        final otherSection = idx < otherSections.length ? otherSections[idx] : null;
        final otherLines = otherSection?.lines ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spacing.sm,
                vertical: AppTheme.spacing.xs,
              ),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                section.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...section.lines.asMap().entries.map((entry) {
              final lineIdx = entry.key;
              final line = entry.value;
              final otherLine = lineIdx < otherLines.length ? otherLines[lineIdx] : null;
              final isDiff = otherLine == null || line != otherLine;

              return Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.sm,
                  vertical: 2,
                ),
                color: isDiff
                    ? (isLeft
                        ? Colors.red.withValues(alpha: 0.08)
                        : Colors.green.withValues(alpha: 0.08))
                    : null,
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: isDiff
                        ? (isLeft ? Colors.red.shade700 : Colors.green.shade700)
                        : null,
                  ),
                ),
              );
            }),
            SizedBox(height: AppTheme.spacing.sm),
          ],
        );
      },
    );
  }
}

class _FlowDropdown extends StatelessWidget {
  final List<FlowSummary> flows;
  final FlowSummary? selected;
  final ValueChanged<FlowSummary?> onChanged;

  const _FlowDropdown({
    required this.flows,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      isExpanded: true,
      value: selected?.flowId,
      hint: const Text('Select a flow...'),
      items: flows.map((f) => DropdownMenuItem(
        value: f.flowId,
        child: Text(
          '${f.method} ${f.host}${f.uri}  [${f.status}]',
          overflow: TextOverflow.ellipsis,
        ),
      )).toList(),
      onChanged: (flowId) {
        if (flowId == null) return;
        final flow = flows.firstWhereOrNull((f) => f.flowId == flowId);
        onChanged(flow);
      },
    );
  }
}
