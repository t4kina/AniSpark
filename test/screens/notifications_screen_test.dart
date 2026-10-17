import 'dart:async';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/widgets/social/social_widgets.dart' show ProfileAvatar;
import 'package:anispark/screens/notifications_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart' show RecordedRequest, jsonResponse;

class _LoggedInAuth extends AuthService {
  @override
  String? get token => 'test-token';

  @override
  Map<String, dynamic>? get user => const {'id': 1, 'name': 'me'};

  @override
  bool get isLoggedIn => true;
}

int _minutesAgo(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 1000;

// No avatar or cover URLs, so no image is fetched during the tests.
Map<String, dynamic> _user(int id) => {'id': id, 'name': 'user$id', 'avatar': null};

Map<String, dynamic> _media(int id) => {
      'id': id,
      'type': 'ANIME',
      'title': {'romaji': 'Show $id'},
      'coverImage': null,
    };

Map<String, dynamic> _page(List<Object> notifications, {bool hasNextPage = false}) => {
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': hasNextPage},
          'notifications': notifications,
        },
      },
    };

void main() {
  late List<RecordedRequest> log;
  late ApiCache cache;

  setUp(() {
    log = [];
    cache = ApiCache(MemoryCacheStore());
  });

  Future<void> pumpInbox(WidgetTester tester, FutureOr<http.Response> Function(RecordedRequest request) handler) async {
    final client = MockClient((request) async {
      final recorded = RecordedRequest(request);
      log.add(recorded);
      return handler(recorded);
    });
    final api = SocialApi(service: AniListService(client: client));
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>(create: (_) => _LoggedInAuth()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: NotificationsScreen(api: api)),
    ));
    // The inbox loads from a post-frame callback.
    await tester.pump();
    await tester.pump();
    // The skeleton cross-fades into the loaded state.
    await tester.pumpAndSettle();
  }

  testWidgets('loads the first page marking it read and shows supported kinds', (tester) async {
    await pumpInbox(
      tester,
      (_) => jsonResponse(_page([
        {'id': 1, 'type': 'FOLLOWING', 'createdAt': _minutesAgo(1), 'user': _user(5)},
        {'id': 2, 'type': 'AIRING', 'createdAt': _minutesAgo(2), 'episode': 3, 'media': _media(7)},
        {'id': 3, 'type': 'THREAD_LIKE', 'createdAt': _minutesAgo(3)},
        {'id': 4, 'type': 'ACTIVITY_LIKE', 'createdAt': _minutesAgo(4), 'activityId': 9, 'user': _user(6)},
        {'id': 5, 'type': 'MEDIA_DELETION', 'createdAt': _minutesAgo(5), 'deletedMediaTitle': 'Gone'},
      ])),
    );

    expect(log.single.variables, {'page': 1, 'perPage': SocialApi.notificationsPerPage, 'reset': true});
    expect(find.text('1m ago'), findsOneWidget);
    expect(find.text('2m ago'), findsOneWidget);
    expect(find.text('3m ago'), findsNothing, reason: 'forum notifications are skipped');
    expect(find.text('4m ago'), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);
    expect(find.byType(ProfileAvatar), findsNWidgets(2));
  });

  testWidgets('fetches through pages that only hold skipped kinds', (tester) async {
    await pumpInbox(tester, (request) {
      final page = request.variables['page'] as int;
      if (page == 1) {
        return jsonResponse(_page([
          {'id': 1, 'type': 'THREAD_COMMENT_REPLY'},
        ], hasNextPage: true));
      }
      return jsonResponse(_page([
        {'id': 2, 'type': 'FOLLOWING', 'createdAt': _minutesAgo(8), 'user': _user(5)},
      ]));
    });
    await tester.pump();

    expect(log.map((r) => (r.variables['page'], r.variables['reset'])), [(1, true), (2, false)]);
    expect(find.text('8m ago'), findsOneWidget);
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    await pumpInbox(tester, (_) => jsonResponse({'errors': []}, status: 500));

    expect(find.text("Couldn't load the content"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(log, hasLength(2));
  });

  testWidgets('shows cached notifications when the refresh fails', (tester) async {
    await cache.write(ApiCache.userKey(1, 'inbox'), {
      'items': [
        {'id': 1, 'type': 'FOLLOWING', 'createdAt': _minutesAgo(6), 'user': _user(5)},
      ],
      'hasNextPage': false,
      'page': 1,
    });

    await pumpInbox(tester, (_) => throw http.ClientException('offline'));

    expect(find.text('6m ago'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text("Couldn't load the content"), findsOneWidget, reason: 'snack bar');
  });

  List<Object> following(int from, int count) => [
        for (var i = from; i < from + count; i++)
          {'id': i, 'type': 'FOLLOWING', 'createdAt': _minutesAgo(i), 'user': _user(i)},
      ];

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('stops loading more after a failed page and retries only on tap', (tester) async {
    var page2Attempts = 0;
    await pumpInbox(tester, (request) {
      if (request.variables['page'] == 1) {
        return jsonResponse(_page(following(1, 15), hasNextPage: true));
      }
      page2Attempts++;
      return jsonResponse({'errors': []}, status: 500);
    });

    await scrollToEnd(tester);
    expect(page2Attempts, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -50));
    await tester.drag(find.byType(ListView), const Offset(0, -50));
    await tester.pump();
    expect(page2Attempts, 1, reason: 'no automatic retry while failed');
    expect(find.byKey(const Key('load-more-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('load-more-retry')));
    await tester.pump();
    await tester.pump();
    expect(page2Attempts, 2);
  });

  testWidgets('offers a load more button when fetched pages added nothing', (tester) async {
    var loadMoreRequests = 0;
    await pumpInbox(tester, (request) {
      final page = request.variables['page'] as int;
      if (page <= 3) {
        return jsonResponse(_page([
          {'id': page, 'type': 'THREAD_COMMENT_REPLY'},
        ], hasNextPage: true));
      }
      loadMoreRequests++;
      return jsonResponse(_page(following(50, 1)));
    });
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('load-more-button')), findsOneWidget);
    expect(loadMoreRequests, 0);

    await tester.tap(find.byKey(const Key('load-more-button')));
    await tester.pump();
    await tester.pump();
    expect(loadMoreRequests, 1);
    expect(find.text('50m ago'), findsOneWidget);
  });

  testWidgets('drops a load-more page that finishes after a refresh', (tester) async {
    final page2 = Completer<http.Response>();
    var firstLoads = 0;
    var page2Requested = 0;
    await pumpInbox(tester, (request) {
      if (request.variables['page'] == 1) {
        firstLoads++;
        return jsonResponse(_page(firstLoads == 1 ? following(1, 15) : following(100, 15), hasNextPage: true));
      }
      // Only the first page-2 request is the stale one held back.
      return page2Requested++ == 0 ? page2.future : jsonResponse(_page(const []));
    });

    await scrollToEnd(tester);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(firstLoads, 2);

    page2.complete(jsonResponse(_page([
      {'id': 500, 'type': 'FOLLOWING', 'createdAt': _minutesAgo(45), 'user': _user(500)},
    ])));
    await tester.pump();
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    expect(find.text('45m ago'), findsNothing);
  });
}
