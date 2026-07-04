import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/app_theme.dart';
import '../utils/magic_bytes.dart';
import 'viewers/code_viewer.dart';
import 'viewers/image_viewer.dart';
import 'viewers/font_viewer.dart';
import 'viewers/hex_viewer.dart';
import 'viewers/media_info_viewer.dart';
import 'viewers/form_viewer.dart';
import 'viewers/unsupported_viewer.dart';

enum BodyViewMode { pretty, raw, hex }

// ── Content category ──

enum ContentCategory { json, html, css, javascript, xml, svgXml, image, video, audio, font, formUrlEncoded, text, binary }

ContentCategory categorizeContent(String contentType) {
  final ct = contentType.toLowerCase();
  if (ct.contains('json')) return ContentCategory.json;
  if (ct.contains('svg+xml')) return ContentCategory.svgXml;
  if (ct.contains('html')) return ContentCategory.html;
  if (ct.contains('css')) return ContentCategory.css;
  if (ct.contains('javascript') || ct.contains('ecmascript')) return ContentCategory.javascript;
  if (ct.contains('xml')) return ContentCategory.xml;
  if (ct.contains('x-www-form-urlencoded')) return ContentCategory.formUrlEncoded;
  if (ct.contains('image/')) return ContentCategory.image;
  if (ct.contains('video/')) return ContentCategory.video;
  if (ct.contains('audio/')) return ContentCategory.audio;
  if (ct.contains('font/') || ct.contains('font-woff') || ct.contains('font-ttf') || ct.contains('font-otf')) return ContentCategory.font;
  if (ct.contains('text/')) return ContentCategory.text;
  return ContentCategory.binary;
}

/// Try to resolve binary to a known category via magic bytes.
ContentCategory _resolveCategory(Uint8List bytes, String contentType) {
  final fromHeader = categorizeContent(contentType);
  if (fromHeader != ContentCategory.binary) return fromHeader;

  // Magic bytes fallback
  final detected = detectFileType(bytes);
  if (detected != null) {
    final fromMagic = categorizeContent(detected.mime);
    if (fromMagic != ContentCategory.binary) return fromMagic;
  }

  // Text heuristic (sniff only the head — bodies can be huge)
  if (_looksLikeText(bytes)) {
    final head = bytes.length > 512 ? Uint8List.sublistView(bytes, 0, 512) : bytes;
    final text = _decodeText(head).trimLeft();
    if (text.startsWith('{') || text.startsWith('[')) return ContentCategory.json;
    return ContentCategory.text;
  }

  return ContentCategory.binary;
}

// ── Main BodyViewer ──

class BodyViewer extends StatefulWidget {
  final Uint8List? bytes;
  final String contentType;
  final String label;

  const BodyViewer({super.key, required this.bytes, this.contentType = '', this.label = ''});

  @override
  State<BodyViewer> createState() => _BodyViewerState();
}

class _BodyViewerState extends State<BodyViewer> {
  BodyViewMode _viewMode = BodyViewMode.pretty;

  @override
  Widget build(BuildContext context) {
    if (widget.bytes == null || widget.bytes!.isEmpty) {
      return Text('body.empty'.tr, style: TextStyle(
        color: Theme.of(context).hintColor, fontSize: AppTheme.fontSize.sm));
    }

    // Viewers scroll internally (virtualized), so they need bounded height.
    // Inside an unbounded parent (e.g. SingleChildScrollView) fall back to a
    // fixed-height box instead of Expanded.
    return LayoutBuilder(builder: (context, constraints) {
      final bounded = constraints.hasBoundedHeight;
      return Column(
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _modeToggle(context),
          SizedBox(height: AppTheme.spacing.xs),
          if (bounded)
            Expanded(child: _body(context))
          else
            SizedBox(height: 400, child: _body(context)),
        ],
      );
    });
  }

  Widget _modeToggle(BuildContext context) {
    final chip = AppTheme.mode(context).filterChip;
    return Row(
      children: BodyViewMode.values.map((mode) {
        final isActive = _viewMode == mode;
        final label = switch (mode) {
          BodyViewMode.pretty => 'tab.pretty'.tr,
          BodyViewMode.raw => 'tab.raw'.tr,
          BodyViewMode.hex => 'tab.hex'.tr,
        };
        return Padding(
          padding: EdgeInsets.only(right: AppTheme.spacing.xs),
          child: GestureDetector(
            onTap: () => setState(() => _viewMode = mode),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? chip.activeBackground : chip.inactiveBackground,
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                  border: Border.all(
                    color: isActive ? chip.activeBorder : chip.inactiveBorder, width: 0.5),
                ),
                child: Text(label, style: TextStyle(
                  fontSize: AppTheme.fontSize.sm,
                  color: isActive ? chip.activeText : null)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _body(BuildContext context) {
    final bytes = widget.bytes!;

    switch (_viewMode) {
      case BodyViewMode.raw:
        return CodeViewer(bytes: bytes, formatJson: false, showLineNumbers: false);
      case BodyViewMode.hex:
        return SingleChildScrollView(child: HexViewer(bytes: bytes));
      case BodyViewMode.pretty:
        return _prettyView(context, bytes);
    }
  }

  Widget _prettyView(BuildContext context, Uint8List bytes) {
    final category = _resolveCategory(bytes, widget.contentType);
    final ct = widget.contentType;

    switch (category) {
      case ContentCategory.json:
        return CodeViewer(bytes: bytes, language: 'json');
      case ContentCategory.html:
        return CodeViewer(bytes: bytes, language: 'html');
      case ContentCategory.css:
        return CodeViewer(bytes: bytes, language: 'css');
      case ContentCategory.javascript:
        return CodeViewer(bytes: bytes, language: 'javascript');
      case ContentCategory.xml:
        return CodeViewer(bytes: bytes, language: 'xml');
      case ContentCategory.svgXml:
        return ImageViewer(bytes: bytes, contentType: ct, isSvg: true);
      case ContentCategory.image:
        return ImageViewer(bytes: bytes, contentType: ct);
      case ContentCategory.font:
        return FontViewer(bytes: bytes, contentType: ct);
      case ContentCategory.video:
        return MediaInfoViewer(bytes: bytes, contentType: ct, mediaType: 'Video');
      case ContentCategory.audio:
        return MediaInfoViewer(bytes: bytes, contentType: ct, mediaType: 'Audio');
      case ContentCategory.formUrlEncoded:
        return FormViewer(bytes: bytes);
      case ContentCategory.text:
        return CodeViewer(bytes: bytes, formatJson: false, showLineNumbers: false);
      case ContentCategory.binary:
        return UnsupportedViewer(bytes: bytes, contentType: ct);
    }
  }
}

// ── Helpers ──

String _decodeText(Uint8List bytes) {
  try { return utf8.decode(bytes); } catch (_) { return latin1.decode(bytes); }
}

bool _looksLikeText(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sample = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
  int p = 0;
  for (final b in sample) {
    if ((b >= 32 && b <= 126) || b == 10 || b == 13 || b == 9) p++;
  }
  return p / sample.length > 0.85;
}
