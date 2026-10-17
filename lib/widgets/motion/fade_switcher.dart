import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Cross-fades from one child to the next (e.g. skeleton → content, or
/// content → error) instead of swapping them abruptly. Give each state's
/// child a different key or type so the switch is noticed. Children are
/// stacked from the top while both are visible, so a list doesn't jump.
///
/// The leaving child's heroes are switched off: while both copies are on
/// screen they share hero tags, and opening a page then would clash.
class FadeSwitcher extends StatelessWidget {
  const FadeSwitcher({super.key, required this.child, this.duration = AppMotion.medium});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Each child keeps the same keyed wrapper when it goes from current to
    // leaving, so its state (scroll position, images) survives the switch.
    // An enabled HeroMode can't re-enable heroes an outer one switched off
    // (the hero search stops at a disabled one), so nesting is safe.
    Widget withHeroes(Widget child, {required bool enabled}) =>
        HeroMode(key: child.key, enabled: enabled, child: child);
    return AnimatedSwitcher(
      duration: AppMotion.of(context, duration),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final leaving in previous) withHeroes(leaving, enabled: false),
          if (current != null) withHeroes(current, enabled: true),
        ],
      ),
      child: child,
    );
  }
}
