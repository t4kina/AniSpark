import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Fades a tab's content in, with a barely noticeable zoom, when it becomes
/// the [active] tab (Material's "fade through"). Meant for the children of
/// an IndexedStack, which keeps every tab's state; the tab shown first
/// appears at once. A hidden tab's animations (e.g. a loading shimmer) are
/// paused, since an IndexedStack keeps them ticking for nobody.
class TabFadeThrough extends StatefulWidget {
  const TabFadeThrough({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<TabFadeThrough> createState() => _TabFadeThroughState();
}

class _TabFadeThroughState extends State<TabFadeThrough> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: widget.active ? 1 : 0,
  );
  late final Animation<double> _progress = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
  late final Animation<double> _scale = Tween(begin: 0.98, end: 1.0).animate(_progress);

  @override
  void didUpdateWidget(TabFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || oldWidget.active) return;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
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
    return FadeTransition(
      opacity: _progress,
      child: ScaleTransition(
        scale: _scale,
        // Inside the transitions, so the fade-in itself is never paused.
        child: TickerMode(enabled: widget.active, child: widget.child),
      ),
    );
  }
}
