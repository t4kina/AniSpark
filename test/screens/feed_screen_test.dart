import 'dart:async';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/feed_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/social_api.dart';
import 'package:anispark/utils/tab_reselect.dart';
import 'package:anispark/widgets/social/feed_timeline_item.dart';
import 'package:anispark/widgets/social/social_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/mock_anilist.dart' show RecordedRequest, jsonResponse;

class _LoggedInAuth extends AuthService {
  @override
  String? get token => 'test-token';

  @override
  Map<String, dynamic>? get user => const {'id': 1, 'name': 'me'};

  @override
  bool get isLoggedIn => true;
}

Map<String, dynamic> _textActivity(int id) => {
      'id': id,
      'type': 'TEXT',
      'text': 'post $id',
      'createdAt': 1700000000 + id,
      'isLiked': false,
      'likeCount': 0,
      'replyCount': 0,
      'user': {'id': id, 'name': 'user$id', 'avatar': null},
    };

Map<String, dynamic> _feedPage(List<Map<String, dynamic>> activities, {bool hasNextPage = false}) => {
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'activities': activities,
        },
      },
    };

void main() {
  late List<RecordedRequest> log;

  setUp(() => log = []);

  Future<void> pumpFeed(
    WidgetTester tester,
    FutureOr<http.Response> Function(RecordedRequest request) handler,
  ) async {
    final client = MockClient((request) async {
      final recorded = RecordedRequest(request);
      log.add(recorded);
      return handler(recorded);
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => _LoggedInAuth()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: FeedScreen(api: SocialApi(service: AniListService(client: client)))),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    // The skeleton cross-fades into the cards.
    await tester.pumpAndSettle();
  }

  bool isFeedPage(RecordedRequest r, int page) => r.variables['page'] == page && r.query.contains('activities');

  testWidgets('stops loading more after a failed page and retries only on tap', (tester) async {
    var page2Attempts = 0;
    await pumpFeed(tester, (request) {
      if (isFeedPage(request, 1)) {
        // Enough entries to push the load-more footer below the screen.
        return jsonResponse(_feedPage([for (var i = 1; i <= 24; i++) _textActivity(i)], hasNextPage: true));
      }
      if (isFeedPage(request, 2)) {
        page2Attempts++;
        return jsonResponse({'errors': []}, status: 500);
      }
      return jsonResponse({'data': {'Viewer': {'id': 1, 'unreadNotificationCount': 0}}});
    });

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pump();
    await tester.pump();
    expect(page2Attempts, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pump();
    expect(page2Attempts, 1, reason: 'no automatic retry while failed');
    expect(find.byKey(const Key('load-more-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('load-more-retry')));
    await tester.pump();
    await tester.pump();
    expect(page2Attempts, 2);
  });

  testWidgets('shows an unknown list status as AniList sent it', (tester) async {
    await pumpFeed(tester, (request) {
      if (isFeedPage(request, 1)) {
        return jsonResponse(_feedPage([
          {
            'id': 7,
            'type': 'ANIME_LIST',
            'status': 'did a backflip',
            'progress': null,
            'createdAt': 1700000000,
            'isLiked': false,
            'likeCount': 0,
            'replyCount': 0,
            'user': {'id': 2, 'name': 'bob', 'avatar': null},
            'media': {'id': 5, 'type': 'ANIME', 'title': {'romaji': 'Show'}, 'coverImage': null},
          },
        ]));
      }
      return jsonResponse({'data': {'Viewer': {'id': 1, 'unreadNotificationCount': 0}}});
    });

    expect(find.textContaining('did a backflip', findRichText: true), findsOneWidget);
  });

  Future<void> pumpLongFeed(WidgetTester tester, {Map<String, dynamic>? posted}) => pumpFeed(tester, (request) {
        if (isFeedPage(request, 1)) {
          return jsonResponse(_feedPage([for (var i = 1; i <= 30; i++) _textActivity(i)]));
        }
        if (posted != null && request.query.contains('SaveTextActivity')) {
          return jsonResponse({'data': {'SaveTextActivity': posted}});
        }
        return jsonResponse({'data': {'Viewer': {'id': 1, 'unreadNotificationCount': 0}}});
      });

  double feedOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)))
      .position
      .pixels;

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<FadeTransition>(find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  testWidgets('re-selecting the feed tab scrolls it back to the top', (tester) async {
    await pumpLongFeed(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    final scrolled = feedOffset(tester);
    expect(scrolled, greaterThan(0));

    // The profile tab's reselection leaves the feed alone.
    tabReselectedNotifier.reselect(4);
    await tester.pumpAndSettle();
    expect(feedOffset(tester), scrolled);

    tabReselectedNotifier.reselect(3);
    await tester.pumpAndSettle();
    expect(feedOffset(tester), 0);
  });

  testWidgets('a posted status fades in at the top while the other cards stay put', (tester) async {
    await pumpLongFeed(tester, posted: _textActivity(99));
    expect(opacityOf(tester, 'post 1'), 1);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'post 99');
    await tester.pump();
    await tester.tap(find.text('Post'));
    final card = find.descendant(of: find.byType(ListView), matching: find.text('post 99'));
    for (var i = 0; i < 30 && card.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(card, findsOneWidget);
    expect(
      tester.widget<FadeTransition>(find.ancestor(of: card, matching: find.byType(FadeTransition)).first).opacity.value,
      lessThan(1),
      reason: 'the new card is still fading in',
    );
    expect(opacityOf(tester, 'post 1'), 1, reason: "cards already shown don't replay their entrance");

    await tester.pumpAndSettle();
    expect(
      tester.widget<FadeTransition>(find.ancestor(of: card, matching: find.byType(FadeTransition)).first).opacity.value,
      1,
    );
    expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(find.text('post 1')).dy));
  });

  testWidgets('the post button waits until something is written', (tester) async {
    var posts = 0;
    await pumpFeed(tester, (request) {
      if (isFeedPage(request, 1)) return jsonResponse(_feedPage([_textActivity(1)]));
      if (request.query.contains('SaveTextActivity')) {
        posts++;
        return jsonResponse({'data': {'SaveTextActivity': _textActivity(99)}});
      }
      return jsonResponse({'data': {'Viewer': {'id': 1, 'unreadNotificationCount': 0}}});
    });
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(find.byType(TextField), findsOneWidget, reason: 'the composer is still open');

    await tester.enterText(find.byType(TextField), 'post 99');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(posts, 1);
  });

  group('the timeline', () {
    int secondsAgo(Duration ago) => DateTime.now().subtract(ago).millisecondsSinceEpoch ~/ 1000;

    Map<String, dynamic> listActivity(int id, int createdAt) => {
          'id': id,
          'type': 'ANIME_LIST',
          'status': 'watched episode',
          'progress': '5',
          'createdAt': createdAt,
          'isLiked': false,
          'likeCount': 4,
          'replyCount': 1,
          'user': {'id': 2, 'name': 'faye', 'avatar': null},
          'media': {
            'id': 5,
            'type': 'ANIME',
            'title': {'romaji': 'Frieren'},
            'coverImage': {'large': 'https://img.example/frieren.jpg'},
          },
        };

    Future<void> pumpTimeline(WidgetTester tester, List<Map<String, dynamic>> activities) => pumpFeed(tester, (request) {
          if (isFeedPage(request, 1)) return jsonResponse(_feedPage(activities));
          return jsonResponse({'data': {'Viewer': {'id': 1, 'unreadNotificationCount': 0}}});
        });

    testWidgets('groups what happened under the day it happened, each day named once', (tester) async {
      final today = DateTime.now();
      final noon = DateTime(today.year, today.month, today.day, 12);
      int at(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
      await pumpTimeline(tester, [
        {..._textActivity(1), 'createdAt': at(noon)},
        {..._textActivity(2), 'createdAt': at(noon.subtract(const Duration(days: 1)))},
        {..._textActivity(3), 'createdAt': at(noon.subtract(const Duration(days: 1, hours: 2)))},
        {..._textActivity(4), 'createdAt': at(noon.subtract(const Duration(days: 400)))},
      ]);

      expect(find.byType(FeedTimelineItem), findsNWidgets(4));
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget, reason: 'two posts, one heading');
      final labels = [
        for (final item in tester.widgetList<FeedTimelineItem>(find.byType(FeedTimelineItem))) item.dayLabel,
      ];
      expect(labels[2], isNull);
      expect(labels[3], contains('${noon.subtract(const Duration(days: 400)).year}'), reason: 'another year is dated in full');
      expect(tester.getTopLeft(find.text('TODAY')).dy, lessThan(tester.getTopLeft(find.text('post 1')).dy));
    });

    testWidgets('a list entry says who did what, to what, with its cover and no card around it', (tester) async {
      await pumpTimeline(tester, [listActivity(7, secondsAgo(const Duration(hours: 2)))]);

      final entry = find.byType(FeedTimelineItem);
      expect(find.descendant(of: entry, matching: find.textContaining('faye', findRichText: true)), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.textContaining('watched episode', findRichText: true)), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('Frieren')), findsOneWidget);
      final cover = find.descendant(of: entry, matching: find.byType(CachedNetworkImage));
      expect(tester.getSize(cover.last), FeedTimelineItem.coverSize);
      expect(tester.getTopLeft(cover.last).dx, greaterThan(tester.getTopRight(find.text('Frieren')).dx),
          reason: 'the cover closes the row, at the right');
      expect(
        find.descendant(
          of: entry,
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && (widget.decoration as BoxDecoration?)?.borderRadius != null,
          ),
        ),
        findsNothing,
        reason: 'entries hang from the line, they are not rounded cards',
      );
    });

    testWidgets('likes and replies are still a tap away on each entry', (tester) async {
      await pumpTimeline(tester, [listActivity(7, secondsAgo(const Duration(hours: 2)))]);

      expect(find.descendant(of: find.byType(LikeButton), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.byType(ReplyCountButton), matching: find.text('1')), findsOneWidget);

      await tester.tap(find.byType(LikeButton));
      await tester.pump();
      expect(log.any((request) => request.query.contains('ToggleLike')), isTrue);
      await tester.pumpAndSettle();
    });
  });
}
