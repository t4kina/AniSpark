import 'dart:async';

import 'package:anispark/screens/search_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    log = [];
  });

  AniListService aniList() => AniListService(
        client: mockAniList(log, (_) => jsonResponse({
              'data': {
                'Page': {
                  'media': [
                    {'id': 1, 'type': 'ANIME', 'format': 'TV', 'title': {'english': 'Frieren'}, 'episodes': 28},
                    {'id': 2, 'type': 'MANGA', 'format': 'MANGA', 'title': {'english': 'Frieren (manga)'}, 'chapters': 140},
                  ],
                },
              },
            })),
      );

  Future<void> searchFor(WidgetTester tester, String query) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screenApp(SearchScreen(service: aniList()), cache: ApiCache(MemoryCacheStore())));
    await tester.enterText(find.byType(TextField), query);
    // Past the 400 ms debounce.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('searches anime and manga together by default', (tester) async {
    await searchFor(tester, 'frieren');

    expect(log.last.variables.containsKey('type'), isFalse, reason: 'no type: AniList returns both');
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Frieren (manga)'), findsOneWidget);
    expect(find.text('All'), findsOneWidget, reason: 'the content type pill');
  });

  testWidgets('narrowing to anime asks AniList for anime only', (tester) async {
    await searchFor(tester, 'frieren');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Anime'), findsOneWidget, reason: 'All, Anime and Manga are offered');
    expect(find.text('Manga'), findsOneWidget);
    await tester.tap(find.text('Anime'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(log.last.variables['type'], 'ANIME');
  });

  testWidgets('shows the shape of the results, not a spinner, while it searches', (tester) async {
    final response = Completer<http.Response>();
    final service = AniListService(client: MockClient((_) => response.future));
    await tester.pumpWidget(screenApp(SearchScreen(service: service), cache: ApiCache(MemoryCacheStore())));
    await tester.enterText(find.byType(TextField), 'frieren');
    // Past the 400 ms debounce.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final loading = find.byKey(const ValueKey('loading'));
    expect(find.descendant(of: loading, matching: find.byType(Skeleton)), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    response.complete(jsonResponse({
      'data': {
        'Page': {
          'media': [
            {'id': 1, 'type': 'ANIME', 'format': 'TV', 'title': {'english': 'Frieren'}, 'episodes': 28},
          ],
        },
      },
    }));
    await tester.pumpAndSettle();

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
  });
}
