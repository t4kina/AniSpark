import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/affinity_api.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/affinity.dart';
import 'package:anispark/widgets/profile/affinity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

const _viewerId = 1;
const _otherId = 7;

void main() {
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
    AffinityApi.clearViewerMemo();
  });

  Future<void> cacheProfile(int userId) => cache.write(ApiCache.userKey(_viewerId, 'profile:$userId'), {
        'id': userId,
        'name': 'Faye Valentine',
        'isFollowing': false,
        'isFollower': false,
      });

  Future<void> pumpProfile(WidgetTester tester, int userId) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      UserProfileScreen(userId: userId, name: 'faye'),
      cache: cache,
      auth: FakeAuthService(fakeToken: 'tok', fakeUser: {'id': _viewerId}),
    ));
    // The profile loads from a post-frame callback, the card after it shows.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('shows the affinity under the stats of another user\'s profile', (tester) async {
    await cacheProfile(_otherId);
    final shared = sharedTitles(
      [for (var i = 1; i <= 12; i++) AffinityEntry(mediaId: i, score: i * 8.0, title: {'english': 'Show $i'})],
      [for (var i = 1; i <= 12; i++) AffinityEntry(mediaId: i, score: i * 8.0)],
    );
    await cache.write(ApiCache.userKey(_viewerId, 'affinity:$_otherId:ANIME'), shared);
    await cache.write(ApiCache.userKey(_viewerId, 'affinity:$_otherId:MANGA'), <SharedTitle>[]);

    await pumpProfile(tester, _otherId);

    expect(find.text('Faye Valentine'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(offline.requests, 2, reason: 'profile and activity only; the comparison is fresh in the cache');
  });

  testWidgets('keeps the profile working when the affinity can\'t load', (tester) async {
    await cacheProfile(_otherId);

    await pumpProfile(tester, _otherId);

    expect(find.text('Faye Valentine'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget, reason: 'one quiet retry for both media types');
    expect(find.byType(FilledButton), findsNothing, reason: 'the page itself shows no error view');
  });

  testWidgets('shows no affinity on the viewer\'s own profile', (tester) async {
    await cacheProfile(_viewerId);

    await pumpProfile(tester, _viewerId);

    expect(find.text('Faye Valentine'), findsOneWidget);
    expect(find.descendant(of: find.byType(AffinityCard), matching: find.byType(Text)), findsNothing);
    expect(offline.requests, 2);
  });
}
