import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/motion/progress_moment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {bool reduceMotion = false}) => MaterialApp(
        theme: buildAppTheme(Brightness.dark, Colors.teal),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: SizedBox(width: 200, child: child))),
        ),
      );

  group('ProgressLine', () {
    double fill(WidgetTester tester) =>
        tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor!;

    testWidgets('is filled as far as the progress, at once when it first appears', (tester) async {
      await tester.pumpWidget(app(const ProgressLine(value: 3, total: 12)));

      expect(fill(tester), 0.25);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getSize(find.byType(ProgressLine)), const Size(200, ProgressLine.height));
    });

    testWidgets('glides to a new value', (tester) async {
      await tester.pumpWidget(app(const ProgressLine(value: 3, total: 12)));

      await tester.pumpWidget(app(const ProgressLine(value: 6, total: 12)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fill(tester), inExclusiveRange(0.25, 0.5));

      await tester.pumpAndSettle();
      expect(fill(tester), 0.5);
    });

    testWidgets('never overflows when the progress passes the total', (tester) async {
      await tester.pumpWidget(app(const ProgressLine(value: 30, total: 12)));

      expect(fill(tester), 1);
    });

    testWidgets('jumps when motion is reduced', (tester) async {
      await tester.pumpWidget(app(const ProgressLine(value: 3, total: 12), reduceMotion: true));

      await tester.pumpWidget(app(const ProgressLine(value: 6, total: 12), reduceMotion: true));
      await tester.pump();
      expect(fill(tester), 0.5);
    });
  });

  group('ChangeTick', () {
    final tick = find.byIcon(Icons.check_circle_rounded);

    double scale(WidgetTester tester) => tester
        .widget<Transform>(find.ancestor(of: tick, matching: find.byType(Transform)).first)
        .transform
        .entry(0, 0);

    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.ancestor(of: tick, matching: find.byType(Opacity)).first).opacity;

    Color colour(WidgetTester tester) => tester.widget<Icon>(tick).color!;

    /// The tick at the end of a line of text, as a list row has it.
    Widget line(int value) => app(Row(
          mainAxisSize: MainAxisSize.min,
          children: [const Text('42 / 100', style: TextStyle(fontSize: 12)), ChangeTick(value: value)],
        ));

    testWidgets('nothing is drawn until the value changes', (tester) async {
      await tester.pumpWidget(app(const ChangeTick(value: 3)));

      expect(tick, findsNothing);
    });

    testWidgets('pops in when the value goes up, stays a moment and fades away', (tester) async {
      await tester.pumpWidget(app(const ChangeTick(value: 3)));

      await tester.pumpWidget(app(const ChangeTick(value: 4)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tick, findsOneWidget);
      expect(scale(tester), lessThan(1), reason: 'still growing');

      await tester.pump(const Duration(milliseconds: 400));
      expect(scale(tester), 1);
      expect(opacity(tester), 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(opacity(tester), lessThan(1), reason: 'fading');

      await tester.pumpAndSettle();
      expect(tick, findsNothing);
    });

    testWidgets('going down is answered too, in a quieter colour than going up', (tester) async {
      await tester.pumpWidget(app(const ChangeTick(value: 3)));
      await tester.pumpWidget(app(const ChangeTick(value: 4)));
      await tester.pump(const Duration(milliseconds: 300));
      final up = colour(tester);
      await tester.pumpAndSettle();

      await tester.pumpWidget(app(const ChangeTick(value: 3)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tick, findsOneWidget);
      expect(colour(tester), isNot(up));
      expect(HSLColor.fromColor(colour(tester)).saturation, lessThan(HSLColor.fromColor(up).saturation));

      await tester.pumpAndSettle();
      expect(tick, findsNothing);
    });

    testWidgets('showing and going moves nothing: its room is the same all along and it adds no height',
        (tester) async {
      await tester.pumpWidget(line(3));
      final text = tester.getRect(find.text('42 / 100'));
      final row = tester.getRect(find.byType(Row));
      final room = tester.getSize(find.byType(ChangeTick));
      expect(room.height, 0, reason: 'it is painted over the line, not laid out in it');

      await tester.pumpWidget(line(4));
      for (final wait in [60, 300, 600]) {
        await tester.pump(Duration(milliseconds: wait));
        expect(tick, findsOneWidget);
        expect(tester.getRect(find.text('42 / 100')), text, reason: 'the text holds still');
        expect(tester.getRect(find.byType(Row)), row, reason: 'the line keeps its height');
        expect(tester.getSize(find.byType(ChangeTick)), room);
      }
      // Centred on the line of text, just after it.
      expect(tester.getCenter(tick).dy, moreOrLessEquals(text.center.dy, epsilon: 0.5));
      expect(tester.getRect(tick).left, greaterThanOrEqualTo(text.right));

      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('42 / 100')), text);
      expect(tester.getRect(find.byType(Row)), row);
    });

    testWidgets('a second change while it shows starts it again', (tester) async {
      await tester.pumpWidget(app(const ChangeTick(value: 3)));
      await tester.pumpWidget(app(const ChangeTick(value: 4)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(opacity(tester), lessThan(1));

      await tester.pumpWidget(app(const ChangeTick(value: 5)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(tester), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('shows without the pop when motion is reduced', (tester) async {
      await tester.pumpWidget(app(const ChangeTick(value: 3), reduceMotion: true));

      await tester.pumpWidget(app(const ChangeTick(value: 4), reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), 1);
      await tester.pumpAndSettle();
      expect(tick, findsNothing);
    });
  });
}
