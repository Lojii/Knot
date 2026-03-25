import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/filter_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../controllers/tag_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';
import '../../utils/request_sender.dart';

class FlowTable extends StatefulWidget {
  const FlowTable({super.key});

  @override
  State<FlowTable> createState() => _FlowTableState();
}

enum _SortColumn { protocol, host, path, method, status, time, duration, size }

class _FlowTableState extends State<FlowTable> {
  final _scrollController = ScrollController();
  _SortColumn? _sortColumn;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final flowCtrl = Get.find<FlowController>();
    ever(flowCtrl.scrollToTopSignal, (_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // All flows are loaded locally — no pagination needed
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
      case _SortColumn.protocol:
        comparator = (a, b) => a.protocol.compareTo(b.protocol);
      case _SortColumn.host:
        comparator = (a, b) => a.host.compareTo(b.host);
      case _SortColumn.path:
        comparator = (a, b) => a.uri.compareTo(b.uri);
      case _SortColumn.method:
        comparator = (a, b) => a.method.compareTo(b.method);
      case _SortColumn.status:
        comparator = (a, b) => a.statusCode.compareTo(b.statusCode);
      case _SortColumn.time:
        comparator = (a, b) => a.startedAt.compareTo(b.startedAt);
      case _SortColumn.duration:
        comparator = (a, b) => (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
      case _SortColumn.size:
        comparator = (a, b) => a.downloadBytes.compareTo(b.downloadBytes);
    }
    sorted.sort(_sortAscending ? comparator : (a, b) => comparator(b, a));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Obx(() {
      var items = flowCtrl.flows.toList();
      // Content type filter (client-side, protocol/domain handled by API)
      final filterCtrl = Get.find<FilterController>();
      if (filterCtrl.activeContentTypes.isNotEmpty) {
        items = items.where((f) => filterCtrl.matchesContentType(f)).toList();
      }

      items = _applySorting(items);

      if (items.isEmpty && !flowCtrl.isLoading.value) {
        return Column(
          children: [
            _tableHeader(theme),
            Expanded(
              child: Center(child: Text('empty.no_requests'.tr,
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
            fontSize: AppTheme.fontSize.sm,
            fontWeight: FontWeight.bold,
            color: isActive ? null : null,
          )),
          if (arrow.isNotEmpty)
            Text(arrow, style: TextStyle(
              fontSize: AppTheme.fontSize.xs,
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
    height: AppTheme.sizing.tableHeaderHeight,
    padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.mode(context).table.headerGradientStart,
          AppTheme.mode(context).table.headerGradientEnd,
        ],
      ),
    ),
    child: Row(
      children: [
        _sortableHeader('Proto', _SortColumn.protocol, width: 55),
        _sortableHeader('col.host'.tr, _SortColumn.host, flex: 2),
        _sortableHeader('col.path'.tr, _SortColumn.path, flex: 3),
        _sortableHeader('col.method'.tr, _SortColumn.method, width: 60),
        _sortableHeader('col.status'.tr, _SortColumn.status, width: 50),
        _sortableHeader('Time', _SortColumn.time, width: 70),
        _sortableHeader('Duration', _SortColumn.duration, width: 70),
        _sortableHeader('col.size'.tr, _SortColumn.size, width: 65),
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
          height: AppTheme.sizing.tableRowHeight,
          padding: EdgeInsets.only(
            left: isSelected ? AppTheme.spacing.sm - AppTheme.mode(context).table.selectedIndicatorWidth : AppTheme.spacing.sm,
            right: AppTheme.spacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.mode(context).table.selectedBackground : null,
            border: isSelected
                ? Border(left: BorderSide(
                    color: AppTheme.mode(context).table.selectedIndicatorColor,
                    width: AppTheme.mode(context).table.selectedIndicatorWidth,
                  ))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(width: 55, child: Text(flow.protocol,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm))),
              Expanded(flex: 2, child: Text(flow.host,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm), overflow: TextOverflow.ellipsis)),
              Expanded(flex: 3, child: Text(flow.uri,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 60, child: Text(_methodLabel(flow.method),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, fontWeight: FontWeight.w600, color: AppTheme.methodColorOf(context, flow.method)))),
              SizedBox(width: 50, child: Text(flow.statusCode,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.statusColorOf(context, int.tryParse(flow.statusCode) ?? 0)))),
              SizedBox(width: 70, child: Text(_formatTime(flow.startedAt),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm))),
              SizedBox(width: 70, child: Text(
                  flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
                  style: TextStyle(fontSize: AppTheme.fontSize.sm))),
              SizedBox(width: 65, child: Text(_formatSize(flow.downloadBytes),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm))),
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
              SizedBox(width: AppTheme.spacing.sm),
              Text(tagCtrl.getComment(flow.flowId) != null
                  ? 'menu.edit_comment'.tr : 'menu.add_comment'.tr),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Copy as cURL
        PopupMenuItem(
          value: 'curl',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('menu.copy_curl'.tr),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Repeat
        PopupMenuItem(
          value: 'repeat',
          child: Row(
            children: [
              const Icon(Icons.replay, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('menu.repeat'.tr),
            ],
          ),
        ),
        // Open in Compose
        PopupMenuItem(
          value: 'compose',
          child: Row(
            children: [
              const Icon(Icons.edit_note, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('menu.open_compose'.tr),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Map Local
        PopupMenuItem(
          value: 'mapLocal',
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 16),
              SizedBox(width: AppTheme.spacing.sm),
              Text('menu.map_local'.tr),
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
      } else if (value == 'mapLocal') {
        _openMapLocalWithUrl(context, flow);
      }
    });
  }

  void _showCommentDialog(BuildContext context, String flowId) {
    final tagCtrl = Get.find<TagController>();
    final controller = TextEditingController(text: tagCtrl.getComment(flowId) ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('msg.flow_comment'.tr, style: TextStyle(fontSize: AppTheme.fontSize.lg)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'msg.enter_comment'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('action.cancel'.tr),
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
            child: Text('action.save'.tr),
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
          content: Text('msg.repeat_failed'.trParams({'error': '$e'})),
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

  void _openMapLocalWithUrl(BuildContext context, FlowSummary flow) {
    final pageCtrl = Get.find<AppPageController>();
    final toolsCtrl = Get.find<ToolsController>();
    final protocol = flow.protocol.toLowerCase();
    final scheme = (protocol == 'https' || protocol == 'h2') ? 'https' : 'http';
    final urlPattern = '$scheme://${flow.host}${flow.uri}';
    // Pre-create a rule with the URL pattern filled in and navigate
    toolsCtrl.addMapLocalRule(MapLocalRule(
      urlPattern: urlPattern,
      method: flow.method,
    ));
    pageCtrl.showMapLocal();
  }

  String _methodLabel(String m) => m.isNotEmpty ? m : '-';

  String _formatTime(double timestamp) {
    if (timestamp <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).toInt(),
      isUtc: false,
    );
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
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
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spacing.sm,
        vertical: AppTheme.spacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('menu.color_tag'.tr, style: TextStyle(
            fontSize: AppTheme.fontSize.sm,
            fontWeight: FontWeight.bold,
          )),
          SizedBox(height: AppTheme.spacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...TagController.tagColors.map((entry) => GestureDetector(
                onTap: () {
                  tagCtrl.setTag(flowId, entry.value);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: EdgeInsets.only(right: AppTheme.spacing.xs),
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
                  message: 'menu.clear'.tr,
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
