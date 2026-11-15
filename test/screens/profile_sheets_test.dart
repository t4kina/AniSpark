import 'dart:io';

import 'package:anispark/screens/profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

/// Logged in, following a few people, with a fresh cached profile.
class _FollowingAuth extends FakeAuthService {
  _FollowingAuth({this.count = 3}) : super(fakeToken: 'token', fakeUser: {'id': 7, 'name': 'Faye'});

  final int count;

  @override
  Map<String, dynamic>? get profileExtras => {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'favoriteAnime': const [],
        'favoriteCharacters': const [],
        'followersCount': 0,
        'followingCount': count,
        'activityDays': const <String, dynamic>{},
        'following': [
          for (var i = 1; i <= count; i++)
            {'id': i, 'name': 'Friend $i', 'avatar': null},
        ],
      };
}

void main() {
  // The followers are asked for with the shared client; keep it off the network.
  final offline = OfflineHttpOverrides();

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() => offline.requests = 0);

  testWidgets('dragging the people up scrolls them inside the sheet, which stays put', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3 Following'));
    await tester.pumpAndSettle();
    final title = find.text('Following');
    final top = tester.getTopLeft(title).dy;
    expect(top, greaterThan(47), reason: 'well clear of the status bar');

    // Like the Sort sheet: the list bounces, the sheet doesn't grow.
    final gesture = await tester.startGesture(tester.getCenter(find.text('Friend 1')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getTopLeft(title).dy, top, reason: 'held up, the sheet stays where it was');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, top);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a long list keeps the sheet to most of the screen and scrolls inside it', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth(count: 30)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('30 Following'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(tester.getTopLeft(find.text('Following')).dy, greaterThanOrEqualTo(900 * 0.3),
        reason: 'the sheet is at most 70% of the screen tall');
    expect(find.text('Friend 30'), findsNothing);

    await tester.scrollUntilVisible(find.text('Friend 30'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Friend 30'), findsOneWidget);
  });

  testWidgets('followers that could not be loaded say so, with a retry', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: ApiCache(MemoryCacheStore()), auth: _FollowingAuth()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0 Followers'));
    await tester.pumpAndSettle();

    expect(find.text(loadErrorText), findsOneWidget);
    expect(find.text('Nobody here yet'), findsNothing, reason: 'not knowing is not the same as nobody');
    expect(offline.requests, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(offline.requests, 2);
    expect(find.text(loadErrorText), findsOneWidget);
  });
}
