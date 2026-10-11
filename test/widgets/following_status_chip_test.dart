import 'dart:math' as math;

import 'package:anispark/widgets/detail/following_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastWithWhite(Color color) {
  final luminance = color.computeLuminance();
  return 1.05 / (luminance + 0.05);
}

void main() {
  test(
    'every status chip colour keeps white 11px text at WCAG AA contrast',
    () {
      expect(followingStatusChipColors, isNotEmpty);
      followingStatusChipColors.forEach((status, color) {
        final ratio = _contrastWithWhite(color);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$status is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    },
  );

  test('each status keeps a distinct hue', () {
    final hues = followingStatusChipColors.values
        .map((c) => HSVColor.fromColor(c).hue)
        .toList();
    for (var i = 0; i < hues.length; i++) {
      for (var j = i + 1; j < hues.length; j++) {
        final gap = (hues[i] - hues[j]).abs();
        expect(math.min(gap, 360 - gap), greaterThan(10));
      }
    }
  });
}
