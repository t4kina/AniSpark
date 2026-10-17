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

/// Starts logged in as user 1; [logOut] drops the session like a 401 would.
class _SessionAuth extends AuthService {
  _SessionAuth({this.userId = 1});

  final int? userId;
  bool _out = false;

  @override
  String? get token => _out ? null : 'test-token';

  @override
  Map<String, dynamic>? get user => _out || userId == null ? null : {'id': userId, 'name': 'me'};

  @override
  bool get isLoggedIn => !_out;

  void logOut() {
    _out = true;
    notifyListeners();
  }
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
  late MemoryCacheStore store;

  setUp(() {
    log = [];
    store = MemoryCacheStore();
    cache = ApiCache(store);
  });

  Future<void> pumpThread(
    WidgetTester tester,
    FutureOr<http.Response> Function(RecordedRequest request) handler, {
    ValueChanged<Map<String, dynamic>>? onActivityChanged,
    AuthService? auth,
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
        ChangeNotifierProvider<AuthService>(create: (_) => auth ?? _LoggedInAuth()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: ActivityThreadScreen(activityId: 9, api: api, onActivityChanged: onActivityChanged),
      ),
    ));
    // The thread loads from a post-frame callback.
    await tester.pump();
    await tester.pump();
    // The skeleton cross-fades into the thread.
    await tester.pumpAndSettle();
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
    // The count rolls back; let the outgoing numbers finish leaving.
    await tester.pumpAndSettle();

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

  testWidgets('a sent reply fades in while the replies already shown stay put', (tester) async {
    await pumpThread(tester, (request) {
      if (isMutation(request, 'SaveActivityReply')) {
        return jsonResponse({
          'data': {
            'SaveActivityReply': {
              'id': 101,
              'text': 'Brand new',
              'createdAt': _minutesAgo(0),
              'isLiked': false,
              'likeCount': 0,
              'user': _user(1),
            },
          },
        });
      }
      return jsonResponse(_threadResponse());
    });
    double opacityOf(Finder text) => tester
        .widget<FadeTransition>(find.ancestor(of: text, matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    await tester.enterText(find.byType(TextField), 'Brand new');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(opacityOf(find.textContaining('Brand new')), lessThan(1), reason: 'still fading in');
    expect(opacityOf(find.textContaining('First\nreply')), 1);
    await tester.pumpAndSettle();
    expect(opacityOf(find.textContaining('Brand new')), 1);
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

  Iterable<String> cachedThreadKeys() => store.keys.where((key) => key.contains('thread:'));

  testWidgets('does not cache a thread when the viewer is unknown despite a token', (tester) async {
    await pumpThread(tester, (_) => jsonResponse(_threadResponse()), auth: _SessionAuth(userId: null));

    expect(find.textContaining('Hello world'), findsOneWidget);
    expect(cachedThreadKeys(), isEmpty, reason: 'viewer-specific data must not land under a shared key');
  });

  testWidgets('does not write the thread to the cache when a like finishes after logout', (tester) async {
    final auth = _SessionAuth();
    final likeResponse = Completer<http.Response>();
    await pumpThread(tester, (request) {
      if (isMutation(request, 'ToggleLikeV2')) return likeResponse.future;
      return jsonResponse(_threadResponse());
    }, auth: auth);
    await store.clear();

    await tester.tap(find.text('4'));
    await tester.pump();
    auth.logOut();
    await tester.pump();
    likeResponse.complete(jsonResponse({
      'data': {
        'ToggleLikeV2': {'id': 100, 'isLiked': true, 'likeCount': 5},
      },
    }));
    await tester.pump();
    await tester.pump();

    expect(cachedThreadKeys(), isEmpty);
  });

  testWidgets('stops loading more replies after a failure and retries only on tap', (tester) async {
    var page2Attempts = 0;
    Map<String, dynamic> manyReplies() {
      final response = _threadResponse(replies: [
        for (var i = 1; i <= 14; i++)
          {
            'id': i,
            'text': 'reply $i',
            'createdAt': _minutesAgo(i),
            'isLiked': false,
            'likeCount': 0,
            'user': _user(3),
          },
      ]);
      ((response['data'] as Map)['Page'] as Map)['pageInfo'] = {'hasNextPage': true};
      return response;
    }

    await pumpThread(tester, (request) {
      if (request.variables['page'] == 2) {
        page2Attempts++;
        return jsonResponse({'errors': []}, status: 500);
      }
      return jsonResponse(manyReplies());
    });

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pump();
    await tester.pump();
    expect(page2Attempts, 1);

    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.drag(find.byType(ListView), const Offset(0, -60));
    await tester.pump();
    expect(page2Attempts, 1, reason: 'no automatic retry while failed');

    await tester.tap(find.byKey(const Key('load-more-retry')));
    await tester.pump();
    await tester.pump();
    expect(page2Attempts, 2);
  });
}
