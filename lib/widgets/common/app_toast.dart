import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

OverlayEntry? _activeToast;
Timer? _dismissTimer;

/// 全局浮动提示：复制/导出/保存成功后的轻量反馈。
/// 基于 Overlay，不依赖 ScaffoldMessenger；约 2 秒自动消失；新提示替换旧提示。
void showAppToast(BuildContext context, String message,
    {IconData icon = Icons.check_circle_outline}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  _dismissTimer?.cancel();
  _activeToast?.remove();
  _activeToast = null;

  final entry = OverlayEntry(
    builder: (ctx) {
      final colors = AppTheme.colors(ctx);
      return Positioned(
        bottom: 48,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing.lg,
                  vertical: AppTheme.spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius.popup),
                  border: Border.all(color: colors.divider, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: AppTheme.sizing.iconSize, color: colors.primary),
                    SizedBox(width: AppTheme.spacing.sm),
                    Text(message,
                        style: TextStyle(
                          fontSize: AppTheme.fontSize.md,
                          color: colors.textPrimary,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeToast = entry;
  overlay.insert(entry);
  _dismissTimer = Timer(const Duration(seconds: 2), () {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
    }
  });
}
