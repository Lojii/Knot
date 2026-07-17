import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'hoverable.dart';

/// 统一分段式 Tab（macOS segmented control 观感）。
/// 选中项 = detailTab.activeBackground 胶囊；未选中 hover 时浅背景。
/// 可选 [label] 在最左侧显示分组标签（如 REQUEST / RESPONSE）。
class AppTabBar extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final String? label;
  final double? fontSize;

  /// 胶囊水平内边距；为 null 时使用 spacing.md。密集场景（详情面板）传 spacing.sm。
  final double? horizontalPadding;

  const AppTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
    this.label,
    this.fontSize,
    this.horizontalPadding,
  });

  @override
  Widget build(BuildContext context) {
    final detailTab = AppTheme.mode(context).detailTab;
    final size = fontSize ?? AppTheme.fontSize.sm;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!,
              style: TextStyle(
                fontSize: AppTheme.fontSize.xs,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppTheme.colors(context).textSecondary,
              )),
          SizedBox(width: AppTheme.spacing.sm),
        ],
        ...List.generate(tabs.length, (i) {
          final isActive = activeIndex == i;
          return Padding(
            padding: EdgeInsets.only(right: i < tabs.length - 1 ? 2 : 0),
            child: Semantics(
              button: true,
              selected: isActive,
              label: tabs[i],
              child: Hoverable(
                onTap: () => onChanged(i),
                builder: (context, hovered) => Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding ?? AppTheme.spacing.md,
                      vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? detailTab.activeBackground
                        : hovered
                            ? detailTab.activeBackground.withValues(alpha: 0.5)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(detailTab.radius),
                  ),
                  child: Text(tabs[i],
                      style: TextStyle(
                        fontSize: size,
                        fontWeight:
                            isActive ? FontWeight.w500 : FontWeight.normal,
                        color: isActive
                            ? detailTab.activeText
                            : detailTab.inactiveText,
                      )),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
