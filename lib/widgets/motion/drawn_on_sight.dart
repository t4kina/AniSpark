import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_motion.dart';

/// Draws something in the first time it is seen: [builder] gets a progress
/// that stays at 0 while the widget is below the fold and runs once to 1
/// when it scrolls into view, for a chart that fills in front of the eyes
/// instead of having done so off screen.
///
/// What is already in view when the page opens runs at once, [delay] later
/// (give the rows of a chart growing delays and they fill in one after the
/// other). With reduced motion the progress is 1 from the start.
class DrawnOnSight extends StatefulWidget {
  const DrawnOnSight({
    super.key,
    required this.builder,
    this.delay = Duration.zero,
    this.duration = AppMotion.long,
  });

  final Widget Function(BuildContext context, Animation<double> progress) builder;
  final Duration delay;
  final Duration duration;

  /// How much of the widget's top must be inside the viewport to count.
  static const sightMargin = 24.0;

  @override
  State<DrawnOnSight> createState() => _DrawnOnSightState();
}

class _DrawnOnSightState extends State<DrawnOnSight> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _progress = CurvedAnimation(parent: _draw, curve: AppMotion.enter);
  ScrollPosition? _position;
  Timer? _wait;
  bool _seen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seen) return;
    if (AppMotion.reduced(context)) {
      _see(animate: false);
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_look);
      _position = position?..addListener(_look);
    }
    // Where it is can only be asked once it has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _look());
  }

  @override
  void dispose() {
    _position?.removeListener(_look);
    _wait?.cancel();
    _draw.dispose();
    super.dispose();
  }

  void _look() {
    if (_seen || !mounted) return;
    final box = context.findRenderObject();
    final position = _position;
    if (box == null || !box.attached || position == null || !position.hasContentDimensions) {
      // Not in something that scrolls: there is no fold to be under.
      if (position == null && box != null && box.attached) _see(animate: true);
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    // The scroll offset at which its top would touch the top of the viewport.
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final inView = top < position.pixels + position.viewportDimension - DrawnOnSight.sightMargin;
    if (inView) _see(animate: true);
  }

  void _see({required bool animate}) {
    _seen = true;
    _position?.removeListener(_look);
    _position = null;
    if (!animate) {
      _draw.value = 1;
    } else if (widget.delay == Duration.zero) {
      _draw.forward();
    } else {
      _wait = Timer(widget.delay, _draw.forward);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _progress);
}
