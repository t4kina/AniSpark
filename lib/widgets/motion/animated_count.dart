import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Shows [value] and rolls it vertically when it changes (likes, progress):
/// up when it grows, down when it shrinks, so the change is noticed without
/// a jump.
class AnimatedCount extends StatefulWidget {
  const AnimatedCount({super.key, required this.value, this.style, this.format});

  final int value;
  final TextStyle? style;

  /// Text for a value; the plain number by default.
  final String Function(int value)? format;

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> {
  late int _previous = widget.value;

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _previous = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    final rising = widget.value >= _previous;
    final format = widget.format;
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.short),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.value);
        // The new value comes in from below when rising, the old one leaves
        // upwards (and the other way round when falling).
        final from = Offset(0, (incoming == rising) ? 0.5 : -0.5);
        return ClipRect(
          child: SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Text(
        format == null ? '${widget.value}' : format(widget.value),
        key: ValueKey(widget.value),
        style: widget.style,
      ),
    );
  }
}
