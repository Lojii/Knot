import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_theme.dart';

/// Image viewer — handles raster images via Image.memory, SVG via flutter_svg.
class ImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String contentType;
  final bool isSvg;

  const ImageViewer({
    super.key,
    required this.bytes,
    this.contentType = '',
    this.isSvg = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final sizeKB = (bytes.length / 1024).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Meta bar
        Container(
          padding: EdgeInsets.all(AppTheme.spacing.sm),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius.sm),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.image, size: 14, color: colors.textSecondary),
              SizedBox(width: AppTheme.spacing.xs),
              Text('$contentType · $sizeKB KB',
                  style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary)),
            ],
          ),
        ),
        SizedBox(height: AppTheme.spacing.sm),
        // Image
        Expanded(
          child: Center(
            child: isSvg ? _svgView(context) : _rasterView(context),
          ),
        ),
      ],
    );
  }

  Widget _rasterView(BuildContext context) {
    return InteractiveViewer(
      maxScale: 10,
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, error, _) => _errorWidget(context, '$error'),
      ),
    );
  }

  Widget _svgView(BuildContext context) {
    try {
      return InteractiveViewer(
        maxScale: 10,
        child: SvgPicture.memory(bytes, fit: BoxFit.contain),
      );
    } catch (e) {
      return _errorWidget(context, '$e');
    }
  }

  Widget _errorWidget(BuildContext context, String msg) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image, size: 32, color: AppTheme.colors(context).textSecondary),
        SizedBox(height: AppTheme.spacing.sm),
        Text(msg, style: TextStyle(fontSize: AppTheme.fontSize.sm, color: AppTheme.colors(context).textSecondary)),
      ],
    );
  }
}
