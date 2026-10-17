import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Briefly enlarges [child] and settles it back with a small spring when
/// [value] changes, e.g. a heart when something is liked. With [when] only
/// some new values pop (e.g. liking but not unliking). Rebuilds with the
/// same value don't animate.
class PopOnChange extends StatefulWidget {
  const PopOnChange({
    super.key,
    required this.value,
    required this.child,
    this.when,
    this.scale = 1.25,
  });

  final Object? value;
  final Widget child;
  final bool Function(Object? value)? when;

  /// The size at the peak of the pop.
  final double scale;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.medium);
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.scale).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.scale, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = widget.value != oldWidget.value;
    final wanted = widget.when?.call(widget.value) ?? true;
    if (changed && wanted && !AppMotion.reduced(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}
