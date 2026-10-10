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
import 'package:provider/provider.dart';

import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

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

  Future<void> pumpInbox(WidgetTester tester, http.Response Function(RecordedRequest request) handler) async {
    final api = SocialApi(service: AniListService(client: mockAniList(log, handler)));
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
}
