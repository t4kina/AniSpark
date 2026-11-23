import 'package:anispark/widgets/motion/press_effect.dart';
import 'package:anispark/widgets/motion/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.ancestor(of: find.text('card'), matching: find.byType(Transform)).first)
    .transform
    .entry(0, 0);

double _opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.ancestor(of: find.text('card'), matching: find.byType(Opacity)).first).opacity;

const _frame = Duration(milliseconds: 16);

void main() {
  late ValueNotifier<bool> pressed;

  setUp(() => pressed = ValueNotifier(false));
  tearDown(() => pressed.dispose());

  Widget effect({double scale = 0.96, double opacity = 1, bool reduceMotion = false}) => _app(
        PressEffect(pressed: pressed, scale: scale, opacity: opacity, child: const Text('card')),
        reduceMotion: reduceMotion,
      );

  testWidgets('goes down quickly and holds there', (tester) async {
    await tester.pumpWidget(effect());
    expect(_scale(tester), 1);

    pressed.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester), 0.96, reason: 'fully pressed within a tenth of a second');

    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester), 0.96);
  });

  testWidgets('springs back past its size and lands exactly on it', (tester) async {
    pressed.value = true;
    await tester.pumpWidget(effect());
    expect(_scale(tester), 0.96);

    pressed.value = false;
    var largest = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
      if (_scale(tester) > largest) largest = _scale(tester);
    }
    expect(largest, greaterThan(1), reason: 'a rebound, not a flat ease');
    expect(largest, lessThan(1.02), reason: 'a hint of one: nothing wobbles');

    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('a tap shorter than a frame is still shown going down', (tester) async {
    await tester.pumpWidget(effect());

    pressed.value = true;
    pressed.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(_scale(tester), 0.96, reason: 'the press is played to the end before it is let go');

    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('pressing again while it springs back takes over', (tester) async {
    pressed.value = true;
    await tester.pumpWidget(effect());
    pressed.value = false;
    await tester.pump(_frame);
    await tester.pump(_frame);

    pressed.value = true;
    await tester.pumpAndSettle();

    expect(_scale(tester), 0.96);
  });

  testWidgets('can dim instead of shrinking', (tester) async {
    pressed.value = true;
    await tester.pumpWidget(effect(scale: 1, opacity: 0.4));
    expect(_scale(tester), 1);
    expect(_opacity(tester), 0.4);

    pressed.value = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
      expect(_opacity(tester), inInclusiveRange(0, 1), reason: 'the rebound never asks for more than opaque');
    }
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('jumps both ways when motion is reduced', (tester) async {
    await tester.pumpWidget(effect(reduceMotion: true));

    pressed.value = true;
    await tester.pump();
    expect(_scale(tester), 0.96);

    pressed.value = false;
    await tester.pump();
    expect(_scale(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('follows a new listenable when it is given one', (tester) async {
    await tester.pumpWidget(effect());
    final other = ValueNotifier(true);
    addTearDown(other.dispose);

    await tester.pumpWidget(_app(PressEffect(pressed: other, child: const Text('card'))));
    await tester.pumpAndSettle();
    expect(_scale(tester), 0.96);

    pressed.value = true;
    other.value = false;
    await tester.pumpAndSettle();
    expect(_scale(tester), 1, reason: 'the old listenable is no longer listened to');
  });

  group('Pressable', () {
    testWidgets('a quick tap is answered even though the finger is already up', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(Pressable(onTap: () => taps++, child: const Text('card'))));

      await tester.tap(find.text('card'));
      expect(taps, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_scale(tester), 0.96);

      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
    });

    testWidgets('a press that becomes a scroll lets go of the card', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(ListView(children: [
        Pressable(onTap: () => taps++, child: const SizedBox(height: 120, child: Text('card'))),
        const SizedBox(height: 2000),
      ])));

      final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
      // Inside a scrollable a press only counts once the finger has rested.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scale(tester), 0.96, reason: 'held long enough to count as a press');

      await gesture.moveBy(const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('the dim variant fades and keeps its size', (tester) async {
      await tester.pumpWidget(_app(Pressable.dim(onTap: () {}, child: const Text('card'))));

      final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      expect(_opacity(tester), lessThan(0.6));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1);
    });
  });
}
