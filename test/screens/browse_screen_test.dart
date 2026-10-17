import 'dart:async';
import 'dart:io';

import 'package:anispark/screens/browse_screen.dart';
import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/browse_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _media(int id, {String prefix = 'Show'}) => {
      'id': id,
      'type': 'ANIME',
      'format': 'TV',
      'episodes': 12,
      'averageScore': 82,
      'title': {'english': '$prefix $id'},
    };

http.Response _page(List<int> ids, {bool hasNextPage = false, String prefix = 'Show'}) => jsonResponse({
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'media': [for (final id in ids) _media(id, prefix: prefix)],
        },
      },
    });

/// Ids of a full page [page] (1-based).
List<int> _fullPage(int page) => [for (var i = 0; i < BrowseApi.pageSize; i++) page * 100 + i];

/// An AniList whose answers wait until the test gives them, in any order.
class _HeldAniList {
  final requests = <RecordedRequest>[];
  final _answers = <Completer<http.Response>>[];

  late final client = MockClient((request) {
    requests.add(RecordedRequest(request));
    final answer = Completer<http.Response>();
    _answers.add(answer);
    return answer.future;
  });

  void answer(int index, http.Response response) => _answers[index].complete(response);
}

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;

  // Detail pages opened from the grid load through the shared client.
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  BrowseApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      BrowseApi(service: AniListService(client: mockAniList(log, handler)));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    // Past the cross-fades.
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpBrowse(
    WidgetTester tester,
    BrowseApi api, {
    BrowseQuery query = BrowseQuery.trending,
    List<dynamic> initialItems = const [],
  }) async {
    await tester.pumpWidget(appWith(
      BrowseScreen(title: 'ROW', query: query, initialItems: initialItems, api: api),
      cache: cache,
    ));
    await settle(tester);
  }

  /// Opens the sheet of the filter bar's [pill] (e.g. `browse-sort`).
  Future<void> openPill(WidgetTester tester, String pill) async {
    await tester.tap(find.byKey(ValueKey(pill)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pickOption(WidgetTester tester, String pill, Object option) async {
    await openPill(tester, pill);
    await tester.tap(find.byKey(ValueKey('browse-option-$option')));
    await settle(tester);
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -30000));
    await settle(tester);
  }

  testWidgets('shows the row items at once, then replaces them with the first page', (tester) async {
    final held = _HeldAniList();
    final api = BrowseApi(service: AniListService(client: held.client));
    await pumpBrowse(tester, api, initialItems: [_media(1, prefix: 'Row'), _media(2, prefix: 'Row')]);

    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 2'), findsOneWidget);
    expect(held.requests.single.variables, {
      'page': 1,
      'perPage': BrowseApi.pageSize,
      'type': 'ANIME',
      'sort': ['TRENDING_DESC', 'ID'],
    });

    held.answer(0, _page([1, 2, 3]));
    await settle(tester);

    expect(find.text('Show 3'), findsOneWidget);
    expect(find.text('Row 1'), findsNothing);
  });

  testWidgets('caches the first page of the unfiltered row and reuses it', (tester) async {
    final api = apiAnswering((_) => _page([1, 2]));
    await pumpBrowse(tester, api);
    expect(log, hasLength(1));
    expect(await cache.read('browse:trending'), isNotNull);

    await tester.pumpWidget(const SizedBox());
    await pumpBrowse(tester, api);

    expect(log, hasLength(1), reason: 'a fresh cached page needs no request');
    expect(find.text('Show 2'), findsOneWidget);
  });

  testWidgets('changing the sort reloads from page 1', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    await pickOption(tester, 'browse-sort', 'SCORE_DESC');

    expect(log, hasLength(2));
    expect(log.last.variables['sort'], ['SCORE_DESC', 'ID']);
    expect(log.last.variables['page'], 1);
    expect(find.descendant(of: find.byKey(const ValueKey('browse-sort')), matching: find.text(_en('search_sort_score'))),
        findsOneWidget, reason: 'the pill shows the current sort');
    expect(await cache.read('browse:trending'), isNotNull);
  });

  testWidgets('picking a minimum rating reloads from page 1', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    await pickOption(tester, 'browse-rating', 70);

    expect(log.last.variables['averageScore_greater'], 69);
    expect(log.last.variables['page'], 1);
    expect(log.last.variables['sort'], ['TRENDING_DESC', 'ID']);
  });

  testWidgets('genres apply together when the sheet is applied', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    await openPill(tester, 'browse-genres');
    await tester.tap(find.text(_en('search_genre_drama')));
    await tester.tap(find.text(_en('search_genre_action')));
    await tester.pump();
    expect(log, hasLength(1), reason: 'nothing loads while picking');
    await tester.tap(find.text(_en('apply')));
    await settle(tester);

    expect(log, hasLength(2));
    expect(log.last.variables['genre_in'], ['Action', 'Drama']);
    expect(log.last.variables['page'], 1);
    expect(find.descendant(of: find.byKey(const ValueKey('browse-genres')), matching: find.text('${_en('search_genre_action')} +1')),
        findsOneWidget, reason: 'the pill shows the picked genres');
  });

  testWidgets('genres picked before swiping the sheet away still apply', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    await openPill(tester, 'browse-genres');
    await tester.tap(find.text(_en('search_genre_horror')));
    await tester.pump();
    await tester.tapAt(const Offset(20, 20)); // the scrim
    await settle(tester);

    expect(log.last.variables['genre_in'], ['Horror']);
  });

  testWidgets('anime formats reload from page 1', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    await openPill(tester, 'browse-format');
    expect(find.byKey(const ValueKey('browse-option-ONE_SHOT')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('browse-option-MOVIE')));
    await tester.tap(find.byKey(const ValueKey('browse-option-TV_SHORT')));
    await tester.tap(find.text(_en('apply')));
    await settle(tester);

    expect(log.last.variables['format_in'], ['MOVIE', 'TV_SHORT']);
    expect(log.last.variables['page'], 1);
  });

  testWidgets('manga offer manga and one-shot formats', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api, query: BrowseQuery.topManga);

    await openPill(tester, 'browse-format');

    expect(find.text(_en('source_manga')), findsOneWidget);
    expect(find.text(_en('detail_format_one_shot')), findsOneWidget);
    expect(find.text(_en('movie')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('browse-option-ONE_SHOT')));
    await tester.tap(find.text(_en('apply')));
    await settle(tester);

    expect(log.last.variables['format_in'], ['ONE_SHOT']);
    expect(log.last.variables['format_not'], 'NOVEL', reason: 'the row keeps its own filters');
  });

  testWidgets('Clear appears with a filter and resets them all', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api, query: BrowseQuery.topAiring);
    final unfiltered = log.single.variables;
    expect(find.byKey(const ValueKey('browse-clear')), findsNothing);

    await pickOption(tester, 'browse-sort', 'SCORE_DESC');
    await pickOption(tester, 'browse-rating', 80);
    expect(find.byKey(const ValueKey('browse-clear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browse-clear')));
    await settle(tester);

    expect(find.byKey(const ValueKey('browse-clear')), findsNothing);
    expect(log, hasLength(3), reason: 'the unfiltered first page comes from the cache');
    expect(find.text('Show 1'), findsOneWidget);

    // And from AniList once the cache has nothing.
    await cache.clear();
    await pickOption(tester, 'browse-rating', 60);
    await tester.tap(find.byKey(const ValueKey('browse-clear')));
    await settle(tester);
    expect(log.last.variables, unfiltered);
  });

  testWidgets('filters matching nothing show an empty state that clears them', (tester) async {
    final api = apiAnswering((r) => r.variables.containsKey('genre_in') ? _page([]) : _page([1, 2]));
    await pumpBrowse(tester, api);

    await openPill(tester, 'browse-genres');
    await tester.tap(find.text(_en('search_genre_mecha')));
    await tester.tap(find.text(_en('apply')));
    await settle(tester);

    expect(find.byKey(const ValueKey('browse-empty-clear')), findsOneWidget);
    expect(find.text('Show 1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('browse-empty-clear')));
    await settle(tester);

    expect(find.text('Show 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('browse-empty-clear')), findsNothing);
  });

  testWidgets('loads more pages on scroll and stops at the last one', (tester) async {
    final api = apiAnswering((r) {
      final page = r.variables['page'] as int;
      return _page(_fullPage(page), hasNextPage: page < 2);
    });
    await pumpBrowse(tester, api);
    expect(log, hasLength(1));

    await scrollToEnd(tester);
    expect(log.map((r) => r.variables['page']), [1, 2]);
    expect(log.last.variables['sort'], ['TRENDING_DESC', 'ID']);

    await scrollToEnd(tester);
    expect(log, hasLength(2), reason: 'page 2 was the last one');
    expect(find.text('Show 2${BrowseApi.pageSize - 1}'), findsOneWidget);
  });

  testWidgets('stops at an empty page even if AniList reports more', (tester) async {
    final api = apiAnswering((r) {
      final page = r.variables['page'] as int;
      return _page(page == 1 ? _fullPage(1) : [], hasNextPage: true);
    });
    await pumpBrowse(tester, api);

    for (var i = 0; i < 3; i++) {
      await scrollToEnd(tester);
    }

    expect(log.map((r) => r.variables['page']), [1, 2]);
  });

  testWidgets('a failed page shows a retry footer and waits for it', (tester) async {
    var failPage2 = true;
    final api = apiAnswering((r) {
      final page = r.variables['page'] as int;
      if (page == 2 && failPage2) return jsonResponse({'errors': []}, status: 500);
      return _page(_fullPage(page), hasNextPage: page < 2);
    });
    await pumpBrowse(tester, api);

    await scrollToEnd(tester);
    expect(log.map((r) => r.variables['page']), [1, 2]);
    expect(find.text(_en('retry')), findsOneWidget);

    await scrollToEnd(tester);
    expect(log, hasLength(2), reason: 'scrolling does not retry by itself');

    failPage2 = false;
    await tester.tap(find.text(_en('retry')));
    await settle(tester);

    expect(log.map((r) => r.variables['page']), [1, 2, 2]);
    expect(find.text(_en('retry')), findsNothing);
  });

  testWidgets('a failed first page with nothing to show offers a retry', (tester) async {
    var fail = true;
    final api = apiAnswering((_) => fail ? jsonResponse({'errors': []}, status: 500) : _page([1]));
    await pumpBrowse(tester, api);

    expect(find.text(_en('retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.text(_en('retry')));
    await settle(tester);

    expect(find.text('Show 1'), findsOneWidget);
  });

  testWidgets('ignores a first page that arrives after the filters changed', (tester) async {
    final held = _HeldAniList();
    final api = BrowseApi(service: AniListService(client: held.client));
    await pumpBrowse(tester, api, initialItems: [_media(1, prefix: 'Row')]);

    await pickOption(tester, 'browse-sort', 'POPULARITY_DESC');
    expect(held.requests, hasLength(2));

    held.answer(1, _page([5], prefix: 'New'));
    await settle(tester);
    held.answer(0, _page([9], prefix: 'Old'));
    await settle(tester);

    expect(find.text('New 5'), findsOneWidget);
    expect(find.text('Old 9'), findsNothing);
    expect(find.text('Row 1'), findsNothing);
  });

  testWidgets('a page that arrives after the filters changed is ignored', (tester) async {
    final held = _HeldAniList();
    final api = BrowseApi(service: AniListService(client: held.client));
    await pumpBrowse(tester, api);
    held.answer(0, _page(_fullPage(1), hasNextPage: true));
    await settle(tester);

    await scrollToEnd(tester);
    expect(held.requests.last.variables['page'], 2);

    await pickOption(tester, 'browse-rating', 60);
    held.answer(2, _page([7], prefix: 'Rated'));
    await settle(tester);
    held.answer(1, _page(_fullPage(2), prefix: 'Stale'));
    await settle(tester);

    expect(find.text('Rated 7'), findsOneWidget);
    expect(find.textContaining('Stale'), findsNothing);
  });

  testWidgets('a cover opens its detail page with the grid hero tag', (tester) async {
    final api = apiAnswering((_) => _page([1, 2]));
    await pumpBrowse(tester, api);
    final tags = tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag).toList();
    expect(tags, hasLength(2));

    await tester.tap(find.text('Show 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
    expect(detail.animeId, 2);
    expect(detail.heroTag, tags.last);
    expect('${detail.heroTag}', contains('browse'));
  });

  testWidgets('another filter set gets its own hero tags', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);
    final before = tester.widget<Hero>(find.byType(Hero)).tag;

    await pickOption(tester, 'browse-sort', 'SCORE_DESC');

    expect(tester.widget<Hero>(find.byType(Hero)).tag, isNot(before));
  });

  testWidgets('a new filter shows its results from the top', (tester) async {
    final api = apiAnswering((r) => _page(_fullPage(r.variables['page'] as int), hasNextPage: true));
    await pumpBrowse(tester, api);
    await scrollToEnd(tester);
    ScrollPosition gridPosition() => tester
        .state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)))
        .position;
    expect(gridPosition().pixels, greaterThan(0));

    await pickOption(tester, 'browse-sort', 'POPULARITY_DESC');

    expect(log.last.variables['page'], 1);
    expect(gridPosition().pixels, 0);
  });

  double opacityOf(WidgetTester tester, String title) => tester
      .widget<FadeTransition>(find.ancestor(of: find.text(title), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  testWidgets('each new result set cascades in', (tester) async {
    final api = apiAnswering((r) => _page([1, 2], prefix: '${(r.variables['sort'] as List).first}'));
    await pumpBrowse(tester, api);
    await tester.pump(const Duration(seconds: 1));

    await openPill(tester, 'browse-sort');
    await tester.tap(find.byKey(const ValueKey('browse-option-SCORE_DESC')));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(opacityOf(tester, 'SCORE_DESC 2'), lessThan(1), reason: 'entering');
    await tester.pump(const Duration(seconds: 1));
    expect(opacityOf(tester, 'SCORE_DESC 2'), 1);
  });

  testWidgets('the first page replacing the row items does not replay the cascade', (tester) async {
    final held = _HeldAniList();
    final api = BrowseApi(service: AniListService(client: held.client));
    await pumpBrowse(tester, api, initialItems: [_media(1), _media(2)]);
    await tester.pump(const Duration(seconds: 1));

    held.answer(0, _page([1, 2, 3]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Show 3'), findsOneWidget);
    for (final title in ['Show 1', 'Show 2']) {
      expect(find.text(title), findsOneWidget, reason: 'the grid stays; no cross-fade');
      final fades = tester.widgetList<FadeTransition>(
          find.ancestor(of: find.text(title), matching: find.byType(FadeTransition)));
      expect(fades.map((fade) => fade.opacity.value), everyElement(1.0), reason: title);
    }
  });

  testWidgets('covers scrolled back into view appear at once', (tester) async {
    final api = apiAnswering((r) => _page(_fullPage(r.variables['page'] as int), hasNextPage: r.variables['page'] == 1));
    await pumpBrowse(tester, api);
    await tester.pump(const Duration(seconds: 1));
    await scrollToEnd(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 30000));
    await tester.pump();

    expect(opacityOf(tester, 'Show 100'), 1);
  });

  testWidgets('filter pills have a tap area of at least 44 px', (tester) async {
    final api = apiAnswering((_) => _page([1]));
    await pumpBrowse(tester, api);

    for (final pill in ['browse-sort', 'browse-rating', 'browse-genres', 'browse-format']) {
      expect(tester.getSize(find.byKey(ValueKey(pill))).height, greaterThanOrEqualTo(44), reason: pill);
    }
  });
}
