import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../providers/media_list_store.dart';
import '../../services/affinity_api.dart';
import '../../services/anilist_service.dart';
import '../../services/api_cache.dart';
import '../../services/notification_service.dart';
import 'entry_draft.dart';

/// What the entry editor needs to know about the media an entry is for.
@immutable
class EditorMedia {
  const EditorMedia({
    required this.id,
    required this.isManga,
    this.title,
    this.coverUrl,
    this.totalProgress,
    this.totalVolumes,
  });

  /// Reads an AniList `Media` map (the detail page's, a list entry's or a
  /// Discover card's), or returns null without an id. Without a `type`, a
  /// media with chapters but no episodes is taken for manga until the
  /// editor's lookup confirms it.
  static EditorMedia? fromMedia(Map<String, dynamic>? media, {bool? isManga}) {
    final id = media?['id'];
    if (media == null || id is! int) return null;
    final manga = isManga ??
        switch (media['type']) {
          'MANGA' => true,
          'ANIME' => false,
          _ => media.containsKey('chapters') && !media.containsKey('episodes'),
        };
    return EditorMedia(
      id: id,
      isManga: manga,
      title: media['title'] as Map<String, dynamic>?,
      coverUrl: (media['coverImage'] as Map?)?['large'] as String?,
    )._withTotalsFrom(media, isManga: manga);
  }

  final int id;
  final bool isManga;
  final Map<String, dynamic>? title;
  final String? coverUrl;

  /// Episodes (anime) or chapters (manga), when known.
  final int? totalProgress;

  /// Volumes of a manga, when known.
  final int? totalVolumes;

  String get type => isManga ? 'MANGA' : 'ANIME';

  EditorMedia _withTotalsFrom(Map<String, dynamic> media, {required bool isManga}) => EditorMedia(
        id: id,
        isManga: isManga,
        title: title,
        coverUrl: coverUrl,
        totalProgress: ((isManga ? media['chapters'] : media['episodes']) as num?)?.toInt(),
        totalVolumes: isManga ? (media['volumes'] as num?)?.toInt() : null,
      );
}

const _entrySelection = '''
  id status progress progressVolumes score(format: POINT_10_DECIMAL)
  repeat private hiddenFromStatusLists notes customLists
  startedAt { year month day } completedAt { year month day }
''';

/// Reads the viewer's current entry for [media] (null when it isn't in the
/// list) together with the media's type and totals. Throws when AniList
/// can't be reached or answers without the media.
Future<(EditorMedia, Map<String, dynamic>?)> fetchEditorEntry(
  AniListService service,
  EditorMedia media,
  String token,
) async {
  final data = await service.request(
    '''
      query(\$id: Int) {
        Media(id: \$id) {
          id type episodes chapters volumes
          mediaListEntry { $_entrySelection }
        }
      }
    ''',
    {'id': media.id},
    token: token,
  );
  final fetched = data['Media'];
  if (fetched is! Map<String, dynamic>) {
    throw const AniListRequestException('Media not found', statusCode: 200);
  }
  final entry = fetched['mediaListEntry'];
  final isManga = switch (fetched['type']) {
    'MANGA' => true,
    'ANIME' => false,
    _ => media.isManga,
  };
  return (
    media._withTotalsFrom(fetched, isManga: isManga),
    entry is Map<String, dynamic> ? entry : null,
  );
}

/// Loads the user's custom list names for [type] from the cache the detail
/// page has always used, refreshing them at most hourly. Failures are
/// logged and leave the names out.
Future<void> loadCustomListNames({
  required ApiCache cache,
  required AniListService service,
  required int userId,
  required String type,
  required String token,
  required ValueChanged<List<String>> onData,
}) async {
  try {
    await cache.load<List<String>>(
      key: ApiCache.userKey(userId, 'customLists:$type'),
      maxAge: const Duration(hours: 1),
      fetch: () => service.getCustomListNames(userId, type, token),
      decode: (json) => [for (final name in json as List) name as String],
      onData: (names, {required isFresh}) => onData(names),
    );
  } on Exception catch (e) {
    debugPrint('[EntryEditor] Loading custom lists failed: $e');
  }
}

/// Saves [changes] for [media] and keeps the shared lists in sync: My List
/// shows the saved values at once, then reloads the list of that type if it
/// has it (or is loading it), which also picks up new entries and custom
/// list changes. A type My List never loaded isn't downloaded: it loads when
/// opened. Returns the saved entry, or null if AniList rejected the change.
Future<Map<String, dynamic>?> saveEntryChanges({
  required AniListService service,
  required MediaListStore store,
  required EditorMedia media,
  required EntryChanges changes,
  required String token,
  required int? userId,
}) async {
  final saved = await service.saveListEntry(
    mediaId: media.id,
    token: token,
    status: changes.status,
    progress: changes.progress,
    progressVolumes: changes.progressVolumes,
    scoreRaw: changes.scoreRaw,
    repeat: changes.repeat,
    private: changes.private,
    hiddenFromStatusLists: changes.hiddenFromStatusLists,
    notes: changes.notes,
    customLists: changes.customLists,
    startedAt: changes.startedAt,
    completedAt: changes.completedAt,
  );
  if (saved == null) return null;
  AffinityApi.clearViewerMemo();
  store.applySavedEntry(media.type, media.id, saved);
  // A load already running may have read the list before this save, so it
  // is followed by a fresh one.
  final listed = store.listsOf(media.type) != null || store.isLoading(media.type);
  if (userId != null && listed) {
    unawaited(store.load(media.type, userId: userId, token: token, force: true));
  }
  return saved;
}

/// Deletes the entry [entryId] of [media], cancels its episode reminders and
/// drops it from the shared lists. Returns whether AniList deleted it.
Future<bool> removeEntry({
  required AniListService service,
  required MediaListStore store,
  required EditorMedia media,
  required int entryId,
  required String token,
}) async {
  final ok = await service.deleteListEntry(entryId: entryId, token: token);
  if (!ok) return false;
  AffinityApi.clearViewerMemo();
  unawaited(NotificationService().cancelForMedia(media.id).onError<Exception>(
        (e, _) => debugPrint('[EntryEditor] Cancelling reminders failed: $e'),
      ));
  store.removeEntry(media.type, media.id);
  return true;
}
