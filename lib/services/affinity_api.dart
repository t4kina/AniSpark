import 'dart:async';

import '../utils/affinity.dart';
import 'anilist_service.dart';

/// The other user's list can't be read: AniList answers 404 for a private
/// profile ("Private User") and for a user that no longer exists.
class AffinityUnavailableException implements Exception {
  const AffinityUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'AffinityUnavailableException: $message';
}

// ─── GraphQL ────────────────────────────────────────────────────────────────
// Checked against the live schema by introspection. Without `chunk` the
// collection comes back whole (`hasNextChunk: false`). PLANNING entries are
// left out server-side: they are rarely scored and only add weight.

const _entryFields = 'mediaId status score(format: POINT_100)';
const _mediaFields = 'media { title { romaji english native } coverImage { medium } }';

const _collectionHead = '''
query(\$userId: Int, \$type: MediaType) {
  MediaListCollection(userId: \$userId, type: \$type, status_not: PLANNING) {
    lists {
      entries {''';
const _collectionTail = '''
      }
    }
  }
}''';

// The other user's list can hold thousands of entries, so it carries only
// what the comparison needs; titles and covers come from the viewer's list.
const _scoresQuery = '$_collectionHead $_entryFields $_collectionTail';
const _scoresWithMediaQuery = '$_collectionHead $_entryFields $_mediaFields $_collectionTail';

const _mediaTypes = {'ANIME', 'MANGA'};

typedef _ViewerList = ({
  DateTime fetchedAt,
  int session,
  Future<List<AffinityEntry>> entries,
});

/// Reads two users' scores to compare their tastes (see `utils/affinity.dart`).
///
/// Reads throw [AffinityUnavailableException] for a private list,
/// [AniListRequestException] for other API errors, and let network errors
/// and timeouts through.
class AffinityApi {
  AffinityApi({AniListService? service, DateTime Function()? clock})
      : _service = service ?? AniListService(),
        _now = clock ?? DateTime.now;

  final AniListService _service;
  final DateTime Function() _now;

  /// How long the viewer's own list is reused, so browsing several
  /// profiles in a row doesn't download it again for each one.
  static const viewerListTtl = Duration(minutes: 5);

  // Keyed by viewer and media type. Shared by every instance (each profile
  // creates its own), holds the request itself so concurrent profiles wait
  // for one download, and is tied to the session that fetched it.
  static final Map<String, _ViewerList> _viewerLists = {};

  /// Forgets the viewer's lists, e.g. after an edit to them or a logout, so
  /// the next comparison reads them again.
  static void clearViewerMemo() => _viewerLists.clear();

  /// The non-planning entries of [userId]'s [type] (`ANIME` or `MANGA`)
  /// list, once per title. With [withMedia] each carries its title and
  /// cover.
  Future<List<AffinityEntry>> fetchEntries(
    int userId,
    String type, {
    String? token,
    bool withMedia = false,
  }) async {
    if (!_mediaTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'must be ANIME or MANGA');
    }
    final Map<String, dynamic> data;
    try {
      data = await _service.request(
        withMedia ? _scoresWithMediaQuery : _scoresQuery,
        {'userId': userId, 'type': type},
        token: token,
      );
    } on AniListRequestException catch (e) {
      if (e.statusCode == 404) throw AffinityUnavailableException(e.message);
      rethrow;
    }
    final collection = data['MediaListCollection'];
    if (collection is! Map) {
      throw const AffinityUnavailableException('Response without MediaListCollection');
    }
    return List.unmodifiable(uniqueEntries(_entriesOf(collection['lists'])).values);
  }

  /// The titles on both the viewer's and [otherId]'s [type] lists, with
  /// both scores. The other list isn't downloaded when the viewer has
  /// nothing to compare.
  Future<List<SharedTitle>> fetchShared({
    required int viewerId,
    required int otherId,
    required String type,
    required String token,
  }) async {
    final mine = await _viewerEntries(viewerId, type, token);
    if (mine.isEmpty) return const [];
    final theirs = await fetchEntries(otherId, type, token: token);
    return sharedTitles(mine, theirs);
  }

  Future<List<AffinityEntry>> _viewerEntries(int viewerId, String type, String token) {
    final key = '$viewerId:$type';
    // Only a hash of the token is kept, never the token itself.
    final session = token.hashCode;
    final now = _now();
    final cached = _viewerLists[key];
    if (cached != null &&
        cached.session == session &&
        now.difference(cached.fetchedAt) < viewerListTtl) {
      return cached.entries;
    }
    final entries = fetchEntries(viewerId, type, token: token, withMedia: true);
    _viewerLists[key] = (fetchedAt: now, session: session, entries: entries);
    // A failed download is forgotten so the next profile tries again. The
    // caller still gets the error through the returned future.
    unawaited(entries.then<void>((_) {}, onError: (Object _) {
      if (identical(_viewerLists[key]?.entries, entries)) _viewerLists.remove(key);
    }));
    return entries;
  }

  static List<AffinityEntry> _entriesOf(Object? lists) => [
        if (lists is List)
          for (final list in lists)
            if (list is Map && list['entries'] is List)
              for (final row in list['entries'] as List) ?_entryOf(row),
      ];

  static AffinityEntry? _entryOf(Object? row) {
    if (row is! Map) return null;
    final mediaId = row['mediaId'];
    if (mediaId is! int) return null;
    final score = row['score'];
    final status = row['status'];
    final media = row['media'];
    final cover = media is Map ? media['coverImage'] : null;
    final coverUrl = cover is Map ? cover['medium'] : null;
    return AffinityEntry(
      mediaId: mediaId,
      score: score is num && score.isFinite ? score.toDouble().clamp(0.0, 100.0) : 0.0,
      status: status is String ? status : null,
      title: media is Map ? _titleOf(media['title']) : null,
      coverUrl: coverUrl is String ? coverUrl : null,
    );
  }

  /// The title's string fields only, so a null or odd value can't break
  /// `SettingsProvider.resolveTitle`.
  static Map<String, dynamic>? _titleOf(Object? title) {
    if (title is! Map) return null;
    return {
      for (final language in const ['romaji', 'english', 'native'])
        if (title[language] case final String text) language: text,
    };
  }
}
