import 'dart:async';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/feed_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/social_api.dart';
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
}
