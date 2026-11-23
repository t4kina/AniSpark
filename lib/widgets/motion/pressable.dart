import 'package:flutter/material.dart';

import 'press_effect.dart';

/// Makes [child] answer a finger: it shrinks slightly while pressed and
/// springs back on release (the app's ink ripples are transparent, so this
/// is the tap feedback of cards, covers and chips). A press that turns into
/// a scroll doesn't shrink anything. Without [onTap] and [onLongPress] it is
/// just [child].
///
/// Scaling suits things with an edge. For bare text or a small icon, which
/// have no shape to shrink, use [Pressable.dim].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.pressedOpacity = 1,
  });

  /// For text links and bare icons: fades while pressed instead of shrinking.
  const Pressable.dim({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  })  : pressedScale = 1,
        pressedOpacity = 0.45;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How small [child] gets while pressed.
  final double pressedScale;

  /// How faint [child] gets while pressed.
  final double pressedOpacity;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  final _pressed = ValueNotifier(false);

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _pressed.value = true,
      onTapUp: (_) => _pressed.value = false,
      onTapCancel: () => _pressed.value = false,
      child: PressEffect(
        pressed: _pressed,
        scale: widget.pressedScale,
        opacity: widget.pressedOpacity,
        child: widget.child,
      ),
    );
  }
}
