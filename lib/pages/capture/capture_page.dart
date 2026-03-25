import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/detail_controller.dart';
import '../../controllers/task_controller.dart';
import '../../utils/request_sender.dart';
import '../../theme/app_theme.dart';
import 'global_bar.dart';
import 'filter_bar.dart';
import 'tree_panel.dart';
import 'content_panel.dart';
import 'status_bar.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';
import '../compose/compose_page.dart';
import '../tools/map_remote_page.dart';
import '../tools/map_local_page.dart';
import '../tools/allow_block_page.dart';
import '../tools/diff_page.dart';
import '../tools/breakpoint_page.dart';

// ============ Intent declarations ============
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class ClearFlowsIntent extends Intent {
  const ClearFlowsIntent();
}

class ToggleCaptureIntent extends Intent {
  const ToggleCaptureIntent();
}

class DeselectFlowIntent extends Intent {
  const DeselectFlowIntent();
}

class CopyAsCurlIntent extends Intent {
  const CopyAsCurlIntent();
}

class RepeatRequestIntent extends Intent {
  const RepeatRequestIntent();
}

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageCtrl = Get.find<AppPageController>();

    return Scaffold(
      body: Column(
        children: [
          const GlobalBar(),
          Expanded(
            child: Obx(() => switch (pageCtrl.currentPage.value) {
              AppPage.capture => const _CaptureContent(),
              AppPage.history => const HistoryPanel(),
              AppPage.settings => const SettingsPanel(),
              AppPage.compose => const ComposePage(),
              AppPage.mapRemote => const MapRemotePanel(),
              AppPage.mapLocal => const MapLocalPanel(),
              AppPage.allowBlock => const AllowBlockPanel(),
              AppPage.diff => const DiffPage(),
              AppPage.breakpointMgmt => const BreakpointPanel(),
            }),
          ),
          const CaptureStatusBar(),
        ],
      ),
    );
  }
}

class _CaptureContent extends StatefulWidget {
  const _CaptureContent();

  @override
  State<_CaptureContent> createState() => _CaptureContentState();
}

class _CaptureContentState extends State<_CaptureContent> {
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final taskCtrl = Get.find<TaskController>();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const FocusSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const ClearFlowsIntent(),
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            const ToggleCaptureIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const DeselectFlowIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            const CopyAsCurlIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            const RepeatRequestIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              _searchFocusNode.requestFocus();
              return null;
            },
          ),
          ClearFlowsIntent: CallbackAction<ClearFlowsIntent>(
            onInvoke: (_) {
              flowCtrl.flows.clear();
              return null;
            },
          ),
          ToggleCaptureIntent: CallbackAction<ToggleCaptureIntent>(
            onInvoke: (_) {
              taskCtrl.toggleCapture();
              return null;
            },
          ),
          DeselectFlowIntent: CallbackAction<DeselectFlowIntent>(
            onInvoke: (_) {
              flowCtrl.selectedFlow.value = null;
              return null;
            },
          ),
          CopyAsCurlIntent: CallbackAction<CopyAsCurlIntent>(
            onInvoke: (_) {
              final flow = flowCtrl.selectedFlow.value;
              if (flow != null) {
                final curl = "curl -X ${flow.method} '${flow.protocol.toLowerCase()}://${flow.host}${flow.uri}'";
                Clipboard.setData(ClipboardData(text: curl));
              }
              return null;
            },
          ),
          RepeatRequestIntent: CallbackAction<RepeatRequestIntent>(
            onInvoke: (_) {
              final flow = flowCtrl.selectedFlow.value;
              if (flow == null) return null;
              final detailCtrl = Get.find<DetailController>();
              final tid = taskCtrl.currentTask.value?.id;

              () async {
                Map<String, dynamic> detail = detailCtrl.detail.value?.raw ?? {};
                if (detail.isEmpty || detail['flowId'] != flow.flowId) {
                  if (tid != null) {
                    await detailCtrl.loadDetail(tid, flow.flowId);
                    detail = detailCtrl.detail.value?.raw ?? {};
                  }
                }
                try {
                  final result = await RequestSender.repeat(flow, detail);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${result.statusCode} (${result.elapsed.inMilliseconds}ms)'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Repeat failed: $e'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              }();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              FilterBar(searchFocusNode: _searchFocusNode),
              Expanded(
                child: MultiSplitViewTheme(
                  data: MultiSplitViewThemeData(
                    dividerPainter: DividerPainters.background(
                      color: AppTheme.colors(context).divider,
                      highlightedColor: AppTheme.colors(context).primary.withAlpha(80),
                    ),
                    dividerThickness: 1,
                  ),
                  child: MultiSplitView(
                    axis: Axis.horizontal,
                    initialAreas: [
                      Area(
                        min: 150,
                        size: AppTheme.sizing.treeDefaultWidth,
                        builder: (context, area) => const TreePanel(),
                      ),
                      Area(
                        min: 300,
                        builder: (context, area) => const ContentPanel(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
