import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A small burst around [child] when [active] becomes true: a ring opens
/// out from it and a few sparks fly off and fade, for the moment something
/// is liked. Nothing happens when it becomes false, or when motion is
/// reduced.
///
/// The burst is painted over and around the child without taking any room,
/// so nothing beside it moves; ancestors must not clip close to it.
class LikeBurst extends StatefulWidget {
  const LikeBurst({super.key, required this.active, required this.color, required this.child, this.radius = 15});

  final bool active;
  final Color color;
  final Widget child;

  /// How far from the child's centre the ring and the sparks get.
  final double radius;

  static const duration = Duration(milliseconds: 450);

  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(vsync: this, duration: LikeBurst.duration);

  @override
  void didUpdateWidget(LikeBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !AppMotion.reduced(context)) _burst.forward(from: 0);
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _BurstPainter(progress: _burst, color: widget.color, radius: widget.radius),
        child: widget.child,
      );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color, required this.radius}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double radius;

  static const _sparks = 6;
  static const _sparkSize = 1.8;
  static const _ringWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;
    final out = Curves.easeOutCubic.transform(t);
    final fade = 1 - t * t;
    final centre = size.center(Offset.zero);

    canvas.drawCircle(
      centre,
      radius * (0.35 + 0.65 * out),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringWidth * (1 - out)
        ..color = color.withValues(alpha: 0.6 * fade),
    );

    final spark = Paint()..color = color.withValues(alpha: fade);
    for (var i = 0; i < _sparks; i++) {
      // Starting straight up, evenly around.
      final angle = -math.pi / 2 + i * 2 * math.pi / _sparks;
      final distance = radius * (0.55 + 0.6 * out);
      canvas.drawCircle(
        centre + Offset(math.cos(angle), math.sin(angle)) * distance,
        _sparkSize * (1 - 0.5 * t),
        spark,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.radius != radius;
}
