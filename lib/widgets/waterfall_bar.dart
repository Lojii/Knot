import 'package:flutter/material.dart';

class WaterfallBar extends StatelessWidget {
  final double totalDuration;  // total time range in ms
  final double startOffset;    // when this request started relative to first request
  final double? connectMs;
  final double? tlsMs;
  final double? requestMs;
  final double? ttfbMs;
  final double? responseMs;
  final Color connectColor;
  final Color tlsColor;
  final Color requestColor;
  final Color ttfbColor;
  final Color responseColor;

  const WaterfallBar({
    super.key,
    required this.totalDuration,
    required this.startOffset,
    this.connectMs,
    this.tlsMs,
    this.requestMs,
    this.ttfbMs,
    this.responseMs,
    required this.connectColor,
    required this.tlsColor,
    required this.requestColor,
    required this.ttfbColor,
    required this.responseColor,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDuration <= 0) return const SizedBox(height: 14);

    return SizedBox(
      height: 14,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WaterfallPainter(
          totalDuration: totalDuration,
          startOffset: startOffset,
          connectMs: connectMs ?? 0,
          tlsMs: tlsMs ?? 0,
          requestMs: requestMs ?? 0,
          ttfbMs: ttfbMs ?? 0,
          responseMs: responseMs ?? 0,
          connectColor: connectColor,
          tlsColor: tlsColor,
          requestColor: requestColor,
          ttfbColor: ttfbColor,
          responseColor: responseColor,
        ),
      ),
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  final double totalDuration, startOffset;
  final double connectMs, tlsMs, requestMs, ttfbMs, responseMs;
  final Color connectColor, tlsColor, requestColor, ttfbColor, responseColor;

  _WaterfallPainter({
    required this.totalDuration, required this.startOffset,
    required this.connectMs, required this.tlsMs,
    required this.requestMs, required this.ttfbMs,
    required this.responseMs,
    required this.connectColor,
    required this.tlsColor,
    required this.requestColor,
    required this.ttfbColor,
    required this.responseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double x = (startOffset / totalDuration) * w;

    void drawSegment(double ms, Color color) {
      if (ms <= 0) return;
      final segW = (ms / totalDuration) * w;
      canvas.drawRect(
        Rect.fromLTWH(x, 2, segW.clamp(1, w - x), h - 4),
        Paint()..color = color,
      );
      x += segW;
    }

    drawSegment(connectMs, connectColor);
    drawSegment(tlsMs, tlsColor);
    drawSegment(requestMs, requestColor);
    drawSegment(ttfbMs, ttfbColor);
    drawSegment(responseMs, responseColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
