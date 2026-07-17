import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 统一空状态：图标 + 标题 + 可选描述 + 可选操作。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.textSecondary.withValues(alpha: 0.6)),
          SizedBox(height: AppTheme.spacing.sm),
          Text(title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: AppTheme.fontSize.md,
                fontWeight: FontWeight.w500,
              )),
          if (description != null) ...[
            SizedBox(height: AppTheme.spacing.xs),
            Text(description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary.withValues(alpha: 0.8),
                  fontSize: AppTheme.fontSize.sm,
                )),
          ],
          if (action != null) ...[
            SizedBox(height: AppTheme.spacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
