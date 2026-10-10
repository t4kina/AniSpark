import 'package:flutter/foundation.dart' show debugPrint;

import 'anilist_service.dart';

/// What a like is toggled on (AniList's `LikeableType`).
enum LikeTarget {
  activity('ACTIVITY'),
  activityReply('ACTIVITY_REPLY');

  const LikeTarget(this.value);

  final String value;
}

/// The like state AniList reports after a toggle.
typedef LikeState = ({bool isLiked, int likeCount});

/// One page of the activity feed.
typedef ActivityPage = ({
  List<Map<String, dynamic>> activities,
  bool hasNextPage,
});

/// The notification kinds the inbox can show; others are skipped.
enum InboxKind {
  airing,
  following,
  activityMessage,
  activityMention,
  activityReply,
  activityReplySubscribed,
  activityLike,
  activityReplyLike,
  relatedMediaAddition,
  mediaDataChange,
  mediaMerge,
  mediaDeletion;

  bool get isAboutActivity => switch (this) {
        activityMessage ||
        activityMention ||
        activityReply ||
        activityReplySubscribed ||
        activityLike ||
        activityReplyLike =>
          true,
        _ => false,
      };

  bool get isAboutMedia => switch (this) {
        airing || relatedMediaAddition || mediaDataChange || mediaMerge => true,
        _ => false,
      };
}

const _kindsByType = {
  'AIRING': InboxKind.airing,
  'FOLLOWING': InboxKind.following,
  'ACTIVITY_MESSAGE': InboxKind.activityMessage,
  'ACTIVITY_MENTION': InboxKind.activityMention,
  'ACTIVITY_REPLY': InboxKind.activityReply,
  'ACTIVITY_REPLY_SUBSCRIBED': InboxKind.activityReplySubscribed,
  'ACTIVITY_LIKE': InboxKind.activityLike,
  'ACTIVITY_REPLY_LIKE': InboxKind.activityReplyLike,
  'RELATED_MEDIA_ADDITION': InboxKind.relatedMediaAddition,
  'MEDIA_DATA_CHANGE': InboxKind.mediaDataChange,
  'MEDIA_MERGE': InboxKind.mediaMerge,
  'MEDIA_DELETION': InboxKind.mediaDeletion,
};

/// An AniList notification the inbox knows how to show.
class InboxNotification {
  const InboxNotification._(this.json, this.kind);

  /// The notification as AniList sent it, kept for the cache.
  final Map<String, dynamic> json;
  final InboxKind kind;

  int get id => json['id'] as int;
  int get createdAt => json['createdAt'] as int? ?? 0;

  /// `{id, name, avatar: {large}}` for user-driven notifications.
  Map<String, dynamic>? get user => _map(json['user']);

  /// `{id, type, title, coverImage}` for media notifications.
  Map<String, dynamic>? get media => _map(json['media']);

  int? get userId => user?['id'] as int?;
  int? get mediaId => media?['id'] as int?;
  int? get activityId => json['activityId'] as int?;
  int? get episode => json['episode'] as int?;
  String? get reason => _nonEmpty(json['reason']);
  String? get deletedMediaTitle => _nonEmpty(json['deletedMediaTitle']);
  List<String> get deletedMediaTitles =>
      (json['deletedMediaTitles'] as List?)?.whereType<String>().toList() ?? const [];

  /// Parses one entry of `Page.notifications`, or returns null for kinds the
  /// inbox doesn't handle (forum threads, submissions) and for entries
  /// missing what they need to be shown or opened.
  static InboxNotification? tryParse(Object? json) {
    final map = _map(json);
    if (map == null || map['id'] is! int) return null;
    final kind = _kindsByType[map['type']];
    if (kind == null) return null;
    final notification = InboxNotification._(map, kind);
    final complete = switch (kind) {
      InboxKind.following => notification.userId != null,
      InboxKind.mediaDeletion => true,
      _ when kind.isAboutActivity =>
        notification.activityId != null && notification.userId != null,
      _ => notification.mediaId != null,
    };
    return complete ? notification : null;
  }
}

/// A page of the inbox. [page] is the AniList page it ends at, since pages
/// holding only skipped kinds are fetched through.
class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.hasNextPage,
    required this.page,
  });

  final List<InboxNotification> items;
  final bool hasNextPage;
  final int page;

  static NotificationsPage parse(Object? notifications, {required bool hasNextPage, required int page}) =>
      NotificationsPage(
        items: [
          for (final entry in (notifications as List?) ?? const [])
            ?InboxNotification.tryParse(entry),
        ],
        hasNextPage: hasNextPage,
        page: page,
      );

  Map<String, dynamic> toJson() => {
        'items': [for (final item in items) item.json],
        'hasNextPage': hasNextPage,
        'page': page,
      };

  static NotificationsPage fromJson(Object? json) {
    final map = json as Map;
    return parse(map['items'], hasNextPage: map['hasNextPage'] == true, page: map['page'] as int);
  }
}

/// An activity with the replies loaded so far.
class ActivityThread {
  const ActivityThread({
    required this.activity,
    required this.replies,
    required this.hasNextPage,
    required this.page,
  });

  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> replies;
  final bool hasNextPage;

  /// The last page of replies loaded.
  final int page;

  Map<String, dynamic> toJson() => {
        'activity': activity,
        'replies': replies,
        'hasNextPage': hasNextPage,
        'page': page,
      };

  static ActivityThread fromJson(Object? json) {
    final map = json as Map;
    final activity = _map(map['activity']);
    if (activity == null) throw const FormatException('Cached thread without activity');
    return ActivityThread(
      activity: activity,
      replies: _entries(map['replies']),
      hasNextPage: map['hasNextPage'] == true,
      page: map['page'] as int,
    );
  }
}

/// Returns [item] with its like flipped and the count adjusted, for
/// optimistic UI before AniList confirms.
Map<String, dynamic> withLikeToggled(Map<String, dynamic> item) {
  final liked = item['isLiked'] == true;
  final count = item['likeCount'] as int? ?? 0;
  return {...item, 'isLiked': !liked, 'likeCount': liked ? (count > 0 ? count - 1 : 0) : count + 1};
}

/// Returns [item] with the like state [state].
Map<String, dynamic> withLikeState(Map<String, dynamic> item, LikeState state) =>
    {...item, 'isLiked': state.isLiked, 'likeCount': state.likeCount};

/// The current like state of [item].
LikeState likeStateOf(Map<String, dynamic> item) =>
    (isLiked: item['isLiked'] == true, likeCount: item['likeCount'] as int? ?? 0);

/// [value] as a JSON object, or null if it isn't one.
Map<String, dynamic>? asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : (value is Map ? value.cast<String, dynamic>() : null);

Map<String, dynamic>? _map(Object? value) => asJsonMap(value);

String? _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

/// [value] as a map if it carries an id. Unknown union members come back
/// from AniList as empty objects.
Map<String, dynamic>? _withId(Object? value) {
  final map = _map(value);
  return map != null && map['id'] is int ? map : null;
}

/// The maps in [list] that carry an id.
List<Map<String, dynamic>> _entries(Object? list) => [
      for (final entry in (list as List?) ?? const []) ?_withId(entry),
    ];

// ─── GraphQL ────────────────────────────────────────────────────────────────
// Checked against the live schema by introspection.

const _userFields = 'id name avatar { large }';
const _mediaFields = 'id type title { romaji english native } coverImage { large }';
const _socialFields = 'isLiked likeCount replyCount isLocked';

const _listActivity = '''
  ... on ListActivity {
    id type status progress createdAt $_socialFields
    user { $_userFields }
    media { $_mediaFields }
  }''';
const _textActivityFields = '''
    id type text(asHtml: false) createdAt $_socialFields
    user { $_userFields }''';
const _textActivity = '... on TextActivity { $_textActivityFields }';
const _messageActivity = '''
  ... on MessageActivity {
    id type message(asHtml: false) createdAt $_socialFields isPrivate
    messenger { $_userFields }
    recipient { $_userFields }
  }''';
const _replyFields = 'id activityId text(asHtml: false) createdAt isLiked likeCount user { $_userFields }';

const _activityNotification = 'id type createdAt activityId user { $_userFields }';

const _notificationsQuery = '''
query(\$page: Int, \$perPage: Int, \$reset: Boolean) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { hasNextPage }
    notifications(resetNotificationCount: \$reset) {
      ... on AiringNotification { id type createdAt episode media { $_mediaFields } }
      ... on FollowingNotification { id type createdAt user { $_userFields } }
      ... on ActivityMessageNotification { $_activityNotification }
      ... on ActivityMentionNotification { $_activityNotification }
      ... on ActivityReplyNotification { $_activityNotification }
      ... on ActivityReplySubscribedNotification { $_activityNotification }
      ... on ActivityLikeNotification { $_activityNotification }
      ... on ActivityReplyLikeNotification { $_activityNotification }
      ... on RelatedMediaAdditionNotification { id type createdAt media { $_mediaFields } }
      ... on MediaDataChangeNotification { id type createdAt reason media { $_mediaFields } }
      ... on MediaMergeNotification { id type createdAt reason deletedMediaTitles media { $_mediaFields } }
      ... on MediaDeletionNotification { id type createdAt reason deletedMediaTitle }
    }
  }
}''';

const _unreadCountQuery = 'query { Viewer { id unreadNotificationCount } }';

const _repliesPage = '''
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { hasNextPage }
    activityReplies(activityId: \$id) { $_replyFields }
  }''';

const _threadQuery = '''
query(\$id: Int, \$page: Int, \$perPage: Int) {
  Activity(id: \$id) {
    $_listActivity
    $_textActivity
    $_messageActivity
  }
  $_repliesPage
}''';

const _repliesQuery = '''
query(\$id: Int, \$page: Int, \$perPage: Int) {
  $_repliesPage
}''';

const _toggleLikeMutation = '''
mutation(\$id: Int, \$type: LikeableType) {
  ToggleLikeV2(id: \$id, type: \$type) {
    ... on ListActivity { id isLiked likeCount }
    ... on TextActivity { id isLiked likeCount }
    ... on MessageActivity { id isLiked likeCount }
    ... on ActivityReply { id isLiked likeCount }
  }
}''';

const _postStatusMutation = '''
mutation(\$text: String) {
  SaveTextActivity(text: \$text) { $_textActivityFields }
}''';

const _postReplyMutation = '''
mutation(\$activityId: Int, \$text: String) {
  SaveActivityReply(activityId: \$activityId, text: \$text) { $_replyFields }
}''';

/// AniList social features: the activity feed with likes and replies,
/// posting, and the notifications inbox.
///
/// Reads throw ([AniListRequestException], network errors, or
/// [FormatException] for an unexpected shape); mutations never throw and
/// return null when AniList didn't accept the change.
class SocialApi {
  SocialApi({AniListService? service}) : _service = service ?? AniListService();

  final AniListService _service;

  static const feedPerPage = 30;
  static const notificationsPerPage = 25;
  static const repliesPerPage = 50;

  /// The following (default), global (`isFollowing: false`) or, with
  /// [userId], one user's activity feed, newest first.
  Future<ActivityPage> fetchFeed(
    String token, {
    bool isFollowing = true,
    int? userId,
    int page = 1,
  }) async {
    final byUser = userId != null;
    final query = '''
query(\$isFollowing: Boolean, \$page: Int, \$perPage: Int${byUser ? ', \$userId: Int' : ''}) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { hasNextPage }
    activities(isFollowing: \$isFollowing${byUser ? ', userId: \$userId' : ''}, sort: ID_DESC) {
      $_listActivity
      $_textActivity
    }
  }
}''';
    final data = await _service.request(
      query,
      {'isFollowing': isFollowing, 'page': page, 'perPage': feedPerPage, 'userId': ?userId},
      token: token,
    );
    final pageData = _page(data);
    return (activities: _entries(pageData['activities']), hasNextPage: _hasNextPage(pageData));
  }

  /// The viewer's unread notification count.
  Future<int> fetchUnreadCount(String token) async {
    final data = await _service.request(_unreadCountQuery, const {}, token: token);
    final viewer = _map(data['Viewer']);
    if (viewer == null) throw const FormatException('Response without Viewer');
    return viewer['unreadNotificationCount'] as int? ?? 0;
  }

  /// One page of notifications, newest first. [resetCount] marks them all
  /// read on AniList (clearing the unread badge).
  Future<NotificationsPage> fetchNotifications(String token, {int page = 1, bool resetCount = false}) async {
    final data = await _service.request(
      _notificationsQuery,
      {'page': page, 'perPage': notificationsPerPage, 'reset': resetCount},
      token: token,
    );
    final pageData = _page(data);
    return NotificationsPage.parse(pageData['notifications'], hasNextPage: _hasNextPage(pageData), page: page);
  }

  /// The activity [activityId] with its first page of replies. A deleted
  /// activity throws [AniListRequestException] with status 404.
  Future<ActivityThread> fetchThread(int activityId, {String? token}) async {
    final data = await _service.request(
      _threadQuery,
      {'id': activityId, 'page': 1, 'perPage': repliesPerPage},
      token: token,
    );
    final activity = _map(data['Activity']);
    if (activity == null || activity['id'] is! int) {
      throw const FormatException('Response without Activity');
    }
    final pageData = _page(data);
    return ActivityThread(
      activity: activity,
      replies: _entries(pageData['activityReplies']),
      hasNextPage: _hasNextPage(pageData),
      page: 1,
    );
  }

  /// A further page of replies to [activityId], oldest first.
  Future<({List<Map<String, dynamic>> replies, bool hasNextPage})> fetchReplies(
    int activityId, {
    required int page,
    String? token,
  }) async {
    final data = await _service.request(
      _repliesQuery,
      {'id': activityId, 'page': page, 'perPage': repliesPerPage},
      token: token,
    );
    final pageData = _page(data);
    return (replies: _entries(pageData['activityReplies']), hasNextPage: _hasNextPage(pageData));
  }

  /// Likes or unlikes [id]. Returns the new state, or null on failure.
  Future<LikeState?> toggleLike(int id, LikeTarget target, {required String token}) =>
      _mutate('ToggleLikeV2', () async {
        final data = await _service.request(
          _toggleLikeMutation,
          {'id': id, 'type': target.value},
          token: token,
        );
        final liked = _map(data['ToggleLikeV2']);
        final isLiked = liked?['isLiked'];
        final likeCount = liked?['likeCount'];
        return isLiked is bool && likeCount is int ? (isLiked: isLiked, likeCount: likeCount) : null;
      });

  /// Posts a status update. Returns the new activity, or null on failure or
  /// for blank [text].
  Future<Map<String, dynamic>?> postStatus(String text, {required String token}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return _mutate('SaveTextActivity', () async {
      final data = await _service.request(_postStatusMutation, {'text': trimmed}, token: token);
      return _withId(data['SaveTextActivity']);
    });
  }

  /// Replies to [activityId]. Returns the new reply, or null on failure or
  /// for blank [text].
  Future<Map<String, dynamic>?> postReply(int activityId, String text, {required String token}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return _mutate('SaveActivityReply', () async {
      final data = await _service.request(
        _postReplyMutation,
        {'activityId': activityId, 'text': trimmed},
        token: token,
      );
      return _withId(data['SaveActivityReply']);
    });
  }

  Future<T?> _mutate<T>(String name, Future<T?> Function() run) async {
    try {
      return await run();
    } on Exception catch (e) {
      debugPrint('[SocialApi] $name failed: $e');
      return null;
    }
  }

  static Map<String, dynamic> _page(Map<String, dynamic> data) {
    final page = _map(data['Page']);
    if (page == null) throw const FormatException('Response without Page');
    return page;
  }

  static bool _hasNextPage(Map<String, dynamic> page) => _map(page['pageInfo'])?['hasNextPage'] == true;
}
