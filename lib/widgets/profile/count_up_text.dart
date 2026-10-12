import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Shows [value], counting up to it from zero when first shown (e.g. a
/// profile's stats). Rebuilds with the same value don't replay it; a new
/// value counts on from the one shown. With reduced motion it's just the
/// number.
class CountUpText extends StatelessWidget {
  const CountUpText(this.value, {super.key, this.fractionDigits = 0, this.style});

  final num value;

  /// Decimals shown, e.g. 1 for days watched.
  final int fractionDigits;
  final TextStyle? style;

  String _format(double value) =>
      fractionDigits == 0 ? '${value.round()}' : value.toStringAsFixed(fractionDigits);

  @override
  Widget build(BuildContext context) {
    final target = value.toDouble();
    return Semantics(
      // Screen readers get the real value, never an in-between one.
      label: _format(target),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: AppMotion.of(context, AppMotion.long),
        curve: AppMotion.enter,
        builder: (context, shown, _) => Text(_format(shown), style: style),
      ),
    );
  }
}
