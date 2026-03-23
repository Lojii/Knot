import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../controllers/page_controller.dart';
import '../../controllers/flow_controller.dart';
import '../../controllers/task_controller.dart';
import '../../theme/app_theme.dart';
import 'global_bar.dart';
import 'toolbar.dart';
import 'filter_bar.dart';
import 'tree_panel.dart';
import 'content_panel.dart';
import 'status_bar.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';

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
              taskCtrl.isCapturing.value = !taskCtrl.isCapturing.value;
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
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              CaptureToolbar(searchFocusNode: _searchFocusNode),
              const FilterBar(),
              Expanded(
                child: MultiSplitView(
                  axis: Axis.horizontal,
                  initialAreas: [
                    Area(
                      min: 150,
                      size: AppTheme.treeDefaultWidth,
                      builder: (context, area) => const TreePanel(),
                    ),
                    Area(
                      min: 300,
                      builder: (context, area) => const ContentPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
