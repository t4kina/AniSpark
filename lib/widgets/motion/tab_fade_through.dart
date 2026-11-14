import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Fades a tab's content in, with a barely noticeable zoom, when it becomes
/// the [active] tab (Material's "fade through"). Meant for the children of
/// an IndexedStack, which keeps every tab's state; the tab shown first
/// appears at once. A hidden tab's animations (e.g. a loading shimmer) are
/// paused, since an IndexedStack keeps them ticking for nobody.
class TabFadeThrough extends StatefulWidget {
  const TabFadeThrough({super.key, required this.active, required this.child, this.origin});

  final bool active;
  final Widget child;

  /// Where the tab was opened from (e.g. the avatar in a corner): it then
  /// grows out of that point instead of the usual hint of a zoom.
  final Alignment? origin;

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

  /// The usual hint of a zoom, and the bigger one out of an [TabFadeThrough.origin].
  static const _hintScale = 0.98;
  static const _originScale = 0.9;

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
        alignment: widget.origin ?? Alignment.center,
        scale: Tween(begin: widget.origin == null ? _hintScale : _originScale, end: 1.0).animate(_progress),
        // Inside the transitions, so the fade-in itself is never paused.
        child: TickerMode(enabled: widget.active, child: widget.child),
      ),
    );
  }
}
