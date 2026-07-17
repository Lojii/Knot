import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controllers/task_scope.dart';
import '../../controllers/flow_table_controller.dart';
import '../../controllers/tag_controller.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/tools_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';
import '../../utils/request_sender.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/empty_state.dart';

class FlowTable extends StatefulWidget {
  const FlowTable({super.key});

  @override
  State<FlowTable> createState() => _FlowTableState();
}

class _FlowTableState extends State<FlowTable> {
  final _scrollController = ScrollController();
  late final Worker _scrollWorker;

  @override
  void initState() {
    super.initState();
    final tableCtrl = TaskScope.table;
    _scrollWorker = ever(tableCtrl.scrollToTopSignal, (_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _scrollWorker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static const _columns = <(String, SortColumn)>[
    ('Proto', SortColumn.protocol),
    ('col.host', SortColumn.host),
    ('col.path', SortColumn.path),
    ('col.method', SortColumn.method),
    ('col.status', SortColumn.status),
    ('Time', SortColumn.time),
    ('Duration', SortColumn.duration),
    ('col.size', SortColumn.size),
  ];

  @override
  Widget build(BuildContext context) {
    final tableCtrl = TaskScope.table;
    final flowCtrl = TaskScope.flow;
    final selCtrl = TaskScope.selection;
    final theme = Theme.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      // Available width for columns = total - padding - resize handles (7px × 7 gaps)
      final totalWidth = constraints.maxWidth - AppTheme.spacing.sm * 2 - 7 * 7;

      return Obx(() {
        final weights = tableCtrl.columnWeights.toList();
        final totalWeight = weights.fold<double>(0, (s, w) => s + w);

        // flows is already filtered + sorted by FlowTableController.
        final items = tableCtrl.flows;

        List<double> colWidths = weights.map((w) => w / totalWeight * totalWidth).toList();

        if (items.isEmpty && !flowCtrl.isLoading.value) {
          return Column(
            children: [
              _buildHeader(theme, tableCtrl, colWidths, totalWidth),
              Expanded(
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'empty.no_requests'.tr,
                  description: 'home.start_hint'.tr,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildHeader(theme, tableCtrl, colWidths, totalWidth),
            if (flowCtrl.isLoading.value)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: items.length,
                itemExtent: AppTheme.sizing.tableRowHeight,
                itemBuilder: (ctx, i) {
                  final f = items[i];
                  // Scope the selection highlight to each row so selecting a
                  // flow repaints only two rows, not the whole table.
                  return Obx(() {
                    final isSelected = selCtrl.selectedFlow.value?.flowId == f.flowId;
                    return _buildRow(context, f, isSelected, colWidths);
                  });
                },
              ),
            ),
          ],
        );
      });
    });
  }

  Widget _buildHeader(ThemeData theme, FlowTableController tableCtrl, List<double> colWidths, double totalWidth) {
    return Container(
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
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          for (int i = 0; i < _columns.length; i++) ...[
            _headerCell(tableCtrl, _columns[i].$1, _columns[i].$2, colWidths[i]),
            if (i < _columns.length - 1)
              _resizeHandle(tableCtrl, i, totalWidth),
          ],
        ],
      ),
    );
  }

  Widget _headerCell(FlowTableController tableCtrl, String labelKey, SortColumn col, double width) {
    final isActive = tableCtrl.sortColumn.value == col;
    final arrow = isActive ? (tableCtrl.sortAscending.value ? ' \u25B2' : ' \u25BC') : '';
    final label = labelKey.contains('.') ? labelKey.tr : labelKey;

    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => tableCtrl.toggleSort(col),
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1,
                style: TextStyle(fontSize: AppTheme.fontSize.sm, fontWeight: FontWeight.w600,
                    color: AppTheme.colors(context).textSecondary))),
            if (arrow.isNotEmpty)
              Text(arrow, style: TextStyle(fontSize: AppTheme.fontSize.xs, fontWeight: FontWeight.w600,
                  color: AppTheme.colors(context).textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _resizeHandle(FlowTableController tableCtrl, int colIndex, double totalWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          tableCtrl.resizeColumns(colIndex, details.delta.dx, totalWidth);
        },
        child: SizedBox(
          width: 7,
          height: AppTheme.sizing.tableHeaderHeight,
          child: Center(
            child: Container(width: 1, height: 12, color: AppTheme.colors(context).divider),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, FlowSummary flow, bool isSelected, List<double> colWidths) {
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _FlowRow._showContextMenu(context, details.globalPosition, flow);
      },
      child: InkWell(
        onTap: () => TaskScope.selection.select(flow),
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
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              SizedBox(width: colWidths[0], child: Text(flow.protocol,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[1], child: Text(flow.host,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[2], child: Tooltip(
                  message: flow.uri,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(flow.uri,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm), overflow: TextOverflow.ellipsis, maxLines: 1))),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[3], child: Text(_FlowRow._methodLabel(flow.method),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, fontWeight: FontWeight.w600, color: AppTheme.methodColorOf(context, flow.method)), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[4], child: Text(flow.statusCode,
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.statusColorOf(context, int.tryParse(flow.statusCode) ?? 0)), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[5], child: Text(_FlowRow._formatTime(flow.startedAt),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.colors(context).textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[6], child: Text(
                  flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.colors(context).textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 7),
              SizedBox(width: colWidths[7], child: Text(_FlowRow._formatSize(flow.downloadBytes),
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.colors(context).textSecondary), overflow: TextOverflow.ellipsis, maxLines: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static utility methods for flow table rows (context menu, formatting).
class _FlowRow {
  _FlowRow._();

  static void _showContextMenu(BuildContext context, Offset position, FlowSummary flow) {
    final tagCtrl = TaskScope.tag;

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
        showAppToast(context, 'detail.curl_copied'.tr);
      } else if (value == 'repeat') {
        _repeatRequest(context, flow);
      } else if (value == 'compose') {
        _openInCompose(context, flow);
      } else if (value == 'mapLocal') {
        _openMapLocalWithUrl(context, flow);
      }
    });
  }

  static void _showCommentDialog(BuildContext context, String flowId) {
    final tagCtrl = TaskScope.tag;
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

  static Future<void> _repeatRequest(BuildContext context, FlowSummary flow) async {
    final detailCtrl = TaskScope.detail;
    final tid = TaskScope.activeTaskId;

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

  static Future<void> _openInCompose(BuildContext context, FlowSummary flow) async {
    final detailCtrl = TaskScope.detail;
    final pageCtrl = Get.find<AppPageController>();
    final tid = TaskScope.activeTaskId;

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

  static void _openMapLocalWithUrl(BuildContext context, FlowSummary flow) {
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

  static String _methodLabel(String m) => m.isNotEmpty ? m : '-';

  static String _formatTime(double timestamp) {
    if (timestamp <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).toInt(),
      isUtc: false,
    );
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  static String _formatSize(int bytes) {
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
    final tagCtrl = TaskScope.tag;

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
                        border: Border.all(color: AppTheme.colors(context).divider),
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
