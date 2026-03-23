import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';

class FlowTable extends StatefulWidget {
  const FlowTable({super.key});

  @override
  State<FlowTable> createState() => _FlowTableState();
}

enum _SortColumn { method, host, path, status, size, time }

class _FlowTableState extends State<FlowTable> {
  final _scrollController = ScrollController();
  _SortColumn? _sortColumn;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      Get.find<FlowController>().loadMore();
    }
  }

  void _onSortTap(_SortColumn col) {
    setState(() {
      if (_sortColumn == col) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          // Third tap: reset to no sort
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = col;
        _sortAscending = true;
      }
    });
  }

  List<FlowSummary> _applySorting(List<FlowSummary> items) {
    if (_sortColumn == null) return items;
    final sorted = List<FlowSummary>.from(items);
    int Function(FlowSummary, FlowSummary) comparator;
    switch (_sortColumn!) {
      case _SortColumn.method:
        comparator = (a, b) => a.method.compareTo(b.method);
      case _SortColumn.host:
        comparator = (a, b) => a.host.compareTo(b.host);
      case _SortColumn.path:
        comparator = (a, b) => a.uri.compareTo(b.uri);
      case _SortColumn.status:
        comparator = (a, b) => a.statusCode.compareTo(b.statusCode);
      case _SortColumn.size:
        comparator = (a, b) => a.downloadBytes.compareTo(b.downloadBytes);
      case _SortColumn.time:
        comparator = (a, b) => (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
    }
    sorted.sort(_sortAscending ? comparator : (a, b) => comparator(b, a));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final treeCtrl = Get.find<TreeController>();
    final theme = Theme.of(context);

    return Obx(() {
      var items = flowCtrl.flows.toList();
      // Filter by selected domain
      final domain = treeCtrl.selectedDomain.value;
      if (domain != null) {
        items = items.where((f) => f.host == domain).toList();
      }

      items = _applySorting(items);

      if (items.isEmpty && !flowCtrl.isLoading.value) {
        return Column(
          children: [
            _tableHeader(theme),
            Expanded(
              child: Center(child: Text('No requests captured',
                  style: TextStyle(color: theme.hintColor))),
            ),
          ],
        );
      }

      return Column(
        children: [
          _tableHeader(theme),
          // Loading indicator
          if (flowCtrl.isLoading.value)
            const LinearProgressIndicator(minHeight: 2),
          // Table body
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final f = items[i];
                final isSelected = flowCtrl.selectedFlow.value?.flowId == f.flowId;
                return _FlowRow(flow: f, isSelected: isSelected);
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _sortableHeader(String label, _SortColumn col, {double? width, int? flex}) {
    final isActive = _sortColumn == col;
    final arrow = isActive ? (_sortAscending ? ' \u25B2' : ' \u25BC') : '';
    final child = GestureDetector(
      onTap: () => _onSortTap(col),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            fontSize: AppTheme.fontSizeSM,
            fontWeight: FontWeight.bold,
            color: isActive ? null : null,
          )),
          if (arrow.isNotEmpty)
            Text(arrow, style: TextStyle(
              fontSize: AppTheme.fontSizeXS,
              fontWeight: FontWeight.bold,
            )),
        ],
      ),
    );

    if (flex != null) {
      return Expanded(flex: flex, child: child);
    }
    return SizedBox(width: width, child: child);
  }

  Widget _tableHeader(ThemeData theme) => Container(
    height: AppTheme.tableHeaderHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
    ),
    child: Row(
      children: [
        _sortableHeader('Method', _SortColumn.method, width: 60),
        const SizedBox(width: AppTheme.spacingSM),
        _sortableHeader('Host', _SortColumn.host, flex: 2),
        _sortableHeader('Path', _SortColumn.path, flex: 3),
        _sortableHeader('Status', _SortColumn.status, width: 50),
        _sortableHeader('Size', _SortColumn.size, width: 70),
        _sortableHeader('Time', _SortColumn.time, width: 70),
      ],
    ),
  );
}

class _FlowRow extends StatelessWidget {
  final FlowSummary flow;
  final bool isSelected;
  const _FlowRow({required this.flow, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final detailCtrl = Get.find<DetailController>();
    final taskCtrl = Get.find<TaskController>();
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        flowCtrl.selectFlow(flow);
        final tid = taskCtrl.currentTask.value?.id;
        if (tid != null) {
          detailCtrl.loadDetail(tid, flow.flowId);
          detailCtrl.loadBodies(tid, flow.flowId);
        }
      },
      child: Container(
        height: AppTheme.tableRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSM),
        color: isSelected
            ? theme.colorScheme.primary.withAlpha(26)
            : null,
        child: Row(
          children: [
            SizedBox(width: 60, child: Text(_methodLabel(flow.method),
                style: TextStyle(fontSize: AppTheme.fontSizeSM, color: AppTheme.methodColor(flow.method)))),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(flex: 2, child: Text(flow.host,
                style: const TextStyle(fontSize: AppTheme.fontSizeSM), overflow: TextOverflow.ellipsis)),
            Expanded(flex: 3, child: Text(flow.uri,
                style: const TextStyle(fontSize: AppTheme.fontSizeSM), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 50, child: Text(flow.statusCode,
                style: TextStyle(fontSize: AppTheme.fontSizeSM, color: _statusColor(flow.statusCode)))),
            SizedBox(width: 70, child: Text(_formatSize(flow.downloadBytes),
                style: const TextStyle(fontSize: AppTheme.fontSizeSM))),
            SizedBox(width: 70, child: Text(
                flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
                style: const TextStyle(fontSize: AppTheme.fontSizeSM))),
          ],
        ),
      ),
    );
  }

  String _methodLabel(String m) => m.isNotEmpty ? m : '-';

  Color _statusColor(String s) {
    final code = int.tryParse(s) ?? 0;
    return AppTheme.statusColor(code);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  }
}
