import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/screens/studio_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/people_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/motion/cover_hero.dart';
import 'package:anispark/widgets/people/media_cover_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _media(int id, {bool isAdult = false}) => {
      'id': id,
      'format': 'TV',
      'isAdult': isAdult,
      'averageScore': 84,
      'title': {'english': 'Show $id'},
      'startDate': {'year': 2006},
    };

Map<String, dynamic> _page(List<int> ids, {bool hasNextPage = false}) => {
      'pageInfo': {'hasNextPage': hasNextPage},
      'nodes': [for (final id in ids) _media(id)],
    };

http.Response _studio({required Map<String, dynamic> main, required Map<String, dynamic> other}) => jsonResponse({
      'data': {
        'Studio': {
          'id': 11,
          'name': 'MADHOUSE',
          'isAnimationStudio': true,
          'favourites': 20044,
          'main': main,
          'other': other,
        },
      },
    });

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  PeopleApi apiAnswering(http.Response Function(RecordedRequest) handler) =>
      PeopleApi(service: AniListService(client: mockAniList(log, handler)));

  // Spinners never settle, so pump a fixed number of frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpStudio(WidgetTester tester, PeopleApi api) async {
    await tester.pumpWidget(appWith(StudioScreen(studioId: 11, name: 'Madhouse', api: api), cache: cache));
    await settle(tester);
  }

  testWidgets('shows the main productions, then the rest, and caches them', (tester) async {
    await pumpStudio(
      tester,
      apiAnswering((_) => _studio(main: _page([1, 2]), other: _page([3]))),
    );

    expect(find.text('MADHOUSE'), findsWidgets);
    expect(find.text('20K'), findsOneWidget);
    expect(find.byType(MediaCoverTile), findsNWidgets(3));
    expect(find.text('Show 1'), findsOneWidget);
    expect(find.text('TV · 2006'), findsNWidgets(3));
    expect(find.text('★ 8.4'), findsNWidgets(3));
    final mainTitle = find.text(_en('studio_main_productions').toUpperCase());
    final otherTitle = find.text(_en('studio_other_productions').toUpperCase());
    expect(mainTitle, findsOneWidget);
    expect(otherTitle, findsOneWidget);
    expect(tester.getTopLeft(find.text('Show 2')).dy, lessThan(tester.getTopLeft(otherTitle).dy));
    expect(tester.getTopLeft(find.text('Show 3')).dy, greaterThan(tester.getTopLeft(otherTitle).dy));
    expect(log, hasLength(1));
    expect(await cache.read('studio:11'), isNotNull);
  });

  testWidgets('keeps the rest hidden until the main productions run out', (tester) async {
    await pumpStudio(
      tester,
      apiAnswering((request) {
        if (request.query.contains('media(isMain: \$isMain')) {
          return jsonResponse({
            'data': {
              'Studio': {'media': _page([2, 4])},
            },
          });
        }
        return _studio(main: _page([1, 2], hasNextPage: true), other: _page([3]));
      }),
    );

    // The short grid asks for the next main page right away.
    expect(log, hasLength(2));
    expect(log.last.variables, {'id': 11, 'isMain': true, 'page': 2, 'perPage': PeopleApi.studioPageSize});
    expect(find.text('Show 4'), findsOneWidget);
    expect(find.text('Show 2'), findsOneWidget, reason: 'repeats across pages are dropped');
    expect(find.text('Show 3'), findsOneWidget, reason: 'shown once the main productions ended');
    expect(find.byType(MediaCoverTile), findsNWidgets(4));
  });

  testWidgets('shows a producer\'s productions without group titles', (tester) async {
    await pumpStudio(
      tester,
      apiAnswering((_) => _studio(main: _page([]), other: _page([5, 6]))),
    );

    expect(find.byType(MediaCoverTile), findsNWidgets(2));
    expect(find.text(_en('studio_main_productions').toUpperCase()), findsNothing);
    expect(find.text(_en('studio_other_productions').toUpperCase()), findsNothing);
  });

  testWidgets('opens a production with its cover flying from the grid', (tester) async {
    await pumpStudio(tester, apiAnswering((_) => _studio(main: _page([1]), other: _page([]))));

    await tester.tap(find.text('Show 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final detail = tester.widget<DetailScreen>(find.byType(DetailScreen));
    expect(detail.animeId, 1);
    expect(detail.heroTag, coverHeroTag('studio-11-main', 1));
  });

  testWidgets('shows an error with retry and the known name when loading fails', (tester) async {
    await pumpStudio(tester, apiAnswering((_) => jsonResponse({'errors': []}, status: 500)));

    expect(find.text('Madhouse'), findsWidgets);
    expect(find.text(loadErrorText), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(log, hasLength(2));
  });
}
