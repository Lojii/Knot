import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/flow_controller.dart';
import '../../models/flow_summary.dart';
import '../../widgets/waterfall_bar.dart';
import '../../theme/app_theme.dart';

class WaterfallTab extends StatelessWidget {
  const WaterfallTab({super.key});

  @override
  Widget build(BuildContext context) {
    final flowCtrl = Get.find<FlowController>();
    final theme = Theme.of(context);

    return Obx(() {
      final flows = flowCtrl.flows.toList();
      if (flows.isEmpty) {
        return const Center(child: Text('No requests yet'));
      }

      final firstStart = flows.last.startedAt;
      final lastEnd = flows.map((f) => f.endedAt ?? f.startedAt).reduce((a, b) => a > b ? a : b);
      final totalMs = ((lastEnd - firstStart) * 1000).clamp(1.0, double.infinity);

      return Column(
        children: [
          // Legend
          Container(
            height: AppTheme.tableHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
            child: Row(
              children: [
                _legend(AppTheme.timingConnect, 'Connect'),
                _legend(AppTheme.timingTLS, 'TLS'),
                _legend(AppTheme.timingRequest, 'Request'),
                _legend(AppTheme.timingTTFB, 'TTFB'),
                _legend(AppTheme.timingResponse, 'Download'),
                const Spacer(),
                Text('${(totalMs / 1000).toStringAsFixed(1)}s total',
                    style: TextStyle(fontSize: AppTheme.fontSizeSM, color: theme.hintColor)),
              ],
            ),
          ),
          // Waterfall rows
          Expanded(
            child: ListView.builder(
              itemCount: flows.length,
              itemBuilder: (ctx, i) {
                // Display in chronological order (oldest first)
                final f = flows[flows.length - 1 - i];
                final offset = (f.startedAt - firstStart) * 1000;
                return _WaterfallRow(flow: f, totalMs: totalMs, offsetMs: offset);
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _legend(Color color, String label) => Padding(
    padding: const EdgeInsets.only(right: AppTheme.spacingMD),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: AppTheme.spacingXS),
        Text(label, style: const TextStyle(fontSize: AppTheme.fontSizeXS)),
      ],
    ),
  );
}

class _WaterfallRow extends StatelessWidget {
  final FlowSummary flow;
  final double totalMs;
  final double offsetMs;

  const _WaterfallRow({required this.flow, required this.totalMs, required this.offsetMs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.only(left: AppTheme.spacingSM),
              child: Text(
                '${flow.method} ${flow.host}${flow.uri}',
                style: const TextStyle(fontSize: AppTheme.fontSizeXS),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: WaterfallBar(
              totalDuration: totalMs,
              startOffset: offsetMs,
              connectMs: flow.durationMs != null ? flow.durationMs! * 0.15 : null,
              responseMs: flow.durationMs != null ? flow.durationMs! * 0.85 : null,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
              style: const TextStyle(fontSize: AppTheme.fontSizeXS),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: AppTheme.spacingSM),
        ],
      ),
    );
  }
}
