import 'package:anispark/screens/season_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/discover_api.dart';
import 'package:anispark/utils/anime_season.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

String _en(String key) => tr(key, 'English');

http.Response _page(int page, {required int count, bool hasNextPage = false}) => jsonResponse({
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'media': [
            for (var i = 0; i < count; i++)
              {
                'id': page * 100 + i,
                'format': 'TV',
                'episodes': 12,
                'averageScore': 86,
                'title': {'english': 'Show $page-$i'},
              },
          ],
        },
      },
    });

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;
  // This year's fall, so the next season (next winter) is still browsable.
  final fall = SeasonYear(AnimeSeason.fall, DateTime.now().year);

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  DiscoverApi apiAnswering(http.Response Function(RecordedRequest) handler) =>
      DiscoverApi(service: AniListService(client: mockAniList(log, handler)));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpSeason(WidgetTester tester, DiscoverApi api) async {
    await tester.pumpWidget(appWith(SeasonScreen(initial: fall, api: api), cache: cache));
    await settle(tester);
  }

  testWidgets('loads the initial season by popularity and caches it', (tester) async {
    await pumpSeason(tester, apiAnswering((r) => _page(1, count: 2)));

    expect(find.text('Show 1-0'), findsOneWidget);
    expect(find.text('★ 8.6'), findsNWidgets(2));
    expect(log.single.variables, containsPair('season', 'FALL'));
    expect(log.single.variables, containsPair('seasonYear', fall.year));
    expect(log.single.variables['sort'], ['POPULARITY_DESC', 'ID']);
    expect(log.single.variables.containsKey('formats'), isFalse);
    expect(await cache.read('season:${fall.key}:POPULARITY_DESC:ALL:p1'), isNotNull);
  });

  testWidgets('loads the next page when scrolled to the end', (tester) async {
    await pumpSeason(
      tester,
      apiAnswering((r) => _page(r.variables['page'] as int,
          count: DiscoverApi.seasonPageSize, hasNextPage: r.variables['page'] == 1)),
    );
    expect(log, hasLength(1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await settle(tester);

    expect(log.map((r) => r.variables['page']), [1, 2]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await settle(tester);

    expect(log, hasLength(2), reason: 'page 2 was the last one');
    expect(find.text('Show 2-${DiscoverApi.seasonPageSize - 1}'), findsOneWidget);
  });

  testWidgets('stops paging at an empty page even if AniList reports more', (tester) async {
    await pumpSeason(
      tester,
      apiAnswering((r) => _page(r.variables['page'] as int,
          count: r.variables['page'] == 1 ? DiscoverApi.seasonPageSize : 0, hasNextPage: true)),
    );

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
      await settle(tester);
    }

    expect(log.map((r) => r.variables['page']), [1, 2], reason: 'an empty page 2 is the end');
  });

  testWidgets('filters by format and steps to the next season', (tester) async {
    await pumpSeason(tester, apiAnswering((r) => _page(1, count: 1)));

    await tester.tap(find.widgetWithText(FilterChip, _en('movie')));
    await settle(tester);

    expect(log.last.variables['formats'], ['MOVIE']);
    expect(log.last.variables['page'], 1);

    await tester.tap(find.byTooltip(_en('season_next')));
    await settle(tester);

    expect(log.last.variables, containsPair('season', 'WINTER'));
    expect(log.last.variables, containsPair('seasonYear', fall.year + 1));
    expect(log.last.variables['formats'], ['MOVIE'], reason: 'filters are kept');
  });

  testWidgets('changes the sort from the menu', (tester) async {
    await pumpSeason(tester, apiAnswering((r) => _page(1, count: 1)));

    await tester.tap(find.byTooltip(_en('search_sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('search_sort_score')).last);
    await settle(tester);

    expect(log.last.variables['sort'], ['SCORE_DESC', 'ID']);
  });

  testWidgets('clamps an initial season outside the browsable range', (tester) async {
    final api = apiAnswering((r) => _page(1, count: 1));
    await tester.pumpWidget(appWith(
      SeasonScreen(initial: const SeasonYear(AnimeSeason.spring, 1900), api: api),
      cache: cache,
    ));
    await settle(tester);

    expect(log.single.variables, containsPair('season', 'WINTER'));
    expect(log.single.variables, containsPair('seasonYear', 1940));
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed,
      isNull,
      reason: 'no earlier season to go to',
    );
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    await pumpSeason(tester, apiAnswering((_) => jsonResponse({'errors': []}, status: 500)));

    expect(find.text(_en('load_error')), findsOneWidget);

    await tester.tap(find.text(_en('retry')));
    await settle(tester);

    expect(log, hasLength(2));
  });
}
