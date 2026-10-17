import 'package:anispark/theme/app_motion.dart';
import 'package:anispark/widgets/motion/animated_count.dart';
import 'package:anispark/widgets/motion/fade_switcher.dart';
import 'package:anispark/widgets/motion/pop_in.dart';
import 'package:anispark/widgets/motion/pop_on_change.dart';
import 'package:anispark/widgets/motion/pressable.dart';
import 'package:anispark/widgets/motion/staggered_entrance.dart';
import 'package:anispark/widgets/motion/tab_fade_through.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _opacityOf(WidgetTester tester, Finder finder) {
  final fade = tester.widget<FadeTransition>(
    find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
  );
  return fade.opacity.value;
}

double _scaleOf(WidgetTester tester, Finder finder) {
  final transform = tester.widget<Transform>(
    find.ancestor(of: finder, matching: find.byType(Transform)).first,
  );
  // The X scale (getMaxScaleOnAxis would also count the untouched Z axis).
  return transform.transform.entry(0, 0);
}

void main() {
  group('AppMotion', () {
    testWidgets('keeps durations normally and drops them when motion is reduced', (tester) async {
      late Duration normal;
      late Duration reduced;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        normal = AppMotion.of(context, AppMotion.medium);
        return const SizedBox();
      })));
      await tester.pumpWidget(_app(Builder(builder: (context) {
        reduced = AppMotion.of(context, AppMotion.medium);
        return const SizedBox();
      }), reduceMotion: true));

      expect(normal, AppMotion.medium);
      expect(reduced, Duration.zero);
    });
  });

  group('Pressable', () {
    testWidgets('shrinks while pressed, springs back and reports the tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(Pressable(onTap: () => taps++, child: const Text('card'))));

      final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, find.text('card')), lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, find.text('card')), 1);
      expect(taps, 1);
    });

    testWidgets('reports long presses', (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(_app(Pressable(onLongPress: () => longPresses++, child: const Text('card'))));

      await tester.longPress(find.text('card'));

      expect(longPresses, 1);
    });

    testWidgets('is inert without callbacks', (tester) async {
      await tester.pumpWidget(_app(const Pressable(child: Text('card'))));

      expect(find.descendant(of: find.byType(Pressable), matching: find.byType(GestureDetector)), findsNothing);
    });
  });

  group('FadeSwitcher', () {
    testWidgets('cross-fades from the old child to the new one', (tester) async {
      await tester.pumpWidget(_app(const FadeSwitcher(child: Text('skeleton', key: ValueKey('a')))));
      await tester.pumpWidget(_app(const FadeSwitcher(child: Text('content', key: ValueKey('b')))));

      await tester.pump(AppMotion.medium ~/ 2);
      expect(find.text('skeleton'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('skeleton'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('turns off the heroes of the child that is leaving', (tester) async {
      Widget withHero(String label) => Hero(key: ValueKey(label), tag: 'cover', child: Text(label));
      await tester.pumpWidget(_app(FadeSwitcher(child: withHero('old'))));
      await tester.pumpWidget(_app(FadeSwitcher(child: withHero('new'))));
      await tester.pump(AppMotion.medium ~/ 2);

      bool heroesOn(String label) => tester
          .widget<HeroMode>(find.ancestor(of: find.text(label), matching: find.byType(HeroMode)).first)
          .enabled;
      expect(heroesOn('old'), isFalse);
      expect(heroesOn('new'), isTrue);
    });

    testWidgets('lets a page open mid cross-fade without a hero tag clash', (tester) async {
      Widget page(String label) => FadeSwitcher(
            child: Builder(
              key: ValueKey(label),
              builder: (context) => GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Hero(tag: 'cover', child: Text('detail'))),
                )),
                child: Hero(tag: 'cover', child: Text(label)),
              ),
            ),
          );
      await tester.pumpWidget(_app(page('list')));
      await tester.pumpWidget(_app(page('list again')));
      await tester.pump(AppMotion.medium ~/ 2);

      await tester.tap(find.text('list again'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('swaps at once when motion is reduced', (tester) async {
      await tester.pumpWidget(_app(const FadeSwitcher(child: Text('skeleton', key: ValueKey('a'))), reduceMotion: true));
      await tester.pumpWidget(_app(const FadeSwitcher(child: Text('content', key: ValueKey('b'))), reduceMotion: true));
      await tester.pump();

      expect(find.text('skeleton'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });

  group('StaggeredEntrance', () {
    testWidgets('fades the first items in, one after another', (tester) async {
      await tester.pumpWidget(_app(const Column(children: [
        StaggeredEntrance(index: 0, child: Text('first')),
        StaggeredEntrance(index: 3, child: Text('fourth')),
      ])));

      expect(_opacityOf(tester, find.text('first')), 0);
      await tester.pump(StaggeredEntrance.step * 2);
      expect(_opacityOf(tester, find.text('first')), greaterThan(0));
      expect(_opacityOf(tester, find.text('fourth')), 0);

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.text('first')), 1);
      expect(_opacityOf(tester, find.text('fourth')), 1);
    });

    testWidgets('shows items past the cascade at once', (tester) async {
      await tester.pumpWidget(_app(const StaggeredEntrance(index: StaggeredEntrance.maxStaggered, child: Text('late'))));

      expect(_opacityOf(tester, find.text('late')), 1);
    });

    testWidgets('shows items at once when motion is reduced', (tester) async {
      await tester.pumpWidget(_app(const StaggeredEntrance(index: 0, child: Text('first')), reduceMotion: true));

      expect(_opacityOf(tester, find.text('first')), 1);
    });

    testWidgets('does not replay for items rebuilt long after their list loaded', (tester) async {
      Widget list(bool showItem) => _app(EntranceGate(
            trigger: 'page-1',
            child: Column(children: [if (showItem) const StaggeredEntrance(index: 0, child: Text('first'))]),
          ));
      await tester.pumpWidget(list(false));
      await tester.pump(EntranceGate.window + const Duration(milliseconds: 1));

      // E.g. the item scrolled back into a lazy list.
      await tester.pumpWidget(list(true));

      expect(_opacityOf(tester, find.text('first')), 1);
    });

    testWidgets('plays again when the gate gets new data', (tester) async {
      Widget list(String trigger) => _app(EntranceGate(
            trigger: trigger,
            child: StaggeredEntrance(key: ValueKey(trigger), index: 0, child: const Text('first')),
          ));
      await tester.pumpWidget(list('page-1'));
      await tester.pumpAndSettle();
      await tester.pump(EntranceGate.window);

      await tester.pumpWidget(list('page-2'));

      expect(_opacityOf(tester, find.text('first')), 0);
      await tester.pumpAndSettle();
    });
  });

  group('AnimatedCount', () {
    testWidgets('rolls to the new value', (tester) async {
      await tester.pumpWidget(_app(const AnimatedCount(value: 4)));
      expect(find.text('4'), findsOneWidget);

      await tester.pumpWidget(_app(const AnimatedCount(value: 5)));
      await tester.pump(AppMotion.short ~/ 2);
      expect(find.text('5'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('4'), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('is a plain text while idle, before and after a roll', (tester) async {
      Finder machinery() => find.descendant(of: find.byType(AnimatedCount), matching: find.byType(ClipRect));
      await tester.pumpWidget(_app(const AnimatedCount(value: 4)));
      expect(machinery(), findsNothing);

      await tester.pumpWidget(_app(const AnimatedCount(value: 5)));
      await tester.pump(AppMotion.short ~/ 2);
      expect(machinery(), findsOneWidget);

      await tester.pumpAndSettle();
      expect(machinery(), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('rolls downwards when the value falls', (tester) async {
      await tester.pumpWidget(_app(const Center(child: AnimatedCount(value: 5))));
      final restY = tester.getTopLeft(find.text('5')).dy;
      await tester.pumpWidget(_app(const Center(child: AnimatedCount(value: 4))));
      await tester.pump(AppMotion.short ~/ 3);

      // The new value comes from above, the old one leaves downwards.
      expect(tester.getTopLeft(find.text('4')).dy, lessThan(restY));
      expect(tester.getTopLeft(find.text('5')).dy, greaterThan(restY));
      await tester.pumpAndSettle();
    });

    testWidgets('jumps to the new value when motion is reduced', (tester) async {
      await tester.pumpWidget(_app(const AnimatedCount(value: 4), reduceMotion: true));
      await tester.pumpWidget(_app(const AnimatedCount(value: 5), reduceMotion: true));

      expect(find.text('4'), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('uses the given format', (tester) async {
      await tester.pumpWidget(_app(AnimatedCount(value: 12, format: (v) => '$v / 24')));

      expect(find.text('12 / 24'), findsOneWidget);
    });
  });

  group('PopOnChange', () {
    testWidgets('briefly enlarges its child when the value changes', (tester) async {
      await tester.pumpWidget(_app(const PopOnChange(value: false, child: Icon(Icons.favorite))));
      await tester.pumpWidget(_app(const PopOnChange(value: true, child: Icon(Icons.favorite))));

      await tester.pump(AppMotion.medium ~/ 3);
      expect(_scaleOf(tester, find.byIcon(Icons.favorite)), greaterThan(1));

      await tester.pumpAndSettle();
      expect(_scaleOf(tester, find.byIcon(Icons.favorite)), 1);
    });

    testWidgets('stays still when only the parent rebuilds', (tester) async {
      await tester.pumpWidget(_app(const PopOnChange(value: true, child: Icon(Icons.favorite))));
      await tester.pumpWidget(_app(const PopOnChange(value: true, child: Icon(Icons.favorite))));
      await tester.pump(AppMotion.medium ~/ 3);

      expect(_scaleOf(tester, find.byIcon(Icons.favorite)), 1);
    });

    testWidgets('can pop only for some values', (tester) async {
      await tester.pumpWidget(_app(PopOnChange(value: true, when: (v) => v == true, child: const Icon(Icons.favorite))));
      await tester.pumpWidget(_app(PopOnChange(value: false, when: (v) => v == true, child: const Icon(Icons.favorite))));
      await tester.pump(AppMotion.medium ~/ 3);

      expect(_scaleOf(tester, find.byIcon(Icons.favorite)), 1);
    });
  });

  group('PopIn', () {
    testWidgets('grows into place when it first appears', (tester) async {
      await tester.pumpWidget(_app(const PopIn(child: Icon(Icons.home))));

      expect(_scaleOf(tester, find.byIcon(Icons.home)), lessThan(1));
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, find.byIcon(Icons.home)), 1);
    });

    testWidgets('appears at full size when motion is reduced', (tester) async {
      await tester.pumpWidget(_app(const PopIn(child: Icon(Icons.home)), reduceMotion: true));

      expect(_scaleOf(tester, find.byIcon(Icons.home)), 1);
    });
  });

  group('TabFadeThrough', () {
    testWidgets('fades a tab in when it becomes active', (tester) async {
      Widget tab(bool active) => _app(TabFadeThrough(active: active, child: const Text('feed')));
      await tester.pumpWidget(tab(false));
      await tester.pumpWidget(tab(true));

      expect(_opacityOf(tester, find.text('feed')), lessThan(1));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.text('feed')), 1);
    });

    testWidgets('pauses the animations of a tab while it is hidden', (tester) async {
      late bool tickersOn;
      Widget tab(bool active) => _app(TabFadeThrough(
            active: active,
            child: Builder(builder: (context) {
              tickersOn = TickerMode.valuesOf(context).enabled;
              return const Text('feed');
            }),
          ));

      await tester.pumpWidget(tab(false));
      expect(tickersOn, isFalse);

      await tester.pumpWidget(tab(true));
      expect(tickersOn, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('shows the first active tab without animating', (tester) async {
      await tester.pumpWidget(_app(const TabFadeThrough(active: true, child: Text('home'))));

      expect(_opacityOf(tester, find.text('home')), 1);
    });
  });
}
