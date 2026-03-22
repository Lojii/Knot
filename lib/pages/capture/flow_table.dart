import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../models/flow_summary.dart';

class FlowTable extends StatefulWidget {
  const FlowTable({super.key});

  @override
  State<FlowTable> createState() => _FlowTableState();
}

class _FlowTableState extends State<FlowTable> {
  final _scrollController = ScrollController();

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

      if (items.isEmpty && !flowCtrl.isLoading.value) {
        return Column(
          children: [
            _tableHeader(theme),
            const Expanded(
              child: Center(child: Text('No requests captured', style: TextStyle(color: Colors.grey))),
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

  Widget _tableHeader(ThemeData theme) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
    ),
    child: const Row(
      children: [
        SizedBox(width: 60, child: Text('Method', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        SizedBox(width: 8),
        Expanded(flex: 2, child: Text('Host', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text('Path', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        SizedBox(width: 50, child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        SizedBox(width: 70, child: Text('Size', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        SizedBox(width: 70, child: Text('Time', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
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
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: isSelected
            ? theme.colorScheme.primary.withAlpha(26)
            : null,
        child: Row(
          children: [
            SizedBox(width: 60, child: Text(_methodLabel(flow.method),
                style: TextStyle(fontSize: 11, color: _methodColor(flow.method)))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: Text(flow.host,
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(flex: 3, child: Text(flow.uri,
                style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 50, child: Text(flow.statusCode,
                style: TextStyle(fontSize: 11, color: _statusColor(flow.statusCode)))),
            SizedBox(width: 70, child: Text(_formatSize(flow.downloadBytes),
                style: const TextStyle(fontSize: 11))),
            SizedBox(width: 70, child: Text(
                flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
                style: const TextStyle(fontSize: 11))),
          ],
        ),
      ),
    );
  }

  String _methodLabel(String m) => m.isNotEmpty ? m : '-';
  Color _methodColor(String m) => switch (m) {
    'GET' => Colors.green,
    'POST' => Colors.orange,
    'PUT' => Colors.blue,
    'DELETE' => Colors.red,
    _ => Colors.grey,
  };
  Color _statusColor(String s) {
    final code = int.tryParse(s) ?? 0;
    if (code >= 500) return Colors.red;
    if (code >= 400) return Colors.orange;
    if (code >= 300) return Colors.blue;
    if (code >= 200) return Colors.green;
    return Colors.grey;
  }
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  }
}
