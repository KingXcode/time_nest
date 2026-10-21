import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'apple_theme.dart';

enum _Kind { text, bordered, filled }

/// Changes the control, keeping the caller's layout, key, action and Web widget.
class AppleButton extends StatelessWidget {
  const AppleButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _Kind.text,
       icon = null,
       _alignment = IconAlignment.start;
  const AppleButton.bordered({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _Kind.bordered,
       icon = null,
       _alignment = IconAlignment.start;
  const AppleButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : _kind = _Kind.filled,
       icon = null,
       _alignment = IconAlignment.start;
  const AppleButton.textIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    IconAlignment iconAlignment = IconAlignment.start,
  }) : _kind = _Kind.text,
       child = label,
       _alignment = iconAlignment;
  const AppleButton.borderedIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    IconAlignment iconAlignment = IconAlignment.start,
  }) : _kind = _Kind.bordered,
       child = label,
       _alignment = iconAlignment;
  const AppleButton.filledIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    IconAlignment iconAlignment = IconAlignment.start,
  }) : _kind = _Kind.filled,
       child = label,
       _alignment = iconAlignment;

  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final _Kind _kind;
  final Widget child;
  final Widget? icon;
  final IconAlignment _alignment;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (!usesAppleTheme(Theme.of(context))) {
      if (icon != null) {
        return switch (_kind) {
          _Kind.text => TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon,
            label: child,
            iconAlignment: _alignment,
          ),
          _Kind.bordered => OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon,
            label: child,
            iconAlignment: _alignment,
          ),
          _Kind.filled => FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon,
            label: child,
            iconAlignment: _alignment,
          ),
        };
      }
      return switch (_kind) {
        _Kind.text => TextButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
        _Kind.bordered => OutlinedButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
        _Kind.filled => FilledButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
      };
    }
    final states = {if (onPressed == null) WidgetState.disabled};
    final themeStyle = switch (_kind) {
      _Kind.text => TextButtonTheme.of(context).style,
      _Kind.bordered => OutlinedButtonTheme.of(context).style,
      _Kind.filled => FilledButtonTheme.of(context).style,
    };
    final effective = (themeStyle ?? const ButtonStyle()).merge(style);
    final foreground =
        effective.foregroundColor?.resolve(states) ??
        (_kind == _Kind.filled ? Colors.white : appleBlue);
    final content = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_alignment == IconAlignment.start) ...[
                icon,
                const SizedBox(width: 6),
              ],
              child,
              if (_alignment == IconAlignment.end) ...[
                const SizedBox(width: 6),
                icon,
              ],
            ],
          );
    final button = CupertinoButton(
      onPressed: onPressed,
      sizeStyle: CupertinoButtonSize.small,
      minimumSize: effective.minimumSize?.resolve(states) ?? const Size(30, 30),
      padding:
          effective.padding?.resolve(states) ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color:
          effective.backgroundColor?.resolve(states) ??
          (_kind == _Kind.filled
              ? appleBlue
              : _kind == _Kind.bordered
              ? appleSurface
              : null),
      foregroundColor: foreground,
      borderRadius: BorderRadius.circular(6),
      child: DefaultTextStyle.merge(
        style:
            effective.textStyle?.resolve(states) ??
            const TextStyle(fontFamily: appleFont, fontSize: 13),
        child: content,
      ),
    );
    return _kind == _Kind.bordered
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: appleSeparator, width: .5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: button,
          )
        : button;
  }
}
