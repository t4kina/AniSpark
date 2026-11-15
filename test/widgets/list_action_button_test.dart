import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/detail/list_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int taps;

  setUp(() => taps = 0);

  Widget button({required bool inList, bool reduceMotion = false}) => MaterialApp(
        theme: buildAppTheme(Brightness.dark, Colors.teal),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: ListActionButton(
                  icon: inList ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  label: inList ? 'WATCHING' : 'ADD TO LIST',
                  sublabel: 'STATUS',
                  highlighted: inList,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );

  BoxDecoration decoration(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration! as BoxDecoration;

  Color painted(WidgetTester tester) => (tester
          .widget<DecoratedBox>(
            find.descendant(of: find.byType(AnimatedContainer), matching: find.byType(DecoratedBox)).first,
          )
          .decoration as BoxDecoration)
      .color!;

  double iconScale(WidgetTester tester) => tester
      .widget<Transform>(find.ancestor(of: find.byType(Icon).last, matching: find.byType(Transform)).first)
      .transform
      .entry(0, 0);

  testWidgets('is a plain button until the series is in the list', (tester) async {
    await tester.pumpWidget(button(inList: false));

    final theme = Theme.of(tester.element(find.byType(ListActionButton)));
    expect(decoration(tester).color, theme.colorScheme.surfaceContainerHighest);
    expect(find.text('ADD TO LIST'), findsOneWidget);

    await tester.tap(find.byType(ListActionButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('turns into the status chip: tinted with the accent, the new label fading in, the icon popping',
      (tester) async {
    await tester.pumpWidget(button(inList: false));
    final plain = painted(tester);

    await tester.pumpWidget(button(inList: true));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('ADD TO LIST'), findsOneWidget, reason: 'the old label is still fading out');
    expect(find.text('WATCHING'), findsOneWidget, reason: 'the new one is fading in');
    expect(painted(tester), isNot(plain), reason: 'the fill is on its way');
    expect(iconScale(tester), greaterThan(1), reason: 'the bookmark pops');

    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(ListActionButton)));
    expect(find.text('ADD TO LIST'), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    expect((decoration(tester).border! as Border).top.color.a, greaterThan(0.6));
    expect(painted(tester), isNot(theme.colorScheme.surfaceContainerHighest));
    expect(iconScale(tester), 1);
  });

  testWidgets('keeps its size through the change', (tester) async {
    await tester.pumpWidget(button(inList: false));
    final before = tester.getSize(find.byType(ListActionButton));

    await tester.pumpWidget(button(inList: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(find.byType(ListActionButton)), before);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListActionButton)), before);
  });

  testWidgets('goes back to a plain button without a pop when it leaves the list', (tester) async {
    await tester.pumpWidget(button(inList: true));

    await tester.pumpWidget(button(inList: false));
    await tester.pump(const Duration(milliseconds: 80));
    expect(iconScale(tester), 1);

    await tester.pumpAndSettle();
    expect(find.text('ADD TO LIST'), findsOneWidget);
    expect(find.text('WATCHING'), findsNothing);
  });

  testWidgets('changes at once when motion is reduced', (tester) async {
    await tester.pumpWidget(button(inList: false, reduceMotion: true));

    await tester.pumpWidget(button(inList: true, reduceMotion: true));
    await tester.pump();
    await tester.pump();

    expect(find.text('ADD TO LIST'), findsNothing);
    expect(find.text('WATCHING'), findsOneWidget);
    expect(iconScale(tester), 1);
  });
}
