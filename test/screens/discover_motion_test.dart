import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/screens/home_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/tab_reselect.dart';
import 'package:anispark/widgets/motion/cover_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

const _bebop = {
  'id': 1,
  'title': {'english': 'Cowboy Bebop'},
  'averageScore': 86,
};

Map<String, dynamic> _show(int id) => {
      'id': id,
      'title': {'english': 'Show $id'},
      'averageScore': 70,
    };

void main() {
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  setUp(() => cache = ApiCache(MemoryCacheStore()));

  testWidgets('a media in two rows opens its detail page, its cover flying from the tapped row',
      (tester) async {
    await cache.write('discover:trending', [_bebop]);
    await cache.write('discover:topAiring', [_bebop]);

    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();

    // Each row gives the cover a tag of its own.
    final tags = tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag).toList();
    expect(tags, containsAll([coverHeroTag('home-trending', 1), coverHeroTag('home-top-airing', 1)]));
    expect(tags.toSet(), hasLength(tags.length), reason: 'no two heroes share a tag');

    await tester.tap(find.text('Cowboy Bebop').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // In flight: two heroes with one tag on a page would have thrown.
    expect(tester.takeException(), isNull);
    final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
    expect(detail.animeId, 1);
    expect(detail.heroTag, coverHeroTag('home-trending', 1));

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DetailScreen), findsOneWidget);
  });

  testWidgets('tapping Discover again scrolls it back to the top', (tester) async {
    await cache.write('discover:trending', [for (var i = 1; i <= 5; i++) _show(i)]);
    await cache.write('discover:topAiring', [for (var i = 6; i <= 10; i++) _show(i)]);
    await cache.write('discover:topManga', [for (var i = 11; i <= 15; i++) _show(i)]);

    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first,
        )
        .position;

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, -500));
    await tester.pumpAndSettle();
    final scrolled = position.pixels;
    expect(scrolled, greaterThan(0));

    tabReselectedNotifier.reselect(0);
    await tester.pumpAndSettle();
    expect(position.pixels, scrolled, reason: 'another tab was tapped');

    tabReselectedNotifier.reselect(2);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
  });

  testWidgets('with animations removed, it jumps back to the top', (tester) async {
    await cache.write('discover:trending', [for (var i = 1; i <= 5; i++) _show(i)]);
    await cache.write('discover:topAiring', [for (var i = 6; i <= 10; i++) _show(i)]);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first,
        )
        .position;
    await tester.drag(find.byType(RefreshIndicator), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    tabReselectedNotifier.reselect(2);
    await tester.pump();

    expect(position.pixels, 0, reason: 'no animation to wait for');
  });
}
