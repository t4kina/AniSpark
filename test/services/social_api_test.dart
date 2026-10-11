import 'dart:io';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/social_api.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

const token = 'test-token';

Map<String, dynamic> user(int id) => {
      'id': id,
      'name': 'user$id',
      'avatar': {'large': 'https://img/u$id.png'},
    };

Map<String, dynamic> media(int id) => {
      'id': id,
      'type': 'ANIME',
      'title': {'romaji': 'Romaji $id', 'english': 'English $id', 'native': null},
      'coverImage': {'large': 'https://img/m$id.png'},
    };

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  SocialApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      SocialApi(service: AniListService(client: mockAniList(log, handler)));

  SocialApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  SocialApi apiThrowing(Exception error) => apiAnswering((_) => throw error);

  Map<String, dynamic> page(String field, List<Object> items, {bool hasNextPage = false}) => {
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': hasNextPage},
            field: items,
          },
        },
      };

  group('fetchFeed', () {
    test('requests the social fields and sends the feed variables', () async {
      final api = apiReturning(page('activities', []));

      await api.fetchFeed(token, isFollowing: false, page: 3);

      final request = log.single;
      expect(request.variables, {'isFollowing': false, 'page': 3, 'perPage': SocialApi.feedPerPage});
      expect(request.authorization, 'Bearer $token');
      expect(request.query, contains('isLiked likeCount replyCount'));
      expect(request.query, contains('text(asHtml: false)'));
      expect(request.query, isNot(contains('\$userId')));
    });

    test('filters by user only when a userId is given', () async {
      final api = apiReturning(page('activities', []));

      await api.fetchFeed(token, userId: 42);

      expect(log.single.variables['userId'], 42);
      expect(log.single.query, contains('userId: \$userId'));
    });

    test('returns the activities with an id and the next page flag', () async {
      final api = apiReturning(page(
        'activities',
        [
          {'id': 1, 'type': 'TEXT', 'text': 'hi', 'likeCount': 2, 'isLiked': true},
          <String, dynamic>{},
        ],
        hasNextPage: true,
      ));

      final result = await api.fetchFeed(token);

      expect(result.hasNextPage, isTrue);
      expect(result.activities.map((a) => a['id']), [1]);
      expect(result.activities.single['isLiked'], isTrue);
    });

    test('throws when the response has no Page', () async {
      final api = apiReturning({'data': <String, dynamic>{}});

      await expectLater(api.fetchFeed(token), throwsFormatException);
    });

    test('throws on HTTP errors and reports an expired session', () async {
      final api = apiReturning({'errors': []}, status: 401);

      await expectLater(api.fetchFeed(token), throwsA(isA<AniListRequestException>()));
      expect(authExpiredNotifier.value, 1);
    });
  });

  group('fetchUnreadCount', () {
    test('returns the viewer unread notification count', () async {
      final api = apiReturning({
        'data': {
          'Viewer': {'id': 1, 'unreadNotificationCount': 7},
        },
      });

      expect(await api.fetchUnreadCount(token), 7);
      expect(log.single.query, contains('unreadNotificationCount'));
      expect(log.single.authorization, 'Bearer $token');
    });

    test('treats a missing count as zero', () async {
      final api = apiReturning({
        'data': {
          'Viewer': {'id': 1},
        },
      });

      expect(await api.fetchUnreadCount(token), 0);
    });

    test('throws when there is no Viewer', () async {
      final api = apiReturning({
        'data': {'Viewer': null},
      });

      await expectLater(api.fetchUnreadCount(token), throwsFormatException);
    });
  });

  group('fetchNotifications', () {
    test('sends the page and reset flag', () async {
      final api = apiReturning(page('notifications', []));

      await api.fetchNotifications(token, page: 2, resetCount: true);

      expect(log.single.variables, {'page': 2, 'perPage': SocialApi.notificationsPerPage, 'reset': true});
      expect(log.single.query, contains('resetNotificationCount: \$reset'));
    });

    test('parses every supported kind with what it needs', () async {
      final api = apiReturning(page('notifications', [
        {'id': 1, 'type': 'AIRING', 'createdAt': 100, 'episode': 5, 'media': media(10)},
        {'id': 2, 'type': 'FOLLOWING', 'createdAt': 101, 'user': user(20)},
        {'id': 3, 'type': 'ACTIVITY_MESSAGE', 'activityId': 30, 'user': user(21)},
        {'id': 4, 'type': 'ACTIVITY_MENTION', 'activityId': 31, 'user': user(22)},
        {'id': 5, 'type': 'ACTIVITY_REPLY', 'activityId': 32, 'user': user(23)},
        {'id': 6, 'type': 'ACTIVITY_REPLY_SUBSCRIBED', 'activityId': 33, 'user': user(24)},
        {'id': 7, 'type': 'ACTIVITY_LIKE', 'activityId': 34, 'user': user(25)},
        {'id': 8, 'type': 'ACTIVITY_REPLY_LIKE', 'activityId': 35, 'user': user(26)},
        {'id': 9, 'type': 'RELATED_MEDIA_ADDITION', 'media': media(11)},
        {'id': 10, 'type': 'MEDIA_DATA_CHANGE', 'reason': 'Fixed dates', 'media': media(12)},
        {
          'id': 11,
          'type': 'MEDIA_MERGE',
          'reason': '',
          'deletedMediaTitles': ['Old A', 'Old B'],
          'media': media(13),
        },
        {'id': 12, 'type': 'MEDIA_DELETION', 'deletedMediaTitle': 'Gone', 'reason': 'Duplicate'},
      ], hasNextPage: true));

      final result = await api.fetchNotifications(token);

      expect(result.hasNextPage, isTrue);
      expect(result.page, 1);
      expect(result.items.map((n) => n.kind), InboxKind.values);
      final airing = result.items[0];
      expect((airing.id, airing.createdAt, airing.episode, airing.mediaId), (1, 100, 5, 10));
      expect(result.items[1].userId, 20);
      expect(result.items[2].activityId, 30);
      expect(result.items[2].user?['name'], 'user21');
      expect(result.items[9].reason, 'Fixed dates');
      expect(result.items[10].reason, isNull, reason: 'blank reasons are dropped');
      expect(result.items[10].deletedMediaTitles, ['Old A', 'Old B']);
      expect(result.items[11].deletedMediaTitle, 'Gone');
    });

    test('skips unknown kinds, empty union members and incomplete entries', () async {
      final api = apiReturning(page('notifications', [
        {'id': 1, 'type': 'THREAD_COMMENT_REPLY', 'user': user(1)},
        <String, dynamic>{},
        {'id': 2, 'type': 'AIRING', 'episode': 1, 'media': null},
        {'id': 3, 'type': 'ACTIVITY_LIKE', 'user': user(2)},
        {'id': 4, 'type': 'FOLLOWING', 'user': null},
        {'type': 'FOLLOWING', 'user': user(3)},
        'not a map',
        {'id': 5, 'type': 'FOLLOWING', 'user': user(4)},
      ]));

      final result = await api.fetchNotifications(token);

      expect(result.items.map((n) => n.id), [5]);
    });

    test('round-trips through JSON for the cache', () async {
      final api = apiReturning(page('notifications', [
        {'id': 1, 'type': 'FOLLOWING', 'createdAt': 5, 'user': user(9)},
      ], hasNextPage: true));
      final fetched = await api.fetchNotifications(token, page: 3);

      final restored = NotificationsPage.fromJson(fetched.toJson());

      expect(restored.items.single.userId, 9);
      expect(restored.items.single.kind, InboxKind.following);
      expect((restored.hasNextPage, restored.page), (true, 3));
    });
  });

  group('fetchThread', () {
    test('returns the activity with its first page of replies', () async {
      final api = apiReturning({
        'data': {
          'Activity': {'id': 9, 'type': 'TEXT', 'text': 'Hello', 'replyCount': 2},
          'Page': {
            'pageInfo': {'hasNextPage': true},
            'activityReplies': [
              {'id': 1, 'text': 'first', 'user': user(1)},
              {'id': 2, 'text': 'second', 'user': user(2)},
            ],
          },
        },
      });

      final thread = await api.fetchThread(9, token: token);

      expect(log.single.variables, {'id': 9, 'page': 1, 'perPage': SocialApi.repliesPerPage});
      expect(log.single.query, contains('Activity(id: \$id)'));
      expect(log.single.query, contains('activityReplies(activityId: \$id)'));
      expect(thread.activity['text'], 'Hello');
      expect(thread.replies.map((r) => r['id']), [1, 2]);
      expect((thread.hasNextPage, thread.page), (true, 1));
    });

    test('throws a 404 request error for a deleted activity', () async {
      final api = apiReturning({
        'errors': [
          {'message': 'Not Found.', 'status': 404},
        ],
        'data': {'Activity': null, 'Page': null},
      }, status: 404);

      await expectLater(
        api.fetchThread(9, token: token),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('round-trips through JSON for the cache', () {
      const thread = ActivityThread(
        activity: {'id': 1, 'type': 'TEXT'},
        replies: [
          {'id': 2},
        ],
        hasNextPage: false,
        page: 2,
      );

      final restored = ActivityThread.fromJson(thread.toJson());

      expect(restored.activity, {'id': 1, 'type': 'TEXT'});
      expect(restored.replies.single['id'], 2);
      expect(restored.page, 2);
    });
  });

  group('fetchReplies', () {
    test('requests the given page of replies', () async {
      final api = apiReturning(page('activityReplies', [
        {'id': 51},
      ]));

      final result = await api.fetchReplies(9, page: 2, token: token);

      expect(log.single.variables, {'id': 9, 'page': 2, 'perPage': SocialApi.repliesPerPage});
      expect(result.replies.single['id'], 51);
      expect(result.hasNextPage, isFalse);
    });
  });

  group('toggleLike', () {
    test('sends the id and likeable type and returns the new state', () async {
      final api = apiReturning({
        'data': {
          'ToggleLikeV2': {'id': 3, 'isLiked': true, 'likeCount': 11},
        },
      });

      final state = await api.toggleLike(3, LikeTarget.activityReply, token: token);

      expect(log.single.variables, {'id': 3, 'type': 'ACTIVITY_REPLY'});
      expect(log.single.query, contains('ToggleLikeV2(id: \$id, type: \$type)'));
      expect(log.single.authorization, 'Bearer $token');
      expect(state, (isLiked: true, likeCount: 11));
    });

    test('returns null when AniList rejects it', () async {
      final api = apiReturning({
        'errors': [
          {'message': 'Unauthorized.'},
        ],
        'data': {'ToggleLikeV2': null},
      });

      expect(await api.toggleLike(3, LikeTarget.activity, token: token), isNull);
    });

    test('returns null instead of throwing on network errors', () async {
      final api = apiThrowing(const SocketException('offline'));

      expect(await api.toggleLike(3, LikeTarget.activity, token: token), isNull);
    });
  });

  group('postStatus', () {
    test('posts the trimmed text and returns the new activity', () async {
      final api = apiReturning({
        'data': {
          'SaveTextActivity': {'id': 77, 'type': 'TEXT', 'text': 'Hi there', 'user': user(1)},
        },
      });

      final activity = await api.postStatus('  Hi there \n', token: token);

      expect(log.single.variables, {'text': 'Hi there'});
      expect(log.single.query, contains('SaveTextActivity(text: \$text)'));
      expect(activity?['id'], 77);
    });

    test('does not send blank text', () async {
      final api = apiReturning({'data': <String, dynamic>{}});

      expect(await api.postStatus('   ', token: token), isNull);
      expect(log, isEmpty);
    });

    test('returns null on HTTP errors', () async {
      final api = apiReturning({'errors': []}, status: 500);

      expect(await api.postStatus('Hi', token: token), isNull);
    });
  });

  group('postReply', () {
    test('posts to the activity and returns the new reply', () async {
      final api = apiReturning({
        'data': {
          'SaveActivityReply': {'id': 5, 'activityId': 9, 'text': 'Nice', 'user': user(1)},
        },
      });

      final reply = await api.postReply(9, ' Nice ', token: token);

      expect(log.single.variables, {'activityId': 9, 'text': 'Nice'});
      expect(log.single.query, contains('SaveActivityReply(activityId: \$activityId, text: \$text)'));
      expect(reply?['id'], 5);
    });

    test('returns null when the response has no reply', () async {
      final api = apiReturning({
        'data': {'SaveActivityReply': null},
      });

      expect(await api.postReply(9, 'Nice', token: token), isNull);
    });

    test('does not send blank text', () async {
      final api = apiReturning({'data': <String, dynamic>{}});

      expect(await api.postReply(9, '\n', token: token), isNull);
      expect(log, isEmpty);
    });
  });

  group('like helpers', () {
    test('withLikeToggled flips the like and adjusts the count without mutating', () {
      final original = {'id': 1, 'isLiked': false, 'likeCount': 4};

      final liked = withLikeToggled(original);
      final unliked = withLikeToggled(liked);

      expect(liked, {'id': 1, 'isLiked': true, 'likeCount': 5});
      expect(unliked, {'id': 1, 'isLiked': false, 'likeCount': 4});
      expect(original, {'id': 1, 'isLiked': false, 'likeCount': 4});
    });

    test('withLikeToggled never goes below zero and handles missing fields', () {
      expect(withLikeToggled({'id': 1, 'isLiked': true, 'likeCount': 0})['likeCount'], 0);
      expect(withLikeToggled({'id': 1}), {'id': 1, 'isLiked': true, 'likeCount': 1});
    });

    test('withLikeState and likeStateOf apply and read the state', () {
      final item = withLikeState({'id': 1}, (isLiked: true, likeCount: 9));

      expect(likeStateOf(item), (isLiked: true, likeCount: 9));
      expect(likeStateOf({'id': 2}), (isLiked: false, likeCount: 0));
    });
  });

  group('malformed responses', () {
    test('a notifications field that is not a list yields an empty page', () async {
      final api = apiReturning({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'notifications': {'oops': true},
          },
        },
      });

      final result = await api.fetchNotifications(token);

      expect(result.items, isEmpty);
    });

    test('notifications with wrongly typed ids or links are skipped, not thrown on', () async {
      final api = apiReturning(page('notifications', [
        {'id': 1, 'type': 'FOLLOWING', 'createdAt': 'soon', 'user': {'id': 'five', 'name': 'x'}},
        {'id': 2, 'type': 'AIRING', 'episode': 'three', 'media': {'id': '7'}},
        {'id': 3, 'type': 'ACTIVITY_LIKE', 'activityId': '9', 'user': user(2)},
        {'id': 4, 'type': 'FOLLOWING', 'createdAt': 'soon', 'user': user(3), 'user_extra': 1},
        'not even a map',
      ]));

      final result = await api.fetchNotifications(token);

      expect(result.items.map((n) => n.id), [4]);
      expect(result.items.single.createdAt, 0);
    });

    test('a deletedMediaTitles list with non-strings keeps only the strings', () async {
      final api = apiReturning(page('notifications', [
        {'id': 1, 'type': 'MEDIA_MERGE', 'deletedMediaTitles': ['A', 3, null], 'media': media(1)},
        {'id': 2, 'type': 'MEDIA_MERGE', 'deletedMediaTitles': 'A', 'media': media(2)},
      ]));

      final result = await api.fetchNotifications(token);

      expect(result.items[0].deletedMediaTitles, ['A']);
      expect(result.items[1].deletedMediaTitles, isEmpty);
    });

    test('a feed whose activities field is not a list yields no activities', () async {
      final api = apiReturning({
        'data': {
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'activities': 'nope',
          },
        },
      });

      final result = await api.fetchFeed(token);

      expect(result.activities, isEmpty);
    });

    test('a thread whose replies field is not a list has no replies', () async {
      final api = apiReturning({
        'data': {
          'Activity': {'id': 9, 'type': 'TEXT'},
          'Page': {
            'pageInfo': {'hasNextPage': false},
            'activityReplies': 5,
          },
        },
      });

      final thread = await api.fetchThread(9);

      expect(thread.replies, isEmpty);
    });

    test('a wrongly typed unread count reads as zero', () async {
      final api = apiReturning({
        'data': {
          'Viewer': {'id': 1, 'unreadNotificationCount': 'many'},
        },
      });

      expect(await api.fetchUnreadCount(token), 0);
    });

    test('cached pages with wrong types fail with a FormatException', () {
      expect(() => NotificationsPage.fromJson('nope'), throwsFormatException);
      expect(() => ActivityThread.fromJson(['x']), throwsFormatException);
      final page = NotificationsPage.fromJson({'items': 'x', 'hasNextPage': true, 'page': 'two'});
      expect(page.items, isEmpty);
      expect(page.page, 1);
    });

    test('like helpers tolerate a wrongly typed like count', () {
      expect(likeStateOf({'isLiked': true, 'likeCount': '3'}), (isLiked: true, likeCount: 0));
      expect(withLikeToggled({'isLiked': false, 'likeCount': 'x'})['likeCount'], 1);
    });
  });
}
