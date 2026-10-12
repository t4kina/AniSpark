import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Cross-fades from one child to the next (e.g. skeleton → content, or
/// content → error) instead of swapping them abruptly. Give each state's
/// child a different key or type so the switch is noticed. Children are
/// stacked from the top while both are visible, so a list doesn't jump.
class FadeSwitcher extends StatelessWidget {
  const FadeSwitcher({super.key, required this.child, this.duration = AppMotion.medium});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, duration),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}
