import 'dart:io';

import 'package:anispark/screens/home_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/discover_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/anime_card.dart';
import 'package:anispark/widgets/motion/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _show(int id, String title) => {
      'id': id,
      'title': {'english': title},
      'averageScore': 80,
    };

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  testWidgets('the lines between Discover\'s groups sit in the middle of equal gaps', (tester) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cache = ApiCache(MemoryCacheStore());
    final now = DateTime.now();
    await cache.write(ApiCache.userKey(7, DiscoverApi.weekCacheName(now)), [
      {
        'id': 1,
        'airingAt': now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
        'episode': 3,
        'media': {
          'id': 1,
          'isAdult': false,
          'title': {'english': 'This Week Show'},
          'coverImage': {'large': null},
          'mediaListEntry': {'status': 'CURRENT'},
        },
      },
    ]);
    await cache.write('discover:trending', [_show(2, 'Trending Show')]);
    await cache.write('discover:topAiring', [_show(3, 'Top Airing Show')]);
    await cache.write('discover:trendingManga', [_show(4, 'Trending Manga')]);
    final discover = DiscoverApi(
      service: AniListService(client: mockAniList([], (_) => jsonResponse({}, status: 500))),
    );

    await tester.pumpWidget(appWith(
      HomeScreen(discover: discover),
      cache: cache,
      auth: FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7}),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    final lines = find.byType(Divider);
    expect(lines, findsNWidgets(2), reason: 'after This week and after the anime rows');
    double bottomOf(Finder finder) => tester.getBottomLeft(finder).dy;
    double topOf(Finder finder) => tester.getTopLeft(finder).dy;
    double lineAt(int i) => tester.getCenter(lines.at(i)).dy;

    final weekCard = find.ancestor(of: find.text('This Week Show'), matching: find.byType(Pressable)).first;
    final aboveFirst = lineAt(0) - bottomOf(weekCard);
    final belowFirst = topOf(find.text(_en('trending'))) - lineAt(0);

    final topAiringCard = find.ancestor(of: find.text('Top Airing Show'), matching: find.byType(AnimeCard));
    final aboveSecond = lineAt(1) - bottomOf(topAiringCard);
    final belowSecond = topOf(find.text(_en('home_trending_manga'))) - lineAt(1);

    final gaps = 'above/below: $aboveFirst/$belowFirst, $aboveSecond/$belowSecond';
    expect(aboveFirst, closeTo(belowFirst, 1), reason: gaps);
    expect(aboveSecond, closeTo(belowSecond, 1), reason: gaps);
    expect(aboveFirst, closeTo(aboveSecond, 1), reason: 'both lines alike: $gaps');
  });
}
