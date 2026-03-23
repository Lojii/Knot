import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../controllers/page_controller.dart';
import '../../theme/app_theme.dart';
import 'global_bar.dart';
import 'toolbar.dart';
import 'filter_bar.dart';
import 'tree_panel.dart';
import 'content_panel.dart';
import 'status_bar.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';

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

class _CaptureContent extends StatelessWidget {
  const _CaptureContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CaptureToolbar(),
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
    );
  }
}
