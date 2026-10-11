import 'dart:io';

import 'package:anispark/screens/home_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/discover_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

Map<String, dynamic> _airing(int id, String title, DateTime time, String status) => {
      'id': id,
      'airingAt': time.millisecondsSinceEpoch ~/ 1000,
      'episode': 3,
      'media': {
        'id': id,
        'isAdult': false,
        'title': {'english': title},
        'coverImage': {'large': null},
        'mediaListEntry': {'status': status},
      },
    };

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  testWidgets("THIS WEEK reuses the calendar's cached week and filters to CURRENT",
      (tester) async {
    final cache = ApiCache(MemoryCacheStore());
    final now = DateTime.now();
    final soon = now.add(const Duration(minutes: 30));
    await cache.write(ApiCache.userKey(7, DiscoverApi.weekCacheName(now)), [
      _airing(1, 'Frieren', soon, 'CURRENT'),
      _airing(2, 'Dandadan', soon, 'PLANNING'),
      _airing(3, 'Aired Already', now.subtract(const Duration(hours: 1)), 'CURRENT'),
    ]);
    await cache.write('discover:trending', [
      {'id': 9, 'title': {'english': 'Cowboy Bebop'}, 'averageScore': 86},
    ]);
    final log = <RecordedRequest>[];
    final discover = DiscoverApi(
      service: AniListService(client: mockAniList(log, (_) => jsonResponse({}, status: 500))),
    );
    final auth = FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7});

    await tester.pumpWidget(appWith(HomeScreen(discover: discover), cache: cache, auth: auth));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Dandadan'), findsNothing, reason: 'only CURRENT');
    expect(find.text('Aired Already'), findsNothing);
    expect(log, isEmpty, reason: 'a fresh calendar week costs no request');
  });
}
