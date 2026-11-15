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

  group('IncrementTick', () {
    final tick = find.byIcon(Icons.check_circle_rounded);

    double scale(WidgetTester tester) => tester
        .widget<Transform>(find.ancestor(of: tick, matching: find.byType(Transform)).first)
        .transform
        .entry(0, 0);

    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.ancestor(of: tick, matching: find.byType(Opacity)).first).opacity;

    testWidgets('is not there until the value goes up, and takes no room', (tester) async {
      await tester.pumpWidget(app(const IncrementTick(value: 3)));

      expect(tick, findsNothing);
      expect(tester.getSize(find.byType(IncrementTick)).height, 0);
    });

    testWidgets('pops in when the value goes up, stays a moment and fades away', (tester) async {
      await tester.pumpWidget(app(const IncrementTick(value: 3)));

      await tester.pumpWidget(app(const IncrementTick(value: 4)));
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

    testWidgets('says nothing when the value goes down', (tester) async {
      await tester.pumpWidget(app(const IncrementTick(value: 3)));

      await tester.pumpWidget(app(const IncrementTick(value: 2)));
      await tester.pump(const Duration(milliseconds: 60));

      expect(tick, findsNothing);
    });

    testWidgets('a second step up while it shows starts it again', (tester) async {
      await tester.pumpWidget(app(const IncrementTick(value: 3)));
      await tester.pumpWidget(app(const IncrementTick(value: 4)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(opacity(tester), lessThan(1));

      await tester.pumpWidget(app(const IncrementTick(value: 5)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(tester), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('shows without the pop when motion is reduced', (tester) async {
      await tester.pumpWidget(app(const IncrementTick(value: 3), reduceMotion: true));

      await tester.pumpWidget(app(const IncrementTick(value: 4), reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(tester), 1);
      await tester.pumpAndSettle();
      expect(tick, findsNothing);
    });
  });
}
