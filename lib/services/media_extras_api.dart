import 'package:flutter/foundation.dart' show immutable;

import 'anilist_service.dart';

/// The extra sections of the media detail page: community reviews and what
/// the people the viewer follows are doing with the media.
class MediaExtrasApi {
  MediaExtrasApi({AniListService? service}) : _service = service ?? AniListService();

  final AniListService _service;

  /// Reviews shown in the detail page's horizontal row.
  static const sectionReviewCount = 10;

  /// Followed users' entries fetched for the FOLLOWING section.
  static const followingLimit = 25;

  // AniList caps perPage at 50.
  static const _maxPerPage = 50;

  static const _userFields = 'user { id name avatar { medium } }';

  static const _reviewsQuery = '''
    query (\$id: Int, \$page: Int, \$perPage: Int) {
      Media(id: \$id) {
        reviews(sort: [RATING_DESC], page: \$page, perPage: \$perPage) {
          pageInfo { hasNextPage }
          nodes { id summary rating ratingAmount score $_userFields }
        }
      }
    }
  ''';

  static const _reviewQuery = '''
    query (\$id: Int) {
      Review(id: \$id) {
        id summary body(asHtml: false) rating ratingAmount score createdAt
        $_userFields
      }
    }
  ''';

  static const _followingQuery = '''
    query (\$id: Int, \$perPage: Int) {
      Page(perPage: \$perPage) {
        mediaList(mediaId: \$id, isFollowing: true, sort: UPDATED_TIME_DESC) {
          status progress score(format: POINT_10_DECIMAL)
          $_userFields
        }
      }
    }
  ''';

  /// One page of [mediaId]'s reviews, most liked first. Public, no token.
  Future<ReviewsPage> getReviews(
    int mediaId, {
    int page = 1,
    int perPage = sectionReviewCount,
  }) async {
    assert(page >= 1, 'AniList pages start at 1');
    assert(perPage >= 1 && perPage <= _maxPerPage, 'perPage must be 1–$_maxPerPage');
    final data = await _service.request(
      _reviewsQuery,
      {'id': mediaId, 'page': page, 'perPage': perPage},
    );
    final media = data['Media'];
    return ReviewsPage.fromJson(media is Map ? media['reviews'] : null);
  }

  /// The full review [reviewId], including its raw markdown body.
  Future<Review> getReview(int reviewId) async {
    final data = await _service.request(_reviewQuery, {'id': reviewId});
    final review = Review.fromJson(data['Review']);
    if (review == null) {
      throw const AniListRequestException('No review in the response', statusCode: 200);
    }
    return review;
  }

  /// The list entries for [mediaId] of the users the viewer follows, most
  /// recently updated first. Needs the viewer's [token].
  Future<List<FollowingEntry>> getFollowing(int mediaId, {required String token}) async {
    final data = await _service.request(
      _followingQuery,
      {'id': mediaId, 'perPage': followingLimit},
      token: token,
    );
    final page = data['Page'];
    return FollowingEntry.listFromJson(page is Map ? page['mediaList'] : null);
  }
}

T? _as<T>(Object? value) => value is T ? value : null;

/// An AniList user as shown next to a review or a list entry.
@immutable
class MiniUser {
  const MiniUser({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;

  /// Parses `user { id name avatar { medium } }`; null without id or name.
  static MiniUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    final name = _as<String>(json['name']);
    if (id == null || name == null) return null;
    final avatar = json['avatar'];
    return MiniUser(
      id: id,
      name: name,
      avatarUrl: avatar is Map ? _as<String>(avatar['medium']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': {'medium': avatarUrl},
      };
}

/// A user review of a media. [body] is only loaded for the full review.
@immutable
class Review {
  const Review({
    required this.id,
    required this.user,
    this.summary = '',
    this.rating = 0,
    this.ratingAmount = 0,
    this.score = 0,
    this.body,
    this.createdAt,
  });

  final int id;
  final MiniUser user;
  final String summary;

  /// How many users liked the review (AniList's upvotes).
  final int rating;

  /// How many users rated the review, liked or not.
  final int ratingAmount;

  /// The reviewer's own score for the media, 0–100.
  final int score;

  /// Raw AniList markdown; see `cleanReviewText` for display.
  final String? body;

  /// Unix timestamp in seconds.
  final int? createdAt;

  /// Parses a review node (same shape as [toJson]); null without id or user.
  static Review? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _as<int>(json['id']);
    final user = MiniUser.fromJson(json['user']);
    if (id == null || user == null) return null;
    return Review(
      id: id,
      user: user,
      summary: _as<String>(json['summary'])?.trim() ?? '',
      rating: _as<int>(json['rating']) ?? 0,
      ratingAmount: _as<int>(json['ratingAmount']) ?? 0,
      score: _as<int>(json['score']) ?? 0,
      body: _as<String>(json['body']),
      createdAt: _as<int>(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'summary': summary,
        'rating': rating,
        'ratingAmount': ratingAmount,
        'score': score,
        'body': ?body,
        'createdAt': ?createdAt,
        'user': user.toJson(),
      };
}

/// One page of a media's reviews.
@immutable
class ReviewsPage {
  const ReviewsPage({required this.reviews, required this.hasNextPage});

  static const empty = ReviewsPage(reviews: [], hasNextPage: false);

  final List<Review> reviews;
  final bool hasNextPage;

  /// Parses `reviews { pageInfo { hasNextPage } nodes {…} }`, skipping
  /// malformed nodes; anything unreadable is an empty last page.
  static ReviewsPage fromJson(Object? json) {
    if (json is! Map) return empty;
    final pageInfo = json['pageInfo'];
    final nodes = json['nodes'];
    return ReviewsPage(
      reviews: List.unmodifiable([
        if (nodes is List)
          for (final node in nodes) ?Review.fromJson(node),
      ]),
      hasNextPage: pageInfo is Map && pageInfo['hasNextPage'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'pageInfo': {'hasNextPage': hasNextPage},
        'nodes': [for (final review in reviews) review.toJson()],
      };
}

/// A followed user's list entry for a media.
@immutable
class FollowingEntry {
  const FollowingEntry({
    required this.user,
    required this.status,
    this.progress = 0,
    this.score = 0,
  });

  final MiniUser user;

  /// AniList's MediaListStatus: CURRENT, PLANNING, COMPLETED, DROPPED,
  /// PAUSED or REPEATING.
  final String status;

  /// Episodes watched or chapters read.
  final int progress;

  /// 0–10 (read with POINT_10_DECIMAL); 0 means not scored.
  final double score;

  /// Parses a `mediaList` entry; null without a user or status.
  static FollowingEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = MiniUser.fromJson(json['user']);
    final status = _as<String>(json['status']);
    if (user == null || status == null) return null;
    return FollowingEntry(
      user: user,
      status: status,
      progress: _as<int>(json['progress']) ?? 0,
      score: _as<num>(json['score'])?.toDouble() ?? 0,
    );
  }

  /// Parses a list of entries, skipping malformed ones.
  static List<FollowingEntry> listFromJson(Object? json) => List.unmodifiable([
        if (json is List)
          for (final entry in json) ?FollowingEntry.fromJson(entry),
      ]);

  Map<String, dynamic> toJson() => {
        'status': status,
        'progress': progress,
        'score': score,
        'user': user.toJson(),
      };
}
