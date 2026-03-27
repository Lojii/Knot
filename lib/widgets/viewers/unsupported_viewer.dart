import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/magic_bytes.dart';

/// Fallback viewer for unsupported file types — shows type, size, hex preview.
class UnsupportedViewer extends StatelessWidget {
  final Uint8List bytes;
  final String contentType;

  const UnsupportedViewer({super.key, required this.bytes, this.contentType = ''});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final detected = detectFileType(bytes);
    final displayType = contentType.isNotEmpty ? contentType : (detected?.mime ?? 'unknown');
    final ext = detected?.ext ?? '';
    final sizeStr = _formatSize(bytes.length);

    return Center(
      child: Container(
        padding: EdgeInsets.all(AppTheme.spacing.lg),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 40, color: colors.textSecondary),
            SizedBox(height: AppTheme.spacing.md),
            Text(displayType,
                style: TextStyle(fontSize: AppTheme.fontSize.lg, fontWeight: FontWeight.w500, color: colors.textPrimary)),
            if (ext.isNotEmpty) ...[
              SizedBox(height: AppTheme.spacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(AppTheme.radius.sm),
                ),
                child: Text('.$ext',
                    style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.primary, fontWeight: FontWeight.w500)),
              ),
            ],
            SizedBox(height: AppTheme.spacing.sm),
            Text(sizeStr, style: TextStyle(fontSize: AppTheme.fontSize.sm, color: colors.textSecondary)),
            SizedBox(height: AppTheme.spacing.md),
            Text('Preview not available',
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
