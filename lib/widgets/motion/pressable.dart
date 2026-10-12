import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Shrinks [child] slightly while it's pressed and springs back on release:
/// tactile feedback for cards and covers (the app's ink ripples are
/// transparent). Only a transform is animated, so it never causes a layout,
/// and a press that turns into a scroll doesn't shrink anything. Without
/// [onTap] and [onLongPress] it is just [child].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How small [child] gets while pressed.
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: AppMotion.of(context, AppMotion.short),
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}
