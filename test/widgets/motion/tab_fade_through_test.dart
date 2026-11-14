import 'package:anispark/widgets/motion/tab_fade_through.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget tab({required bool active, Alignment? origin}) => MaterialApp(
        home: TabFadeThrough(active: active, origin: origin, child: const SizedBox.expand()),
      );

  ScaleTransition scale(WidgetTester tester) => tester.widget<ScaleTransition>(find.byType(ScaleTransition));

  testWidgets('a tab opened from a corner grows out of it', (tester) async {
    await tester.pumpWidget(tab(active: false));
    await tester.pumpWidget(tab(active: true, origin: Alignment.topLeft));

    expect(scale(tester).alignment, Alignment.topLeft);
    expect(scale(tester).scale.value, lessThan(0.95), reason: 'a noticeable zoom, not the usual hint');
    await tester.pumpAndSettle();
    expect(scale(tester).scale.value, 1);
  });

  testWidgets('a tab picked in the bar only hints at a zoom, from its centre', (tester) async {
    await tester.pumpWidget(tab(active: false));
    await tester.pumpWidget(tab(active: true));
    await tester.pump(const Duration(milliseconds: 16));

    expect(scale(tester).alignment, Alignment.center);
    expect(scale(tester).scale.value, greaterThanOrEqualTo(0.98));
  });
}
