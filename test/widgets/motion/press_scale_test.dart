import 'package:anispark/widgets/motion/press_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _scaleOf(WidgetTester tester) => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

double _shownScale(WidgetTester tester) => tester
    .widget<Transform>(find.ancestor(of: find.text('cover'), matching: find.byType(Transform)).first)
    .transform
    .entry(0, 0);

void main() {
  testWidgets('shrinks while pressed and springs back on release', (tester) async {
    final pressed = ValueNotifier(false);
    addTearDown(pressed.dispose);
    await tester.pumpWidget(_app(PressScale(pressed: pressed, child: const Text('cover'))));
    expect(_scaleOf(tester), 1);

    pressed.value = true;
    await tester.pumpAndSettle();
    expect(_shownScale(tester), 0.94);

    pressed.value = false;
    await tester.pumpAndSettle();
    expect(_shownScale(tester), 1);
  });

  testWidgets('a row\'s ink highlight drives it without adding a gesture detector', (tester) async {
    final pressed = ValueNotifier(false);
    addTearDown(pressed.dispose);
    var taps = 0;
    await tester.pumpWidget(_app(InkWell(
      onTap: () => taps++,
      onHighlightChanged: (value) => pressed.value = value,
      child: SizedBox(width: 200, height: 80, child: PressScale(pressed: pressed, child: const Text('cover'))),
    )));

    final gesture = await tester.startGesture(tester.getCenter(find.byType(InkWell)));
    await tester.pumpAndSettle();
    expect(_shownScale(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_shownScale(tester), 1);
    expect(taps, 1);
    expect(find.descendant(of: find.byType(PressScale), matching: find.byType(GestureDetector)), findsNothing);
  });

  testWidgets('jumps instead of animating when motion is reduced', (tester) async {
    final pressed = ValueNotifier(false);
    addTearDown(pressed.dispose);
    await tester.pumpWidget(_app(PressScale(pressed: pressed, child: const Text('cover')), reduceMotion: true));

    pressed.value = true;
    await tester.pump();

    expect(_shownScale(tester), 0.94);
  });
}
