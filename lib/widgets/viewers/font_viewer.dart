import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// Font preview — loads font bytes dynamically and renders sample text.
class FontViewer extends StatefulWidget {
  final Uint8List bytes;
  final String contentType;

  const FontViewer({super.key, required this.bytes, this.contentType = ''});

  @override
  State<FontViewer> createState() => _FontViewerState();
}

class _FontViewerState extends State<FontViewer> {
  String? _fontFamily;
  bool _loading = true;
  String? _error;
  static int _counter = 0;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  Future<void> _loadFont() async {
    try {
      final family = '_preview_font_${_counter++}';
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(widget.bytes)));
      await loader.load();
      if (mounted) setState(() { _fontFamily = family; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final sizeKB = (widget.bytes.length / 1024).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(AppTheme.spacing.sm),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            border: Border.all(color: colors.divider),
          ),
          child: Row(children: [
            Icon(Icons.font_download, size: 14, color: colors.textSecondary),
            SizedBox(width: AppTheme.spacing.xs),
            Text('${widget.contentType} · $sizeKB KB',
                style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary)),
          ]),
        ),
        SizedBox(height: AppTheme.spacing.md),
        if (_loading) const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text('Cannot preview: $_error', style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary))
        else if (_fontFamily != null)
          Expanded(child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final size in [12.0, 18.0, 24.0, 36.0, 48.0]) ...[
                Text('AaBbCcDdEeFf 0123456789',
                    style: TextStyle(fontFamily: _fontFamily, fontSize: size, color: colors.textPrimary)),
                SizedBox(height: AppTheme.spacing.xs),
              ],
              SizedBox(height: AppTheme.spacing.sm),
              Text('The quick brown fox jumps over the lazy dog',
                  style: TextStyle(fontFamily: _fontFamily, fontSize: 20, color: colors.textPrimary)),
              SizedBox(height: AppTheme.spacing.xs),
              Text('ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz',
                  style: TextStyle(fontFamily: _fontFamily, fontSize: 16, color: colors.textPrimary)),
              SizedBox(height: AppTheme.spacing.xs),
              Text('!@#\$%^&*()_+-=[]{}|;:\'",.<>?/~`',
                  style: TextStyle(fontFamily: _fontFamily, fontSize: 16, color: colors.textSecondary)),
            ],
          ))),
      ],
    );
  }
}
