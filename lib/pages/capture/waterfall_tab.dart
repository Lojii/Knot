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
    final colors = AppTheme.colors(context);

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
            height: AppTheme.sizing.tableHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
            child: Row(
              children: [
                _legend(colors.timingConnect, 'Connect'),
                _legend(colors.timingTLS, 'TLS'),
                _legend(colors.timingRequest, 'Request'),
                _legend(colors.timingTTFB, 'TTFB'),
                _legend(colors.timingResponse, 'Download'),
                const Spacer(),
                Text('${(totalMs / 1000).toStringAsFixed(1)}s total',
                    style: TextStyle(fontSize: AppTheme.fontSize.sm, color: theme.hintColor)),
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
                return _WaterfallRow(
                  flow: f,
                  totalMs: totalMs,
                  offsetMs: offset,
                  connectColor: colors.timingConnect,
                  tlsColor: colors.timingTLS,
                  requestColor: colors.timingRequest,
                  ttfbColor: colors.timingTTFB,
                  responseColor: colors.timingResponse,
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _legend(Color color, String label) => Padding(
    padding: EdgeInsets.only(right: AppTheme.spacing.md),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        SizedBox(width: AppTheme.spacing.xs),
        Text(label, style: TextStyle(fontSize: AppTheme.fontSize.xs)),
      ],
    ),
  );
}

class _WaterfallRow extends StatelessWidget {
  final FlowSummary flow;
  final double totalMs;
  final double offsetMs;
  final Color connectColor;
  final Color tlsColor;
  final Color requestColor;
  final Color ttfbColor;
  final Color responseColor;

  const _WaterfallRow({
    required this.flow,
    required this.totalMs,
    required this.offsetMs,
    required this.connectColor,
    required this.tlsColor,
    required this.requestColor,
    required this.ttfbColor,
    required this.responseColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Padding(
              padding: EdgeInsets.only(left: AppTheme.spacing.sm),
              child: Text(
                '${flow.method} ${flow.host}${flow.uri}',
                style: TextStyle(fontSize: AppTheme.fontSize.xs),
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
              connectColor: connectColor,
              tlsColor: tlsColor,
              requestColor: requestColor,
              ttfbColor: ttfbColor,
              responseColor: responseColor,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              flow.durationMs != null ? '${flow.durationMs!.toStringAsFixed(0)}ms' : '-',
              style: TextStyle(fontSize: AppTheme.fontSize.xs),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(width: AppTheme.spacing.sm),
        ],
      ),
    );
  }
}
