import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A cover clipped to [borderRadius] that flies between pages as a [Hero]
/// tagged [tag] (see `coverHeroTag`). Covers are rounded differently at each
/// end (a list thumbnail and the detail page's cover), so while flying the
/// corners morph from one shape to the other and nothing pops on landing.
///
/// On the way to the detail page the flying cover is the one the list
/// already shows, so it never flashes a placeholder, while the destination's
/// own image loads underneath it, ready for the landing. On the way back the
/// page's cover fades into the list's as it flies, so a sharper image or a
/// dimmed one doesn't swap at once. The covers are built again for the
/// flight, so [child] must not hold a `GlobalKey`.
///
/// Without a [tag], or when the system asks to remove animations, it is
/// just the clipped [child].
class RoundedHero extends StatelessWidget {
  const RoundedHero({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final Object? tag;
  final BorderRadius borderRadius;

  /// The cover, sized by the parent (it is stretched to the flying size).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clipped = ClipRRect(borderRadius: borderRadius, child: child);
    final tag = this.tag;
    if (tag == null || AppMotion.reduced(context)) return clipped;
    return Hero(tag: tag, flightShuttleBuilder: _flightShuttle, child: clipped);
  }

  static Widget _flightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final from = fromHeroContext.findAncestorWidgetOfExactType<RoundedHero>();
    final to = toHeroContext.findAncestorWidgetOfExactType<RoundedHero>();
    // A plain Hero shares the tag (e.g. the full-screen cover viewer): fly
    // its own content, as Flutter would.
    if (from == null || to == null) return (toHeroContext.widget as Hero).child;

    final push = direction == HeroFlightDirection.push;
    // The route animation runs 0 → 1 on push and 1 → 0 on pop, so 0 is
    // always the lower page's end of the flight.
    final lower = push ? from : to;
    final upper = push ? to : from;
    final corners = BorderRadiusTween(begin: lower.borderRadius, end: upper.borderRadius);
    final content = Stack(
      fit: StackFit.expand,
      children: [
        to.child,
        // On pop the animation runs 1 → 0, fading the page's cover out.
        if (push) from.child else FadeTransition(opacity: animation, child: from.child),
      ],
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => ClipRRect(
        borderRadius: corners.evaluate(animation) ?? BorderRadius.zero,
        child: child,
      ),
      child: content,
    );
  }
}
