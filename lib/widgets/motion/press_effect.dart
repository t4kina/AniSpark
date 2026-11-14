import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../theme/app_motion.dart';

/// How [child] looks while [pressed]: a little smaller, a little dimmer, or
/// both. It goes down fast and comes back on a spring, so letting go has a
/// small rebound instead of a flat ease.
///
/// A quick tap lifts the finger before anything could be seen (down and up
/// often arrive in the same frame, which is why [pressed] is listened to
/// rather than rebuilt from); the press is then played to the end before it
/// is released, so every tap is answered.
///
/// Only a transform and an opacity change, never the layout, and only this
/// widget repaints. It handles no gestures itself: see `Pressable` and
/// `PressScale`.
class PressEffect extends StatefulWidget {
  const PressEffect({
    super.key,
    required this.pressed,
    required this.child,
    this.scale = 0.96,
    this.opacity = 1,
  });

  final ValueListenable<bool> pressed;
  final Widget child;

  /// How small [child] gets while pressed (1 leaves its size alone).
  final double scale;

  /// How faint [child] gets while pressed (1 leaves it alone).
  final double opacity;

  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> with SingleTickerProviderStateMixin {
  /// Going down is quicker than any token: it has to keep up with a finger.
  static const _pressIn = Duration(milliseconds: 90);

  /// 0 at rest, 1 fully pressed. Unbounded, so the spring can overshoot.
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  TickerFuture? _pressingIn;

  @override
  void initState() {
    super.initState();
    if (widget.pressed.value) _press.value = 1;
    widget.pressed.addListener(_pressedChanged);
  }

  @override
  void didUpdateWidget(PressEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pressed == oldWidget.pressed) return;
    oldWidget.pressed.removeListener(_pressedChanged);
    widget.pressed.addListener(_pressedChanged);
    if (widget.pressed.value != oldWidget.pressed.value) _pressedChanged();
  }

  @override
  void dispose() {
    widget.pressed.removeListener(_pressedChanged);
    _press.dispose();
    super.dispose();
  }

  void _pressedChanged() => widget.pressed.value ? _pressDown() : _release();

  void _pressDown() {
    if (AppMotion.reduced(context)) {
      _press.value = 1;
      return;
    }
    _pressingIn = _press.animateTo(1, duration: _pressIn, curve: Curves.easeOut);
  }

  void _release() {
    if (AppMotion.reduced(context)) {
      _press.value = 0;
      return;
    }
    final pressingIn = _pressingIn;
    if (pressingIn != null && _press.isAnimating) {
      // Completes only if the press runs to its end; a new press cancels it.
      pressingIn.whenComplete(_springBack);
    } else {
      _springBack();
    }
  }

  void _springBack() {
    if (!mounted || widget.pressed.value) return;
    _pressingIn = null;
    // A spring settles within a hair of its end; land exactly on it unless a
    // new press took over.
    _press.animateWith(SpringSimulation(AppMotion.bounce, _press.value, 0, 0)).whenComplete(() {
      if (mounted && !widget.pressed.value) _press.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final t = _press.value;
        final scaled = Transform.scale(scale: 1 - (1 - widget.scale) * t, child: child);
        if (widget.opacity == 1) return scaled;
        return Opacity(opacity: (1 - (1 - widget.opacity) * t).clamp(0.0, 1.0), child: scaled);
      },
      child: widget.child,
    );
  }
}
