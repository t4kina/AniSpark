import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Shows [value] and rolls it vertically when it changes (likes, progress):
/// up when it grows, down when it shrinks, so the change is noticed without
/// a jump.
///
/// While idle it is a plain [Text]: the animation is only built while a
/// change rolls, since long lists show one per row.
class AnimatedCount extends StatefulWidget {
  const AnimatedCount({super.key, required this.value, this.style, this.format});

  final int value;
  final TextStyle? style;

  /// Text for a value; the plain number by default.
  final String Function(int value)? format;

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;

  /// The value rolling out, while a change animates.
  int? _leaving;
  bool _rising = true;

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final duration = AppMotion.of(context, AppMotion.short);
    if (duration == Duration.zero) {
      _controller?.stop();
      _leaving = null;
      return;
    }
    _rising = widget.value >= oldWidget.value;
    _leaving = oldWidget.value;
    final controller = _controller ??= _createController();
    controller
      ..duration = duration
      ..forward(from: 0);
  }

  AnimationController _createController() {
    final controller = AnimationController(vsync: this, duration: AppMotion.short);
    _progress = CurvedAnimation(parent: controller, curve: AppMotion.enter);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _leaving = null);
    });
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _text(int value) => widget.format?.call(value) ?? '$value';

  @override
  Widget build(BuildContext context) {
    final current = Text(_text(widget.value), style: widget.style);
    final leaving = _leaving;
    final progress = _progress;
    if (leaving == null || progress == null) return current;

    // Rising: the new value comes in from below and the old one leaves
    // upwards; falling: the other way round.
    final offset = Offset(0, _rising ? 0.5 : -0.5);
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SlideTransition(
            position: Tween(begin: Offset.zero, end: -offset).animate(progress),
            child: FadeTransition(
              opacity: ReverseAnimation(progress),
              child: Text(_text(leaving), style: widget.style),
            ),
          ),
          SlideTransition(
            position: Tween(begin: offset, end: Offset.zero).animate(progress),
            child: FadeTransition(opacity: progress, child: current),
          ),
        ],
      ),
    );
  }
}
