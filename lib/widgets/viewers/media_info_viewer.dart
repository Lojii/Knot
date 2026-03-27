import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Info card for video/audio — shows type, size, no inline playback.
class MediaInfoViewer extends StatelessWidget {
  final Uint8List bytes;
  final String contentType;
  final String mediaType; // 'Video' or 'Audio'

  const MediaInfoViewer({
    super.key,
    required this.bytes,
    this.contentType = '',
    this.mediaType = 'Media',
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final sizeStr = _formatSize(bytes.length);

    return Center(
      child: Container(
        padding: EdgeInsets.all(AppTheme.spacing.lg),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mediaType == 'Video' ? Icons.videocam : Icons.audiotrack,
              size: 40, color: colors.textSecondary,
            ),
            SizedBox(height: AppTheme.spacing.md),
            Text(mediaType,
                style: TextStyle(fontSize: AppTheme.fontSize.lg, fontWeight: FontWeight.w500, color: colors.textPrimary)),
            SizedBox(height: AppTheme.spacing.xs),
            Text(contentType,
                style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary)),
            SizedBox(height: AppTheme.spacing.xs),
            Text(sizeStr,
                style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
