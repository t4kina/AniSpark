import 'dart:async';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/feed_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/social_api.dart';
import 'package:anispark/utils/tab_reselect.dart';
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
        return jsonResponse(_feedPage([for (var i = 1; i <= 12; i++) _textActivity(i)], hasNextPage: true));
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
}
