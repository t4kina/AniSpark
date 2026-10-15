import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/motion/liquid_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
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

  group('dragging along the bar', () {
    late List<Object?> haptics;

    setUp(() => haptics = []);

    Future<void> pumpBar(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
    }

    int selected(WidgetTester tester) => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    testWidgets('pulls the pill after the finger and opens the tab let go on', (tester) async {
      await pumpBar(tester);
      final from = tester.getCenter(find.byKey(const ValueKey('icon-0')));
      final to = tester.getCenter(find.byKey(const ValueKey('icon-3')));

      final gesture = await tester.startGesture(from);
      for (var x = from.dx; x < to.dx; x += 10) {
        await gesture.moveTo(Offset(x, from.dy));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 16));

      expect(_pill(tester).width, greaterThan(60), reason: 'stretched, trailing the finger');
      expect(selected(tester), 0, reason: 'nothing opens until the finger lifts');
      expect(haptics, hasLength(3), reason: 'a tick on tabs 1, 2 and 3');

      await tester.pump(const Duration(milliseconds: 600));
      final caughtUp = _pill(tester);
      expect(caughtUp.center.dx, moreOrLessEquals(_iconCenter(tester, 3).dx, epsilon: 0.5));
      expect(caughtUp.width, moreOrLessEquals(60, epsilon: 0.5), reason: 'back in shape once it catches up');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected(tester), 3);
      _expectOn(tester, 3);
    });

    testWidgets('works after holding first', (tester) async {
      await pumpBar(tester);
      final from = tester.getCenter(find.byKey(const ValueKey('icon-4')));

      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tab 4'), findsOneWidget, reason: 'no tooltip bubble repeating the label over the bar');
      await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('icon-1'))));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selected(tester), 1);
    });

    testWidgets('a small wobble is still a tap', (tester) async {
      await pumpBar(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Tab 2')));
      await gesture.moveBy(const Offset(6, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selected(tester), 2);
      _expectOn(tester, 2);
    });

    testWidgets('letting go on the open tab changes nothing', (tester) async {
      var selections = 0;
      await pumpBar(tester);
      final bar = tester.widget<LiquidNavigationBar>(find.byType(LiquidNavigationBar));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.dark, const Color(0xFF009688)),
        home: Scaffold(
          bottomNavigationBar: LiquidNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) => selections++,
            destinations: bar.destinations,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final from = tester.getCenter(find.byKey(const ValueKey('icon-0')));
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(from);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selections, 0);
      _expectOn(tester, 0);
    });
  });
}
