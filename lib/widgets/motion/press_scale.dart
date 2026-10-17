import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Shrinks [child] slightly while [pressed] is true and springs it back:
/// press feedback for one part of a larger tappable row (e.g. its cover)
/// whose gestures are handled elsewhere, typically by an `InkWell` reporting
/// `onHighlightChanged`. Unlike `Pressable` it adds no gesture detector, so
/// it can't fight a row's swipe or long press, and only [child] rebuilds
/// when the press changes.
class PressScale extends StatelessWidget {
  const PressScale({super.key, required this.pressed, required this.child, this.scale = 0.94});

  final ValueListenable<bool> pressed;
  final Widget child;

  /// How small [child] gets while pressed.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: pressed,
      builder: (context, isPressed, child) => AnimatedScale(
        scale: isPressed ? scale : 1,
        duration: AppMotion.of(context, AppMotion.short),
        curve: AppMotion.standard,
        child: child,
      ),
      child: child,
    );
  }
}
