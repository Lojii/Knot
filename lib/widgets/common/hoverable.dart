import 'package:flutter/material.dart';

/// 自定义可点击区域的 hover/光标包装器。
/// 解决 GestureDetector 无悬停反馈的问题：builder 拿到 hovered 状态自行渲染。
/// 注意：无论是否提供 onTap，本组件在命中测试中均为不透明（HitTestBehavior.opaque）。
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;

  /// 悬停光标；为 null 时根据 onTap 是否存在自动选择 click / basic。
  final MouseCursor? cursor;

  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapUp,
    this.cursor,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor ??
          (widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic),
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}
