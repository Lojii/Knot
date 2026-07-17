import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'hoverable.dart';

enum AppButtonVariant { primary, secondary, destructive }

/// 统一按钮。primary=实心主色（主操作）；secondary=描边（普通操作）；
/// destructive=红色文字（删除/清空）。内建 hover/pressed/光标/tooltip。
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final String? tooltip;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.secondary,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final enabled = onPressed != null;

    Widget button = Hoverable(
      onTap: onPressed,
      builder: (context, hovered) {
        final hover = hovered && enabled;
        final (Color bg, Color fg, Border? border) = switch (variant) {
          AppButtonVariant.primary => (
              hover ? colors.primary.withValues(alpha: 0.85) : colors.primary,
              Colors.white, // 有色底上的前景色，明暗模式均适用（刻意例外）
              null,
            ),
          AppButtonVariant.secondary => (
              hover ? colors.divider.withValues(alpha: 0.35) : Colors.transparent,
              colors.textPrimary,
              Border.all(color: colors.divider, width: 0.5),
            ),
          AppButtonVariant.destructive => (
              hover ? colors.diffRemoved.withValues(alpha: 0.12) : Colors.transparent,
              colors.diffRemoved,
              Border.all(color: colors.divider, width: 0.5),
            ),
        };

        return Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            height: AppTheme.sizing.searchFieldHeight,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(AppTheme.radius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppTheme.sizing.iconSize, color: fg),
                  SizedBox(width: AppTheme.spacing.xs),
                ],
                Text(label,
                    style: TextStyle(fontSize: AppTheme.fontSize.md, color: fg)),
              ],
            ),
          ),
        );
      },
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }
    return button;
  }
}
