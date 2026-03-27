import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import '../../controllers/task_scope.dart';
import '../../controllers/tree_controller.dart';
import '../../models/flow_summary.dart';
import '../../theme/app_theme.dart';

const double _msPerPixel = 2.0;
const double _gapWidth = 50.0;

// ============================================================
// Smart Color Map — assigns colors by domain or path
// ============================================================

class _ColorMap {
  final Map<String, Color> mapping; // key (domain or path) → color
  final bool byDomain; // true=domain mode, false=path mode
  final List<(String, Color)> legend; // sorted legend entries

  _ColorMap({required this.mapping, required this.byDomain, required this.legend});

  Color colorFor(FlowSummary flow) {
    final key = byDomain
        ? TreeController.normalizeHost(flow.host)
        : _normalizePath(flow.uri);
    return mapping[key] ?? _fallback;
  }

  static const _fallback = Color(0xFF90A4AE);

  static String _normalizePath(String uri) {
    final parsed = Uri.tryParse(uri);
    final path = parsed?.path ?? uri;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    // Use first 2 segments as grouping key: /api/users
    if (segments.length >= 2) return '/${segments[0]}/${segments[1]}';
    if (segments.length == 1) return '/${segments[0]}';
    return '/';
  }
}

const _palette = [
  Color(0xFF4FC3F7), Color(0xFF81C784), Color(0xFFFFB74D),
  Color(0xFFE57373), Color(0xFFBA68C8), Color(0xFF4DD0E1),
  Color(0xFFFF8A65), Color(0xFFA1887F), Color(0xFFAED581),
  Color(0xFF7986CB), Color(0xFFF06292), Color(0xFF64B5F6),
  Color(0xFFDCE775), Color(0xFFCE93D8), Color(0xFF80DEEA),
];

_ColorMap _buildColorMap(List<FlowSummary> flows) {
  // Count unique domains
  final domainCounts = <String, int>{};
  for (final f in flows) {
    final h = TreeController.normalizeHost(f.host);
    domainCounts[h] = (domainCounts[h] ?? 0) + 1;
  }

  final bool byDomain = domainCounts.length > 3;

  if (byDomain) {
    // Top domains by count, assign colors
    final sorted = domainCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mapping = <String, Color>{};
    final legend = <(String, Color)>[];
    for (int i = 0; i < sorted.length && i < _palette.length; i++) {
      mapping[sorted[i].key] = _palette[i];
      legend.add((sorted[i].key, _palette[i]));
    }
    return _ColorMap(mapping: mapping, byDomain: true, legend: legend);
  } else {
    // By path prefix
    final pathCounts = <String, int>{};
    for (final f in flows) {
      final p = _ColorMap._normalizePath(f.uri);
      pathCounts[p] = (pathCounts[p] ?? 0) + 1;
    }
    final sorted = pathCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mapping = <String, Color>{};
    final legend = <(String, Color)>[];
    for (int i = 0; i < sorted.length && i < _palette.length; i++) {
      mapping[sorted[i].key] = _palette[i];
      legend.add((sorted[i].key, _palette[i]));
    }
    return _ColorMap(mapping: mapping, byDomain: false, legend: legend);
  }
}

// ============================================================
// Timeline segments
// ============================================================

class _TimeSegment {
  final double startMs, endMs;
  final bool isGap;
  final double pixelStart, pixelWidth;
  final int gapIndex;

  const _TimeSegment({
    required this.startMs, required this.endMs, required this.isGap,
    required this.pixelStart, required this.pixelWidth, this.gapIndex = -1,
  });

  double get durationMs => endMs - startMs;
  double get pixelEnd => pixelStart + pixelWidth;
}

class _BarEntry {
  final FlowSummary flow;
  final int laneIndex;
  final double pixelX, pixelW;

  const _BarEntry({
    required this.flow, required this.laneIndex,
    required this.pixelX, required this.pixelW,
  });
}

// ============================================================
// Segment builder + helpers
// ============================================================

List<_TimeSegment> _buildSegments(
    List<FlowSummary> sorted, double firstStart, double scale,
    Set<int> expandedGaps) {
  if (sorted.isEmpty) return [];

  final intervals = <(double, double)>[];
  for (final f in sorted) {
    final s = (f.startedAt - firstStart) * 1000;
    final e = s + (f.durationMs ?? 0);
    intervals.add((s, e));
  }

  const mergePadding = 100.0;
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(double, double)>[intervals.first];
  for (int i = 1; i < intervals.length; i++) {
    final last = merged.last;
    if (intervals[i].$1 <= last.$2 + mergePadding) {
      merged[merged.length - 1] = (last.$1, max(last.$2, intervals[i].$2));
    } else {
      merged.add(intervals[i]);
    }
  }

  final durations = merged.map((m) => m.$2 - m.$1).toList()..sort();
  final medianDuration = durations.isNotEmpty ? durations[durations.length ~/ 2] : 1000.0;
  final gapThreshold = max(medianDuration * 3, 500.0);

  final segments = <_TimeSegment>[];
  double px = 0;
  int gapIdx = 0;

  for (int i = 0; i < merged.length; i++) {
    final gapStart = i == 0 ? 0.0 : merged[i - 1].$2;
    final gapEnd = merged[i].$1;
    final gapMs = gapEnd - gapStart;

    bool prevWasCollapsedGap = false;
    if (gapMs > gapThreshold && !expandedGaps.contains(gapIdx)) {
      const pad = 50.0;
      final gapVisualEnd = max(gapStart, gapEnd - pad);
      segments.add(_TimeSegment(
        startMs: gapStart, endMs: gapVisualEnd,
        isGap: true, pixelStart: px, pixelWidth: _gapWidth, gapIndex: gapIdx,
      ));
      px += _gapWidth;
      gapIdx++;
      prevWasCollapsedGap = true;
    } else if (gapMs > 0) {
      if (gapMs > gapThreshold) gapIdx++;
      final w = gapMs / _msPerPixel * scale;
      segments.add(_TimeSegment(
        startMs: gapStart, endMs: gapEnd,
        isGap: false, pixelStart: px, pixelWidth: w,
      ));
      px += w;
    }

    final activeStart = prevWasCollapsedGap
        ? gapEnd - 50.0
        : max(merged[i].$1 - 50.0, i == 0 ? 0.0 : gapEnd);
    final activeEnd = merged[i].$2 + 50.0;
    final activeMs = activeEnd - activeStart;
    final activeW = activeMs / _msPerPixel * scale;
    segments.add(_TimeSegment(
      startMs: activeStart, endMs: activeEnd,
      isGap: false, pixelStart: px, pixelWidth: activeW,
    ));
    px += activeW;
  }

  return segments;
}

double _msToPixel(List<_TimeSegment> segments, double ms) {
  for (final seg in segments) {
    if (ms < seg.startMs) continue;
    if (ms <= seg.endMs) {
      if (seg.isGap) return seg.pixelStart + seg.pixelWidth / 2;
      final ratio = seg.durationMs > 0 ? (ms - seg.startMs) / seg.durationMs : 0.0;
      return seg.pixelStart + ratio * seg.pixelWidth;
    }
  }
  return segments.isNotEmpty ? segments.last.pixelEnd : 0;
}

double _totalPixelWidth(List<_TimeSegment> segments) =>
    segments.isNotEmpty ? segments.last.pixelEnd : 100;

String _formatMs(double ms) {
  if (ms < 1000) return '${ms.toInt()} ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  final min = (ms / 60000).floor();
  final sec = ((ms % 60000) / 1000).toStringAsFixed(1);
  return '${min}m ${sec}s';
}

List<_BarEntry> _buildBarEntries(
    List<List<FlowSummary>> lanes, List<_TimeSegment> segments, double firstStart, double timelineWidth) {
  final entries = <_BarEntry>[];
  for (int li = 0; li < lanes.length; li++) {
    for (final f in lanes[li]) {
      final startMs = (f.startedAt - firstStart) * 1000;
      final durationMs = f.durationMs ?? 0;
      final x = _msToPixel(segments, startMs);
      final xEnd = _msToPixel(segments, startMs + durationMs);
      final w = (xEnd - x).clamp(2.0, timelineWidth - x);
      entries.add(_BarEntry(flow: f, laneIndex: li, pixelX: x, pixelW: w));
    }
  }
  entries.sort((a, b) => a.pixelX.compareTo(b.pixelX));
  return entries;
}

List<_BarEntry> _visibleBars(List<_BarEntry> all, double viewLeft, double viewRight) {
  if (all.isEmpty) return [];

  int lo = 0, hi = all.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (all[mid].pixelX < viewLeft) { lo = mid + 1; } else { hi = mid; }
  }

  final result = <_BarEntry>[];
  for (int i = lo - 1; i >= 0; i--) {
    if (all[i].pixelX + all[i].pixelW < viewLeft) break;
    result.add(all[i]);
  }
  for (int i = lo; i < all.length; i++) {
    if (all[i].pixelX > viewRight) break;
    result.add(all[i]);
  }
  return result;
}

// ============================================================
// WaterfallTab
// ============================================================

class WaterfallTab extends StatefulWidget {
  const WaterfallTab({super.key});

  @override
  State<WaterfallTab> createState() => _WaterfallTabState();
}

class _WaterfallTabState extends State<WaterfallTab> {
  final _hScrollCtrl = ScrollController();
  final _expandedGaps = <int>{};
  late final Worker _flowsWorker;

  // Cached computation — only recomputed when flows change, not on scroll
  List<_TimeSegment> _cachedSegments = [];
  List<_BarEntry> _cachedBars = [];
  List<List<FlowSummary>> _cachedLanes = [];
  _ColorMap? _cachedColorMap;
  double _cachedTimelineWidth = 100;
  double _cachedTotalMs = 1;
  int _cachedFlowsHash = 0;

  @override
  void initState() {
    super.initState();
    _hScrollCtrl.addListener(() => setState(() {}));
    final tableCtrl = TaskScope.table;
    _flowsWorker = ever(tableCtrl.flows, (_) {
      if (_hScrollCtrl.hasClients) _hScrollCtrl.jumpTo(0);
      _expandedGaps.clear();
      _cachedFlowsHash = 0; // invalidate cache
    });
  }

  @override
  void dispose() {
    _flowsWorker.dispose();
    _hScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tableCtrl = TaskScope.table;
    final selCtrl = TaskScope.selection;
    final colors = AppTheme.colors(context);

    return Obx(() {
      selCtrl.selectedFlow.value;
      final flows = tableCtrl.flows.toList();
      if (flows.isEmpty) {
        return Center(child: Text('empty.no_requests_yet'.tr,
            style: TextStyle(color: colors.textSecondary)));
      }

      // Recompute only when flows change (not on scroll)
      final flowsHash = flows.length ^ (flows.isNotEmpty ? flows.first.flowId.hashCode : 0);
      if (flowsHash != _cachedFlowsHash) {
        _cachedFlowsHash = flowsHash;
        final sorted = List<FlowSummary>.from(flows)
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
        final firstStart = sorted.first.startedAt;
        final lastEnd = sorted.map((f) => f.endedAt ?? (f.startedAt + (f.durationMs ?? 0) / 1000)).reduce(max);
        _cachedTotalMs = ((lastEnd - firstStart) * 1000).clamp(1.0, double.infinity);
        _cachedSegments = _buildSegments(sorted, firstStart, 1.0, _expandedGaps);
        _cachedTimelineWidth = _totalPixelWidth(_cachedSegments);
        _cachedLanes = _packIntoLanes(sorted, firstStart);
        _cachedBars = _buildBarEntries(_cachedLanes, _cachedSegments, firstStart, _cachedTimelineWidth);
        _cachedColorMap = _buildColorMap(sorted);
      }

      final segments = _cachedSegments;
      final timelineWidth = _cachedTimelineWidth;
      final totalMs = _cachedTotalMs;
      final lanes = _cachedLanes;
      final allBars = _cachedBars;
      final colorMap = _cachedColorMap!;

      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, outerConstraints) {
              final viewportWidth = outerConstraints.maxWidth;
              final viewLeft = _hScrollCtrl.hasClients ? _hScrollCtrl.offset : 0.0;
              final viewRight = viewLeft + viewportWidth;
              final visibleBars = _visibleBars(allBars, viewLeft, viewRight);

              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final newOffset = _hScrollCtrl.offset + event.scrollDelta.dy;
                    _hScrollCtrl.jumpTo(newOffset.clamp(0, _hScrollCtrl.position.maxScrollExtent));
                  }
                },
                child: Scrollbar(
                  controller: _hScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _hScrollCtrl,
                    child: SizedBox(
                      width: timelineWidth,
                      child: Column(
                        children: [
                          CustomPaint(
                            size: Size(timelineWidth, 24),
                            painter: _RulerPainter(
                              segments: segments,
                              timelineWidth: timelineWidth,
                              textColor: colors.textSecondary,
                              lineColor: colors.divider,
                              viewLeft: viewLeft,
                              viewRight: viewRight,
                            ),
                          ),
                          Container(height: 0.5, color: colors.divider),
                          Expanded(
                            child: LayoutBuilder(builder: (context, constraints) {
                              final availH = constraints.maxHeight;
                              final visibleLaneIds = visibleBars.map((b) => b.laneIndex).toSet();
                              final activeLaneCount = visibleLaneIds.isNotEmpty ? visibleLaneIds.length : 1;
                              final totalLaneCount = lanes.length.clamp(1, 9999);
                              final laneH = (availH / activeLaneCount).clamp(2.0, 24.0);

                              final sortedActiveLanes = visibleLaneIds.toList()..sort();
                              final hitLaneMap = <int, int>{};
                              for (int i = 0; i < sortedActiveLanes.length; i++) {
                                hitLaneMap[sortedActiveLanes[i]] = i;
                              }

                              return Stack(
                                children: [
                                  CustomPaint(
                                    size: Size(timelineWidth, availH),
                                    painter: _LanesPainter(
                                      bars: visibleBars,
                                      colors: colors,
                                      colorMap: colorMap,
                                      selectedFlowId: selCtrl.selectedFlow.value?.flowId,
                                      laneHeight: laneH,
                                      laneCount: totalLaneCount,
                                      activeLaneIds: visibleLaneIds,
                                    ),
                                  ),
                                  ...segments
                                      .where((s) => s.isGap && s.pixelEnd > viewLeft && s.pixelStart < viewRight)
                                      .map((seg) => Positioned(
                                        left: seg.pixelStart, top: 0,
                                        width: seg.pixelWidth, height: availH,
                                        child: _GapMarker(
                                          durationMs: seg.durationMs, colors: colors,
                                          onTap: () => setState(() { _expandedGaps.add(seg.gapIndex); }),
                                        ),
                                      )),
                                  ...visibleBars.map((bar) {
                                    final y = (hitLaneMap[bar.laneIndex] ?? 0) * laneH;
                                    final tip = '${bar.flow.method} ${bar.flow.host}${bar.flow.uri}\n'
                                        '${bar.flow.statusCode} · ${(bar.flow.durationMs ?? 0).toStringAsFixed(0)} ms';
                                    return Positioned(
                                      left: bar.pixelX, top: y,
                                      width: max(bar.pixelW, 8), height: laneH,
                                      child: Tooltip(
                                        message: tip,
                                        waitDuration: const Duration(milliseconds: 300),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => selCtrl.select(bar.flow),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          // Bottom: 0 (left) + legend (center, expandable) + total (right)
          Container(
            height: 24,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm),
            child: Row(
              children: [
                Text('0', style: TextStyle(fontSize: AppTheme.fontSize.xs, color: colors.textSecondary)),
                const SizedBox(width: 8),
                // Legend — scrollable, only takes available space
                Expanded(
                  child: _BottomLegend(legend: colorMap.legend, colors: colors),
                ),
                const SizedBox(width: 8),
                Text(_formatMs(totalMs),
                    style: TextStyle(fontSize: AppTheme.fontSize.xs, color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    });
  }

  List<List<FlowSummary>> _packIntoLanes(List<FlowSummary> sorted, double firstStart) {
    final lanes = <List<FlowSummary>>[];
    final laneEnds = <double>[];
    for (final f in sorted) {
      final startMs = (f.startedAt - firstStart) * 1000;
      final endMs = startMs + (f.durationMs ?? 0);
      int? target;
      for (int i = 0; i < laneEnds.length; i++) {
        if (laneEnds[i] <= startMs) { target = i; break; }
      }
      if (target != null) {
        lanes[target].add(f);
        laneEnds[target] = endMs;
      } else {
        lanes.add([f]);
        laneEnds.add(endMs);
      }
    }
    return lanes;
  }
}

// ============================================================
// Bottom Legend — horizontal scroll, hover to see full list
// ============================================================

class _BottomLegend extends StatelessWidget {
  final List<(String, Color)> legend;
  final ThemeColors colors;
  const _BottomLegend({required this.legend, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (legend.isEmpty) return const SizedBox();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in legend)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: entry.$2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 3),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      entry.$1,
                      style: TextStyle(fontSize: 9, color: colors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Gap Marker
// ============================================================

class _GapMarker extends StatelessWidget {
  final double durationMs;
  final ThemeColors colors;
  final VoidCallback onTap;
  const _GapMarker({required this.durationMs, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap, behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: 'waterfall.expand_gap'.trParams({'duration': _formatMs(durationMs)}),
          child: CustomPaint(
            painter: _ZigzagPainter(
              zigzagColor: colors.textSecondary.withAlpha(100),
              iconColor: colors.textSecondary.withAlpha(160),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZigzagPainter extends CustomPainter {
  final Color zigzagColor, iconColor;
  _ZigzagPainter({required this.zigzagColor, required this.iconColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = zigzagColor..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const tooth = 4.0;
    final lp = Path()..moveTo(tooth, 0);
    for (double y = 0; y < size.height; y += tooth * 2) {
      lp.lineTo(0, y + tooth); lp.lineTo(tooth, y + tooth * 2);
    }
    canvas.drawPath(lp, paint);
    final rp = Path()..moveTo(size.width - tooth, 0);
    for (double y = 0; y < size.height; y += tooth * 2) {
      rp.lineTo(size.width, y + tooth); rp.lineTo(size.width - tooth, y + tooth * 2);
    }
    canvas.drawPath(rp, paint);
    final cx = size.width / 2, cy = size.height / 2;
    final ap = Paint()..color = iconColor..strokeWidth = 1.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 3, cy - 4), Offset(cx - 6, cy), ap);
    canvas.drawLine(Offset(cx - 6, cy), Offset(cx - 3, cy + 4), ap);
    canvas.drawLine(Offset(cx + 3, cy - 4), Offset(cx + 6, cy), ap);
    canvas.drawLine(Offset(cx + 6, cy), Offset(cx + 3, cy + 4), ap);
  }

  @override
  bool shouldRepaint(covariant _ZigzagPainter old) =>
      zigzagColor != old.zigzagColor || iconColor != old.iconColor;
}

// ============================================================
// Ruler Painter (viewport-culled)
// ============================================================

class _RulerPainter extends CustomPainter {
  final List<_TimeSegment> segments;
  final double timelineWidth, viewLeft, viewRight;
  final Color textColor, lineColor;

  _RulerPainter({required this.segments, required this.timelineWidth,
    required this.textColor, required this.lineColor,
    required this.viewLeft, required this.viewRight});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()..color = lineColor..strokeWidth = 0.5;
    final textStyle = TextStyle(fontSize: 9, color: textColor);
    final gapTextStyle = TextStyle(fontSize: 8, color: textColor, fontStyle: FontStyle.italic);

    for (final seg in segments) {
      if (seg.pixelEnd < viewLeft || seg.pixelStart > viewRight) continue;

      if (seg.isGap) {
        final zigPaint = Paint()..color = textColor.withAlpha(100)..strokeWidth = 1.5..style = PaintingStyle.stroke;
        const t = 3.0;
        final lp = Path()..moveTo(seg.pixelStart + t, 0);
        for (double y = 0; y < size.height; y += t * 2) {
          lp.lineTo(seg.pixelStart, y + t); lp.lineTo(seg.pixelStart + t, y + t * 2);
        }
        canvas.drawPath(lp, zigPaint);
        final rp = Path()..moveTo(seg.pixelStart + seg.pixelWidth - t, 0);
        for (double y = 0; y < size.height; y += t * 2) {
          rp.lineTo(seg.pixelStart + seg.pixelWidth, y + t);
          rp.lineTo(seg.pixelStart + seg.pixelWidth - t, y + t * 2);
        }
        canvas.drawPath(rp, zigPaint);
        final label = _formatMs(seg.durationMs);
        final tp = TextPainter(text: TextSpan(text: label, style: gapTextStyle), textDirection: TextDirection.ltr)..layout();
        if (tp.width < seg.pixelWidth - 2) {
          tp.paint(canvas, Offset(seg.pixelStart + (seg.pixelWidth - tp.width) / 2, (size.height - tp.height) / 2));
        }
      } else if (seg.durationMs > 0) {
        final tickInterval = _niceInterval(seg.durationMs / max(seg.pixelWidth / 60, 1));
        final firstTick = (seg.startMs / tickInterval).ceil() * tickInterval;
        for (double ms = firstTick; ms <= seg.endMs; ms += tickInterval) {
          final x = seg.pixelStart + (ms - seg.startMs) / seg.durationMs * seg.pixelWidth;
          if (x < viewLeft - 50 || x > viewRight + 50) continue;
          canvas.drawLine(Offset(x, size.height - 6), Offset(x, size.height), linePaint);
          final tp = TextPainter(text: TextSpan(text: _formatMs(ms), style: textStyle), textDirection: TextDirection.ltr)..layout();
          if (x + tp.width + 2 < seg.pixelStart + seg.pixelWidth) {
            tp.paint(canvas, Offset(x + 2, 2));
          }
        }
      }
    }
  }

  double _niceInterval(double raw) {
    const v = [1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000];
    for (final n in v) { if (n >= raw) return n.toDouble(); }
    return raw.clamp(1, double.infinity);
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => true;
}

// ============================================================
// Lanes Painter — smart color, adaptive text, status markers
// ============================================================

class _LanesPainter extends CustomPainter {
  final List<_BarEntry> bars;
  final ThemeColors colors;
  final _ColorMap colorMap;
  final String? selectedFlowId;
  final double laneHeight;
  final int laneCount;
  final Set<int> activeLaneIds;

  _LanesPainter({
    required this.bars, required this.colors, required this.colorMap,
    required this.laneHeight, required this.laneCount,
    required this.activeLaneIds, this.selectedFlowId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barH = laneHeight * 0.9;
    final sortedLanes = activeLaneIds.toList()..sort();
    final laneMap = <int, int>{};
    for (int i = 0; i < sortedLanes.length; i++) {
      laneMap[sortedLanes[i]] = i;
    }

    for (final bar in bars) {
      final compactIdx = laneMap[bar.laneIndex] ?? 0;
      final laneY = compactIdx * laneHeight;
      final barY = laneY + (laneHeight - barH) / 2;
      final barColor = colorMap.colorFor(bar.flow);
      final isSelected = bar.flow.flowId == selectedFlowId;
      final statusCode = int.tryParse(bar.flow.statusCode) ?? 0;

      // Selection highlight
      if (isSelected) {
        canvas.drawRect(
          Rect.fromLTWH(bar.pixelX - 1, laneY, bar.pixelW + 2, laneHeight),
          Paint()..color = colors.primary.withAlpha(30),
        );
      }

      // Bar body
      final barRect = Rect.fromLTWH(bar.pixelX, barY, bar.pixelW, barH);
      final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(2));
      canvas.drawRRect(rrect, Paint()..color = (isSelected ? barColor : barColor.withAlpha(200)));

      // Status code markers
      if (statusCode >= 500) {
        // 5xx: diagonal hatching
        canvas.save();
        canvas.clipRRect(rrect);
        final hatchPaint = Paint()..color = const Color(0x40000000)..strokeWidth = 1;
        for (double d = -barH; d < bar.pixelW + barH; d += 4) {
          canvas.drawLine(
            Offset(bar.pixelX + d, barY + barH),
            Offset(bar.pixelX + d + barH, barY),
            hatchPaint,
          );
        }
        canvas.restore();
      } else if (statusCode >= 400) {
        // 4xx: small warning triangle at left edge
        final triSize = min(barH * 0.5, 6.0);
        final triPath = Path()
          ..moveTo(bar.pixelX + 2, barY + barH - 1)
          ..lineTo(bar.pixelX + 2 + triSize, barY + barH - 1)
          ..lineTo(bar.pixelX + 2 + triSize / 2, barY + barH - 1 - triSize)
          ..close();
        canvas.drawPath(triPath, Paint()..color = const Color(0xCCFFFFFF));
      } else if (statusCode >= 300) {
        // 3xx: dashed top border
        final dashPaint = Paint()..color = const Color(0x60FFFFFF)..strokeWidth = 1;
        for (double x = bar.pixelX; x < bar.pixelX + bar.pixelW; x += 4) {
          canvas.drawLine(Offset(x, barY), Offset(min(x + 2, bar.pixelX + bar.pixelW), barY), dashPaint);
        }
      }

      // Selection border
      if (isSelected) {
        canvas.drawRRect(rrect, Paint()
          ..color = colors.primary..style = PaintingStyle.stroke..strokeWidth = 1);
      }

      // Text on bar: METHOD STATUS URL, auto ellipsis, hidden when too thin
      if (barH >= 10 && bar.pixelW > 20) {
        final flow = bar.flow;
        final label = '${flow.method} ${flow.statusCode} ${flow.uri}';
        final fontSize = min(barH * 0.65, 10.0);

        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
          maxLines: 1,
          ellipsis: '…',
        ))..pushStyle(ui.TextStyle(
          color: const Color(0xE0FFFFFF),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ))..addText(label);
        final paragraph = pb.build()
          ..layout(ui.ParagraphConstraints(width: bar.pixelW - 4));

        canvas.drawParagraph(paragraph,
          Offset(bar.pixelX + 2, barY + (barH - paragraph.height) / 2));
      }
    }

    // Lane grid lines
    final gridPaint = Paint()..color = colors.divider.withAlpha(30);
    for (int i = 1; i < sortedLanes.length; i++) {
      canvas.drawLine(Offset(0, i * laneHeight), Offset(size.width, i * laneHeight), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LanesPainter old) => true;
}
