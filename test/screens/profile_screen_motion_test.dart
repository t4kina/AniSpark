import 'package:anispark/screens/profile_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/tab_reselect.dart';
import 'package:anispark/widgets/profile/count_up_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

const _profileTab = 4;

/// Logged in with stats and a fresh cached profile, so nothing is fetched.
class _ProfileAuth extends FakeAuthService {
  _ProfileAuth()
      : super(fakeToken: 'token', fakeUser: {
          'id': 7,
          'name': 'Faye',
          'statistics': {
            'anime': {'count': 321, 'episodesWatched': 4567, 'minutesWatched': 17856},
            'manga': {'count': 12, 'chaptersRead': 890, 'volumesRead': 34},
          },
        });

  @override
  Map<String, dynamic>? get profileExtras => {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'favoriteAnime': [
          for (var i = 1; i <= 3; i++)
            {
              'id': i,
              'title': {'english': 'Fav $i'},
              'coverImage': null,
            },
        ],
        'favoriteCharacters': const [],
        'followersCount': 5,
        'followingCount': 6,
        'activityDays': const <String, dynamic>{},
        'following': const [],
      };
}

void main() {
  late ApiCache cache;

  setUp(() => cache = ApiCache(MemoryCacheStore()));

  Future<void> pumpProfile(WidgetTester tester) async {
    // Wide enough for the follow buttons in the test font, short enough to scroll.
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(const ProfileScreen(), cache: cache, auth: _ProfileAuth()));
    // The cached profile is applied from a post-frame callback.
    await tester.pump();
  }

  testWidgets('the stats count up and end on the real values', (tester) async {
    await pumpProfile(tester);
    final episodes = find.byWidgetPredicate((w) => w is CountUpText && w.value == 4567);
    expect(episodes, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.widget<Text>(find.descendant(of: episodes, matching: find.byType(Text))).data!;
    expect(int.parse(midway), lessThan(4567), reason: 'still counting');

    await tester.pumpAndSettle();
    for (final value in ['321 anime', '12 manga', '4567', '12.4']) {
      expect(find.text(value), findsOneWidget, reason: value);
    }
  });

  testWidgets('re-selecting the profile tab scrolls it back to the top', (tester) async {
    await pumpProfile(tester);
    await tester.pumpAndSettle();
    final scrollable = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
    double offset() => tester.state<ScrollableState>(scrollable).position.pixels;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = offset();
    expect(scrolled, greaterThan(0));

    tabReselectedNotifier.reselect(3);
    await tester.pumpAndSettle();
    expect(offset(), scrolled, reason: 'the feed tab\'s reselection is not ours');

    tabReselectedNotifier.reselect(_profileTab);
    await tester.pumpAndSettle();
    expect(offset(), 0);
  });

  testWidgets('favourite covers fly with tags unique to the profile', (tester) async {
    await pumpProfile(tester);
    await tester.pumpAndSettle();

    final tags = tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag).toList();
    expect(tags, ['cover:profile-favs:1', 'cover:profile-favs:2', 'cover:profile-favs:3']);
  });
}
