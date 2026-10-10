import 'dart:convert';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/media_extras_api.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

Map<String, dynamic> _user(int id, String name, {String? avatar}) => {
      'id': id,
      'name': name,
      'avatar': {'medium': avatar},
    };

Map<String, dynamic> _reviewNode(int id, {String summary = 'Great show'}) => {
      'id': id,
      'summary': summary,
      'rating': 367,
      'ratingAmount': 781,
      'score': 70,
      'user': _user(410834, 'Limitless', avatar: 'https://img/a.jpg'),
    };

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  MediaExtrasApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      MediaExtrasApi(service: AniListService(client: mockAniList(log, handler)));

  MediaExtrasApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  group('getReviews', () {
    Map<String, dynamic> reviewsBody(List<Object?> nodes, {bool hasNextPage = false}) => {
          'data': {
            'Media': {
              'reviews': {
                'pageInfo': {'hasNextPage': hasNextPage},
                'nodes': nodes,
              },
            },
          },
        };

    test('asks for the media reviews by rating with the default page size', () async {
      final api = apiReturning(reviewsBody([]));

      await api.getReviews(1);

      final request = log.single;
      expect(request.variables, {'id': 1, 'page': 1, 'perPage': MediaExtrasApi.sectionReviewCount});
      expect(request.query, contains('reviews(sort: [RATING_DESC], page: \$page, perPage: \$perPage)'));
      expect(request.authorization, isNull, reason: 'reviews are public');
    });

    test('sends the requested page and page size', () async {
      final api = apiReturning(reviewsBody([]));

      await api.getReviews(21, page: 3, perPage: 20);

      expect(log.single.variables, {'id': 21, 'page': 3, 'perPage': 20});
    });

    test('parses the reviews, their authors and whether more pages exist', () async {
      final api = apiReturning(reviewsBody([_reviewNode(7295), _reviewNode(2242, summary: 'Review of Bebop')], hasNextPage: true));

      final page = await api.getReviews(1);

      expect(page.hasNextPage, isTrue);
      expect(page.reviews.map((r) => r.id), [7295, 2242]);
      final first = page.reviews.first;
      expect(first.summary, 'Great show');
      expect(first.rating, 367);
      expect(first.ratingAmount, 781);
      expect(first.score, 70);
      expect(first.body, isNull, reason: 'the list query does not load bodies');
      expect(first.user.id, 410834);
      expect(first.user.name, 'Limitless');
      expect(first.user.avatarUrl, 'https://img/a.jpg');
    });

    test('skips malformed nodes instead of failing the whole page', () async {
      final api = apiReturning(reviewsBody([
        _reviewNode(1),
        null,
        {'id': 2, 'summary': 'No author', 'user': null},
        {'summary': 'No id', 'user': _user(3, 'x')},
        {'id': 4, 'user': _user(4, 'Sparse')},
      ]));

      final page = await api.getReviews(1);

      expect(page.reviews.map((r) => r.id), [1, 4]);
      final sparse = page.reviews.last;
      expect(sparse.summary, '');
      expect(sparse.rating, 0);
      expect(sparse.ratingAmount, 0);
      expect(sparse.score, 0);
      expect(sparse.user.avatarUrl, isNull);
    });

    test('returns an empty last page when the media does not exist', () async {
      final api = apiReturning({
        'data': {'Media': null},
      });

      final page = await api.getReviews(999999);

      expect(page.reviews, isEmpty);
      expect(page.hasNextPage, isFalse);
    });

    test('rethrows request errors', () async {
      final api = apiReturning({'errors': []}, status: 500);

      await expectLater(
        api.getReviews(1),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('survives a JSON round trip, as the cache stores it', () async {
      final api = apiReturning(reviewsBody([_reviewNode(7295)], hasNextPage: true));
      final page = await api.getReviews(1);

      final restored = ReviewsPage.fromJson(jsonDecode(jsonEncode(page)));

      expect(restored.hasNextPage, isTrue);
      expect(restored.reviews.single.id, 7295);
      expect(restored.reviews.single.summary, 'Great show');
      expect(restored.reviews.single.rating, 367);
      expect(restored.reviews.single.user.name, 'Limitless');
      expect(restored.reviews.single.user.avatarUrl, 'https://img/a.jpg');
    });

    test('treats unreadable cached data as an empty page', () {
      expect(ReviewsPage.fromJson('garbage').reviews, isEmpty);
      expect(ReviewsPage.fromJson(null).hasNextPage, isFalse);
    });
  });

  group('getReview', () {
    test('asks for the review by id with its plain markdown body', () async {
      final api = apiReturning({
        'data': {
          'Review': {
            ..._reviewNode(2242),
            'body': '# __Title__\nText',
            'createdAt': 1499666384,
          },
        },
      });

      final review = await api.getReview(2242);

      expect(log.single.variables, {'id': 2242});
      expect(log.single.query, contains('body(asHtml: false)'));
      expect(log.single.authorization, isNull);
      expect(review.id, 2242);
      expect(review.body, '# __Title__\nText');
      expect(review.createdAt, 1499666384);
      expect(review.score, 70);
      expect(review.user.name, 'Limitless');
    });

    test('keeps the body and date through a JSON round trip', () async {
      final api = apiReturning({
        'data': {
          'Review': {..._reviewNode(5), 'body': 'Body', 'createdAt': 10},
        },
      });
      final review = await api.getReview(5);

      final restored = Review.fromJson(jsonDecode(jsonEncode(review)));

      expect(restored?.body, 'Body');
      expect(restored?.createdAt, 10);
    });

    test('throws when the response has no usable review', () async {
      final api = apiReturning({
        'data': {'Review': null},
      });

      await expectLater(api.getReview(1), throwsA(isA<AniListRequestException>()));
    });

    test('rethrows a missing review reported by AniList', () async {
      final api = apiReturning({
        'data': null,
        'errors': [
          {'message': 'Not Found.'},
        ],
      }, status: 404);

      await expectLater(
        api.getReview(1),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('getFollowing', () {
    Map<String, dynamic> followingBody(List<Object?> entries) => {
          'data': {
            'Page': {'mediaList': entries},
          },
        };

    test("sends the viewer's token and asks only for followed users", () async {
      final api = apiReturning(followingBody([]));

      await api.getFollowing(16498, token: 'secret-token');

      final request = log.single;
      expect(request.authorization, 'Bearer secret-token');
      expect(request.variables, {'id': 16498, 'perPage': MediaExtrasApi.followingLimit});
      expect(request.query, contains('isFollowing: true'));
      expect(request.query, contains('sort: UPDATED_TIME_DESC'));
      expect(request.query, contains('score(format: POINT_10_DECIMAL)'));
    });

    test('parses status, progress, decimal scores and users', () async {
      final api = apiReturning(followingBody([
        {'status': 'CURRENT', 'progress': 12, 'score': 8.5, 'user': _user(1, 'Ann', avatar: 'https://img/1.jpg')},
        {'status': 'COMPLETED', 'progress': 25, 'score': 9, 'user': _user(2, 'Ben')},
        {'status': 'PLANNING', 'progress': 0, 'score': 0, 'user': _user(3, 'Cy')},
      ]));

      final entries = await api.getFollowing(1, token: 't');

      expect(entries.map((e) => e.user.name), ['Ann', 'Ben', 'Cy']);
      expect(entries[0].status, 'CURRENT');
      expect(entries[0].progress, 12);
      expect(entries[0].score, 8.5);
      expect(entries[0].user.avatarUrl, 'https://img/1.jpg');
      expect(entries[1].score, 9.0);
      expect(entries[2].score, 0.0);
    });

    test('skips entries without a user or status and defaults missing numbers', () async {
      final api = apiReturning(followingBody([
        {'status': 'CURRENT', 'progress': 1, 'score': 1, 'user': null},
        {'progress': 1, 'user': _user(2, 'No status')},
        'garbage',
        {'status': 'DROPPED', 'user': _user(4, 'Dee')},
      ]));

      final entries = await api.getFollowing(1, token: 't');

      expect(entries.single.user.name, 'Dee');
      expect(entries.single.progress, 0);
      expect(entries.single.score, 0.0);
    });

    test('returns an empty list when the page has no entries', () async {
      final api = apiReturning({
        'data': {'Page': null},
      });

      expect(await api.getFollowing(1, token: 't'), isEmpty);
    });

    test('reports an expired session on 401', () async {
      final api = apiReturning({'errors': []}, status: 401);

      await expectLater(api.getFollowing(1, token: 't'), throwsA(isA<AniListRequestException>()));
      expect(authExpiredNotifier.value, 1);
    });

    test('survives a JSON round trip, as the cache stores it', () async {
      final api = apiReturning(followingBody([
        {'status': 'REPEATING', 'progress': 3, 'score': 7.5, 'user': _user(9, 'Eve', avatar: 'https://img/9.jpg')},
      ]));
      final entries = await api.getFollowing(1, token: 't');

      final restored = FollowingEntry.listFromJson(jsonDecode(jsonEncode(entries)));

      expect(restored.single.status, 'REPEATING');
      expect(restored.single.progress, 3);
      expect(restored.single.score, 7.5);
      expect(restored.single.user.id, 9);
      expect(restored.single.user.avatarUrl, 'https://img/9.jpg');
    });

    test('treats unreadable cached data as no entries', () {
      expect(FollowingEntry.listFromJson({'not': 'a list'}), isEmpty);
    });
  });
}
