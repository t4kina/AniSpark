import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// A pill behind the bottom nav's selected tab that, on a tab change,
/// stretches toward the destination before its trailing edge catches up
/// and it snaps back into shape — a liquid-drop motion instead of a rigid
/// slide. Purely decorative: it sits behind the real NavigationBar, which
/// handles all taps.
class LiquidTabIndicator extends StatefulWidget {
  const LiquidTabIndicator({
    super.key,
    required this.index,
    required this.itemCount,
    required this.color,
  });

  final int index;
  final int itemCount;
  final Color color;

  @override
  State<LiquidTabIndicator> createState() => _LiquidTabIndicatorState();
}

class _LiquidTabIndicatorState extends State<LiquidTabIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _fromIndex;

  static const _restWidth = 44.0;
  static const _height = 34.0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void didUpdateWidget(covariant LiquidTabIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _fromIndex = oldWidget.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / widget.itemCount;
        final fromCenter = (_fromIndex + 0.5) * itemWidth;
        final toCenter = (widget.index + 0.5) * itemWidth;
        final movingForward = toCenter >= fromCenter;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            // The edge in the direction of travel reaches the target
            // quickly; the trailing edge lags on a delayed curve and
            // catches up last, stretching the pill like a liquid drop.
            final leadT = Curves.easeOutCubic.transform(t);
            final trailT = const Interval(
              0.25,
              1,
              curve: Curves.easeOutCubic,
            ).transform(t);

            final fromLead = movingForward
                ? fromCenter + _restWidth / 2
                : fromCenter - _restWidth / 2;
            final toLead = movingForward
                ? toCenter + _restWidth / 2
                : toCenter - _restWidth / 2;
            final fromTrail = movingForward
                ? fromCenter - _restWidth / 2
                : fromCenter + _restWidth / 2;
            final toTrail = movingForward
                ? toCenter - _restWidth / 2
                : toCenter + _restWidth / 2;

            final lead = lerpDouble(fromLead, toLead, leadT)!;
            final trail = lerpDouble(fromTrail, toTrail, trailT)!;

            final left = math.min(lead, trail);
            final width = math.max(lead, trail) - left;

            // A gentle squash while stretched reads as liquid rather than
            // a rigid bar sliding on rails.
            final stretch = ((width - _restWidth) / _restWidth).clamp(0.0, 1.5);
            final squash = 1 - stretch * 0.18;

            return Positioned(
              left: left,
              width: width,
              top: 10,
              height: _height,
              child: Transform.scale(
                scaleY: squash,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_height / 2),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.color.withValues(alpha: 0.22),
                        widget.color.withValues(alpha: 0.10),
                      ],
                    ),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
