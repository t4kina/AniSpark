import 'package:anispark/theme/app_colors.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find.ancestor(of: find.text('Save'), matching: find.byType(Transform)).first)
    .transform
    .entry(0, 0);

BoxDecoration _decoration(WidgetTester tester) => tester
    .widget<Container>(find.descendant(of: find.byType(AppButton), matching: find.byType(Container)).first)
    .decoration! as BoxDecoration;

Color? _labelColor(WidgetTester tester) => tester.widget<Text>(find.text('Save')).style?.color;

void main() {
  testWidgets('reports a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(AppButton(label: 'Save', onPressed: () => taps++)));

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('shrinks under the finger', (tester) async {
    await tester.pumpWidget(_app(AppButton(label: 'Save', onPressed: () {})));

    final gesture = await tester.startGesture(tester.getCenter(find.byType(AppButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester), 0.96);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('while busy it shows a spinner, ignores taps and keeps its size', (tester) async {
    var taps = 0;
    Widget button({required bool busy}) => _app(AppButton(label: 'Save', busy: busy, onPressed: () => taps++));

    await tester.pumpWidget(button(busy: false));
    final size = tester.getSize(find.byType(AppButton));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(button(busy: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(AppButton)), size, reason: 'the spinner takes the label\'s place');
    final label = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('Save'), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(label.opacity, 0);

    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);

    await tester.pumpWidget(button(busy: false));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('without a callback it is faded and does not answer a press', (tester) async {
    await tester.pumpWidget(_app(const AppButton(label: 'Save', onPressed: null)));

    final fade = tester.widget<AnimatedOpacity>(
      find.descendant(of: find.byType(AppButton), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(fade.opacity, lessThan(1));

    final gesture = await tester.startGesture(tester.getCenter(find.byType(AppButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.byType(AppButton)), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
  });

  testWidgets('hugs its label unless told to fill the width', (tester) async {
    await tester.pumpWidget(_app(AppButton(label: 'Save', onPressed: () {})));
    expect(tester.getSize(find.byType(AppButton)).width, lessThan(200));
    expect(tester.getSize(find.byType(AppButton)).height, 44);

    await tester.pumpWidget(_app(AppButton(label: 'Save', large: true, expand: true, onPressed: () {})));
    expect(tester.getSize(find.byType(AppButton)).width, 800);
    expect(tester.getSize(find.byType(AppButton)).height, 52);
  });

  testWidgets('a long label is cut short instead of overflowing', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      width: 160,
      child: AppButton(label: 'Save ' * 20, icon: Icons.check, expand: true, onPressed: () {}),
    )));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppButton)).width, 160);
  });

  for (final brightness in Brightness.values) {
    testWidgets('each kind has its own colours (${brightness.name})', (tester) async {
      const accent = Color(0xFF02A9FF);
      final theme = buildAppTheme(brightness, accent);
      Widget button(AppButtonKind kind) => _app(AppButton(label: 'Save', kind: kind, onPressed: () {}), theme: theme);

      await tester.pumpWidget(button(AppButtonKind.primary));
      expect(_decoration(tester).color, accent);
      expect(_labelColor(tester), Colors.white, reason: 'text on the accent is white in both themes');

      await tester.pumpWidget(button(AppButtonKind.tonal));
      expect(_decoration(tester).color, theme.colorScheme.surfaceContainerHighest);
      expect(_labelColor(tester), theme.colorScheme.onSurface);

      await tester.pumpWidget(button(AppButtonKind.glass));
      expect(_decoration(tester).color!.a, lessThan(0.2), reason: 'see-through');
      expect(_decoration(tester).border, isNotNull);
      expect(_labelColor(tester), Colors.white);

      await tester.pumpWidget(button(AppButtonKind.danger));
      expect(_decoration(tester).color, theme.extension<AppColors>()!.danger);
      expect(_labelColor(tester), Colors.white);
    });
  }
}
