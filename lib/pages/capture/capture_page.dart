import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import '../../theme/app_theme.dart';
import 'global_bar.dart';
import 'toolbar.dart';
import 'filter_bar.dart';
import 'tree_panel.dart';
import 'content_panel.dart';
import 'status_bar.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const GlobalBar(),
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
          const CaptureStatusBar(),
        ],
      ),
    );
  }
}
