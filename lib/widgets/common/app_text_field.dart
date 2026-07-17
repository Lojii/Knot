import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 统一输入框：isDense、radius.md 圆角、divider 边框、聚焦主色边框。
/// 取代各页手写的 InputDecoration。
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int maxLines;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLines = 1,
  });

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius.md),
        borderSide: BorderSide(color: color, width: 0.5),
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      style: TextStyle(fontSize: AppTheme.fontSize.md),
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffix: suffix,
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacing.sm,
          vertical: AppTheme.spacing.sm,
        ),
        border: _border(colors.divider),
        enabledBorder: _border(colors.divider),
        focusedBorder: _border(colors.primary),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
