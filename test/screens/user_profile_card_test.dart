import 'dart:io';

import 'package:anispark/screens/user_profile_screen.dart';
import 'package:anispark/services/affinity_api.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

const _viewerId = 1;
const _otherId = 7;

void main() {
  // The affinity card uses the shared client; keep it off the network.
  final offline = OfflineHttpOverrides();
  late ApiCache cache;
  late List<RecordedRequest> log;
  // What AniList holds.
  var following = false;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
    following = false;
    AffinityApi.clearViewerMemo();
  });

  AniListService aniList({required bool isFollower}) => AniListService(
        client: mockAniList(log, (request) {
          if (request.query.contains('ToggleFollow')) {
            following = !following;
            return jsonResponse({
              'data': {
                'ToggleFollow': {'id': _otherId, 'isFollowing': following},
              },
            });
          }
          if (request.query.contains('activities')) {
            return jsonResponse({
              'data': {
                'Page': {'activities': []},
              },
            });
          }
          return jsonResponse({
            'data': {
              'User': {'id': _otherId, 'name': 'Faye Valentine', 'isFollowing': following, 'isFollower': isFollower},
            },
          });
        }),
      );

  Future<void> pumpProfile(WidgetTester tester, {int userId = _otherId, bool isFollower = false}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      UserProfileScreen(userId: userId, name: 'faye', service: aniList(isFollower: isFollower)),
      cache: cache,
      auth: FakeAuthService(fakeToken: 'tok', fakeUser: {'id': _viewerId}),
    ));
    // The profile loads from a post-frame callback.
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  int toggles() => log.where((request) => request.query.contains('ToggleFollow')).length;

  testWidgets('another user\'s profile offers Follow, which follows them', (tester) async {
    await pumpProfile(tester);
    expect(find.text('Faye Valentine'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();

    expect(toggles(), 1);
    expect(following, isTrue);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);
  });

  testWidgets('when following, the button offers Unfollow beside Block and Report', (tester) async {
    following = true;
    await pumpProfile(tester, isFollower: true);
    expect(find.text('Follows You'), findsOneWidget);

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.text('Unfollow'));
    await tester.pumpAndSettle();

    expect(toggles(), 1);
    expect(following, isFalse);
    expect(find.text('Follow'), findsOneWidget);
  });

  testWidgets('the more button offers Block and Report, not Unfollow, when not following', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Unfollow'), findsNothing);
  });

  testWidgets('the viewer\'s own profile has no follow actions', (tester) async {
    await pumpProfile(tester, userId: _viewerId);

    expect(find.text('Faye Valentine'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);
    expect(find.byTooltip('More options'), findsNothing);
  });
}
