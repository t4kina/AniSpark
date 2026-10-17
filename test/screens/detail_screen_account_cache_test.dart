import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

void main() {
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
  });

  testWidgets('with a token but no account id, the logged-out cache is not used', (tester) async {
    // The profile fetch failed, so the account id is unknown. The logged-out
    // copy must not stand in for this account's list entry and favourite.
    await cache.write('anon:media:1', {
      'id': 1,
      'type': 'ANIME',
      'title': {'english': 'Cached for everyone'},
      'mediaListEntry': null,
      'isFavourite': false,
    });

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache, auth: FakeAuthService(fakeToken: 'tok')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Cached for everyone'), findsNothing);
    expect(find.text(loadErrorText), findsOneWidget, reason: 'offline, with nothing it may show');
    expect(offline.requests, 1);
  });

  testWidgets('logged out, the shared cached copy is shown', (tester) async {
    await cache.write('anon:media:1', {
      'id': 1,
      'type': 'ANIME',
      'title': {'english': 'Cached for everyone'},
    });

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));
    await tester.pump();
    await tester.pump();

    expect(find.text('Cached for everyone'), findsWidgets);
  });
}
