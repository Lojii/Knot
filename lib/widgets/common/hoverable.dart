import 'package:flutter/material.dart';

/// 自定义可点击区域的 hover/光标包装器。
/// 解决 GestureDetector 无悬停反馈的问题：builder 拿到 hovered 状态自行渲染。
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final MouseCursor cursor;

  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTapUp,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
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
