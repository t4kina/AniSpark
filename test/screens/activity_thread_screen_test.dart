import 'dart:async';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/activity_thread_screen.dart';
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

// No avatar or cover URLs, so no image is fetched during the tests.
Map<String, dynamic> _user(int id) => {'id': id, 'name': 'user$id', 'avatar': null};

int _minutesAgo(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _threadResponse({List<Map<String, dynamic>>? replies}) => {
      'data': {
        'Activity': {
          'id': 9,
          'type': 'TEXT',
          'text': 'Hello __world__ ~!secret!~',
          'createdAt': _minutesAgo(5),
          'isLiked': false,
          'likeCount': 1,
          'replyCount': 1,
          'isLocked': false,
          'user': _user(2),
        },
        'Page': {
          'pageInfo': {'hasNextPage': false},
          'activityReplies': replies ??
              [
                {
                  'id': 100,
                  'text': 'First<br>reply',
                  'createdAt': _minutesAgo(3),
                  'isLiked': false,
                  'likeCount': 4,
                  'user': _user(3),
                },
              ],
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

  Future<void> pumpThread(
    WidgetTester tester,
    FutureOr<http.Response> Function(RecordedRequest request) handler, {
    ValueChanged<Map<String, dynamic>>? onActivityChanged,
  }) async {
    // Like mockAniList, but answers may be held back to observe the
    // optimistic state.
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
      child: MaterialApp(
        home: ActivityThreadScreen(activityId: 9, api: api, onActivityChanged: onActivityChanged),
      ),
    ));
    // The thread loads from a post-frame callback.
    await tester.pump();
    await tester.pump();
  }

  bool isMutation(RecordedRequest request, String name) => request.query.contains(name);

  testWidgets('shows the activity and its replies as plain text', (tester) async {
    await pumpThread(tester, (_) => jsonResponse(_threadResponse()));

    expect(log.single.variables['id'], 9);
    expect(find.textContaining('Hello world'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('First\nreply'), findsOneWidget);
    expect(find.text('user3'), findsOneWidget);
    expect(find.text('3m ago'), findsOneWidget);
  });

  testWidgets('likes a reply optimistically, then reverts and says so when it fails', (tester) async {
    final likeResponse = Completer<http.Response>();
    await pumpThread(tester, (request) {
      if (isMutation(request, 'ToggleLikeV2')) return likeResponse.future;
      return jsonResponse(_threadResponse());
    });

    // The reply's like button shows its count (the activity's shows 1).
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.text('5'), findsOneWidget, reason: 'optimistic like');

    likeResponse.complete(jsonResponse({'errors': []}, status: 500));
    await tester.pump();
    await tester.pump();

    final likeRequest = log.firstWhere((r) => isMutation(r, 'ToggleLikeV2'));
    expect(likeRequest.variables, {'id': 100, 'type': 'ACTIVITY_REPLY'});
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsNothing);
    expect(find.text("Couldn't save. Please try again."), findsOneWidget);
  });

  testWidgets('keeps a confirmed like and reports it to the opener', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await pumpThread(
      tester,
      (request) {
        if (isMutation(request, 'ToggleLikeV2')) {
          return jsonResponse({
            'data': {
              'ToggleLikeV2': {'id': 9, 'isLiked': true, 'likeCount': 2},
            },
          });
        }
        return jsonResponse(_threadResponse());
      },
      onActivityChanged: changes.add,
    );

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(changes.last['isLiked'], isTrue);
    expect(changes.last['likeCount'], 2);
  });

  testWidgets('sends a reply, shows it and bumps the reply count', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await pumpThread(
      tester,
      (request) {
        if (isMutation(request, 'SaveActivityReply')) {
          return jsonResponse({
            'data': {
              'SaveActivityReply': {
                'id': 101,
                'activityId': 9,
                'text': 'My **reply**',
                'createdAt': _minutesAgo(0),
                'isLiked': false,
                'likeCount': 0,
                'user': _user(1),
              },
            },
          });
        }
        return jsonResponse(_threadResponse());
      },
      onActivityChanged: changes.add,
    );

    await tester.enterText(find.byType(TextField), '  My **reply**  ');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();

    final sent = log.firstWhere((r) => isMutation(r, 'SaveActivityReply'));
    expect(sent.variables, {'activityId': 9, 'text': 'My **reply**'});
    expect(find.textContaining('My reply'), findsOneWidget);
    expect(changes.last['replyCount'], 2);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('keeps the text when sending a reply fails', (tester) async {
    await pumpThread(tester, (request) {
      if (isMutation(request, 'SaveActivityReply')) return jsonResponse({'errors': []}, status: 500);
      return jsonResponse(_threadResponse(replies: []));
    });

    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't save. Please try again."), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Draft');
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    await pumpThread(tester, (_) => jsonResponse({'errors': []}, status: 500));

    expect(find.text("Couldn't load the content"), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(log, hasLength(2));
  });

  testWidgets('shows a deleted activity as gone, without retry or reply field', (tester) async {
    await pumpThread(
      tester,
      (_) => jsonResponse({
        'errors': [
          {'message': 'Not Found.', 'status': 404},
        ],
        'data': {'Activity': null, 'Page': null},
      }, status: 404),
    );

    expect(find.byIcon(Icons.speaker_notes_off_outlined), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows the cached thread right away while refreshing', (tester) async {
    await cache.write(ApiCache.userKey(1, 'thread:9'), {
      'activity': {
        'id': 9,
        'type': 'TEXT',
        'text': 'Cached post',
        'createdAt': _minutesAgo(5),
        'user': _user(2),
      },
      'replies': <Object>[],
      'hasNextPage': false,
      'page': 1,
    });

    await pumpThread(tester, (_) => throw http.ClientException('offline'));

    expect(find.textContaining('Cached post'), findsOneWidget);
    expect(find.text("Couldn't load the content"), findsOneWidget, reason: 'inline refresh error');
  });
}
