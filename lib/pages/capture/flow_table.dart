import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/tree_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/tag_controller.dart';
import '../../controllers/page_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';
import '../../utils/request_sender.dart';

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
        // Extra space for tag dot
        const SizedBox(width: 14),
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
    final tagCtrl = Get.find<TagController>();
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, flow);
      },
      child: InkWell(
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
              // Color tag dot
              Obx(() {
                final tagColor = tagCtrl.getTag(flow.flowId);
                return SizedBox(
                  width: 14,
                  child: tagColor != null
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tagColor,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox.shrink(),
                );
              }),
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
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, FlowSummary flow) {
    final tagCtrl = Get.find<TagController>();

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        // Color submenu
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ColorSubmenu(flowId: flow.flowId),
        ),
        const PopupMenuDivider(),
        // Add Comment
        PopupMenuItem(
          value: 'comment',
          child: Row(
            children: [
              const Icon(Icons.comment_outlined, size: 16),
              const SizedBox(width: AppTheme.spacingSM),
              Text(tagCtrl.getComment(flow.flowId) != null
                  ? 'Edit Comment' : 'Add Comment'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Copy as cURL
        const PopupMenuItem(
          value: 'curl',
          child: Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Copy as cURL'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Repeat
        const PopupMenuItem(
          value: 'repeat',
          child: Row(
            children: [
              Icon(Icons.replay, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Repeat'),
            ],
          ),
        ),
        // Open in Compose
        const PopupMenuItem(
          value: 'compose',
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 16),
              SizedBox(width: AppTheme.spacingSM),
              Text('Open in Compose'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'comment') {
        _showCommentDialog(context, flow.flowId);
      } else if (value == 'curl') {
        final curl = "curl -X ${flow.method} '${flow.protocol.toLowerCase()}://${flow.host}${flow.uri}'";
        Clipboard.setData(ClipboardData(text: curl));
      } else if (value == 'repeat') {
        _repeatRequest(context, flow);
      } else if (value == 'compose') {
        _openInCompose(context, flow);
      }
    });
  }

  void _showCommentDialog(BuildContext context, String flowId) {
    final tagCtrl = Get.find<TagController>();
    final controller = TextEditingController(text: tagCtrl.getComment(flowId) ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Flow Comment', style: TextStyle(fontSize: AppTheme.fontSizeLG)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter a comment...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                tagCtrl.removeComment(flowId);
              } else {
                tagCtrl.setComment(flowId, text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _repeatRequest(BuildContext context, FlowSummary flow) async {
    final taskCtrl = Get.find<TaskController>();
    final detailCtrl = Get.find<DetailController>();
    final tid = taskCtrl.currentTask.value?.id;

    // Load detail if needed
    Map<String, dynamic> detail = detailCtrl.detail.value?.raw ?? {};
    if (detail.isEmpty || detail['flowId'] != flow.flowId) {
      if (tid != null) {
        await detailCtrl.loadDetail(tid, flow.flowId);
        detail = detailCtrl.detail.value?.raw ?? {};
      }
    }

    if (!context.mounted) return;

    try {
      final result = await RequestSender.repeat(flow, detail);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.statusCode} (${result.elapsed.inMilliseconds}ms)'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Repeat failed: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openInCompose(BuildContext context, FlowSummary flow) async {
    final taskCtrl = Get.find<TaskController>();
    final detailCtrl = Get.find<DetailController>();
    final pageCtrl = Get.find<AppPageController>();
    final tid = taskCtrl.currentTask.value?.id;

    // Load detail if needed
    Map<String, dynamic> detail = detailCtrl.detail.value?.raw ?? {};
    if (detail.isEmpty || detail['flowId'] != flow.flowId) {
      if (tid != null) {
        await detailCtrl.loadDetail(tid, flow.flowId);
        detail = detailCtrl.detail.value?.raw ?? {};
      }
    }

    final headers = RequestSender.extractHeaders(detail);
    final url = RequestSender.buildUrl(flow);

    pageCtrl.openInCompose(
      method: flow.method,
      url: url,
      headers: headers,
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

/// Inline color picker for the context menu.
class _ColorSubmenu extends StatelessWidget {
  final String flowId;
  const _ColorSubmenu({required this.flowId});

  @override
  Widget build(BuildContext context) {
    final tagCtrl = Get.find<TagController>();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSM,
        vertical: AppTheme.spacingXS,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Color Tag', style: TextStyle(
            fontSize: AppTheme.fontSizeSM,
            fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: AppTheme.spacingXS),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...TagController.tagColors.map((entry) => GestureDetector(
                onTap: () {
                  tagCtrl.setTag(flowId, entry.value);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: AppTheme.spacingXS),
                  child: Tooltip(
                    message: entry.key,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              )),
              // Clear button
              GestureDetector(
                onTap: () {
                  tagCtrl.removeTag(flowId);
                  Navigator.pop(context);
                },
                child: Tooltip(
                  message: 'Clear',
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).hintColor),
                    ),
                    child: Icon(Icons.close, size: 12, color: Theme.of(context).hintColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
