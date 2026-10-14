import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/motion/liquid_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _icons = [Icons.smart_display, Icons.collections_bookmark, Icons.travel_explore, Icons.article, Icons.person];

/// The bar as MainNavigation uses it, in the app's theme, with its selection
/// driven by taps like the real one.
Widget _app({int initial = 0, MediaQueryData Function(MediaQueryData)? media}) {
  var selected = initial;
  return MaterialApp(
    theme: buildAppTheme(Brightness.dark, const Color(0xFF009688)),
    builder: (context, child) => media == null
        ? child!
        : MediaQuery(data: media(MediaQuery.of(context)), child: child!),
    home: StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: LiquidNavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) => setState(() => selected = i),
          destinations: [
            for (final (i, icon) in _icons.indexed)
              LiquidDestination(
                icon: Icon(icon, key: ValueKey('icon-$i')),
                selectedIcon: Icon(icon, key: ValueKey('icon-$i')),
                label: 'Tab $i',
              ),
          ],
        ),
      ),
    ),
  );
}

/// The pill the bar painted, in the bar's coordinates.
RRect _pill(WidgetTester tester) {
  late RRect pill;
  expect(
    find.byKey(LiquidNavigationBar.pillKey),
    paints..something((method, arguments) {
      if (method != #drawRRect) return false;
      pill = arguments[0] as RRect;
      return true;
    }),
  );
  return pill;
}

/// [tab]'s icon centre in the bar's coordinates.
Offset _iconCenter(WidgetTester tester, int tab) =>
    tester.getCenter(find.byKey(ValueKey('icon-$tab'))) - tester.getTopLeft(find.byKey(LiquidNavigationBar.pillKey));

void _expectOn(WidgetTester tester, int tab) {
  final pill = _pill(tester);
  final icon = _iconCenter(tester, tab);
  expect(pill.center.dx, moreOrLessEquals(icon.dx, epsilon: 0.01), reason: 'centred on tab $tab');
  expect(pill.center.dy, moreOrLessEquals(icon.dy, epsilon: 0.01), reason: 'centred on tab $tab');
  expect(pill.width, 60, reason: 'resting, not stretched');
}

void main() {
  testWidgets('is laid out as a normal bottom bar with the pill on the selected icon', (tester) async {
    await tester.pumpWidget(_app(initial: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final barHeight = tester.getSize(find.byType(LiquidNavigationBar)).height;
    expect(barHeight, tester.getSize(find.byType(NavigationBar)).height,
        reason: 'the bar must not grow past the NavigationBar (it filled the screen once)');
    expect(barHeight, lessThan(120));
    _expectOn(tester, 2);
  });

  testWidgets('stretches toward the tapped tab, then settles on it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    _expectOn(tester, 0);

    await tester.tap(find.text('Tab 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final midway = _pill(tester);
    expect(midway.width, greaterThan(60), reason: 'stretched like a drop mid-move');
    expect(midway.center.dx, greaterThan(_iconCenter(tester, 0).dx));
    expect(midway.center.dx, lessThan(_iconCenter(tester, 3).dx));

    await tester.pumpAndSettle();
    _expectOn(tester, 3);
  });

  testWidgets('a tap during a move continues from where the pill is', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tab 4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = _pill(tester);

    await tester.tap(find.text('Tab 1'));
    await tester.pump();
    final after = _pill(tester);
    expect(after.left, moreOrLessEquals(before.left, epsilon: 1), reason: 'no jump back to the first tab');
    expect(after.right, moreOrLessEquals(before.right, epsilon: 1));

    await tester.pumpAndSettle();
    _expectOn(tester, 1);
  });

  testWidgets('jumps straight to the tab when animations are reduced', (tester) async {
    await tester.pumpWidget(_app(media: (m) => m.copyWith(disableAnimations: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tab 4'));
    await tester.pump();
    _expectOn(tester, 4);
  });

  testWidgets('stays on the icon with large text and safe-area insets', (tester) async {
    await tester.pumpWidget(_app(
      initial: 1,
      media: (m) => m.copyWith(
        textScaler: const TextScaler.linear(1.6),
        padding: const EdgeInsets.only(bottom: 34),
        viewPadding: const EdgeInsets.only(bottom: 34),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectOn(tester, 1);
  });
}
