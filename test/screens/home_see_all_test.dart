import 'dart:io';

import 'package:anispark/screens/browse_screen.dart';
import 'package:anispark/screens/home_screen.dart';
import 'package:anispark/screens/season_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/browse_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _show(int id) => {
      'id': id,
      'title': {'english': 'Show $id'},
      'averageScore': 70,
    };

void main() {
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  setUp(() => cache = ApiCache(MemoryCacheStore()));

  /// "See all" in the header titled [title].
  Finder seeAllOf(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
        matching: find.text(_en('home_see_all')),
      );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();
  }

  Future<void> openSeeAll(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(seeAllOf(title), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(seeAllOf(title));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  final rows = {
    'trending': ('discover:trending', BrowseQuery.trending),
    'top_airing': ('discover:topAiring', BrowseQuery.topAiring),
    'home_trending_manga': ('discover:trendingManga', BrowseQuery.trendingManga),
    'home_top_manga': ('discover:topManga', BrowseQuery.topManga),
    'home_popular_manhwa': ('discover:manhwa', BrowseQuery.manhwa),
  };

  for (final MapEntry(key: titleKey, value: (cacheKey, query)) in rows.entries) {
    testWidgets('See all on ${_en(titleKey)} opens its filterable grid with the row items', (tester) async {
      await cache.write(cacheKey, [_show(1), _show(2)]);
      await pumpHome(tester);

      await openSeeAll(tester, _en(titleKey));

      final screen = tester.widget<BrowseScreen>(find.byType(BrowseScreen));
      expect(screen.query, query);
      expect(screen.title, _en(titleKey));
      expect(screen.initialItems.map((item) => (item as Map)['id']), [1, 2]);
      expect(find.descendant(of: find.byType(BrowseScreen), matching: find.text('Show 2')), findsOneWidget);
    });
  }

  testWidgets('the season rows still open the season browser', (tester) async {
    await cache.write('discover:topManga', [_show(1)]);
    await pumpHome(tester);

    // Trending is empty, so the first See all is the current season's.
    await tester.tap(find.text(_en('home_see_all')).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SeasonScreen), findsOneWidget);
    expect(find.byType(BrowseScreen), findsNothing);
  });

  testWidgets('an empty row has no See all', (tester) async {
    await cache.write('discover:topAiring', [_show(1)]);
    await pumpHome(tester);

    expect(seeAllOf(_en('top_airing')), findsOneWidget);
    expect(find.text(_en('trending')), findsOneWidget);
    expect(seeAllOf(_en('trending')), findsNothing);
  });
}
