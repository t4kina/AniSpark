import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/anilist_service.dart';
import '../services/api_cache.dart';

/// One media type's lists: status keys (`CURRENT`, `COMPLETED`, …) and
/// `custom:<name>` keys, each holding AniList list entries.
typedef MediaLists = Map<String, List<Map<String, dynamic>>>;

const customListPrefix = 'custom:';

/// Single source of truth for the signed-in user's anime and manga lists,
/// shared by the list tabs and the detail screen. It shows cached lists
/// instantly, refreshes them from AniList, and applies edits locally from
/// the mutation response instead of re-downloading the whole collection.
class MediaListStore extends ChangeNotifier {
  MediaListStore({required AniListService service, required ApiCache cache})
      : _service = service,
        _cache = cache;

  final AniListService _service;
  final ApiCache _cache;

  final Map<String, MediaLists> _lists = {};
  final Map<String, Object> _errors = {};
  final Set<String> _loading = {};
  final Set<String> _reloadRequested = {};
  final Set<int> _saving = {};
  int? _userId;

  MediaLists? listsOf(String type) => _lists[type];
  Object? errorOf(String type) => _errors[type];
  bool isLoading(String type) => _loading.contains(type);
  bool isSaving(int mediaId) => _saving.contains(mediaId);

  /// Shows the cached lists for [userId] right away, then fetches fresh ones
  /// (skipping the cache when [force] is set). A load requested while one is
  /// running is queued so the newest server state always wins. Returns
  /// whether fresh data arrived.
  Future<bool> load(
    String type, {
    required int userId,
    required String token,
    bool force = false,
  }) async {
    if (_userId != userId) {
      reset();
      _userId = userId;
    }
    if (_loading.contains(type)) {
      _reloadRequested.add(type);
      return false;
    }
    _loading.add(type);
    _errors.remove(type);
    notifyListeners();

    var gotFresh = false;
    try {
      await _cache.load<MediaLists>(
        key: _cacheKey(userId, type),
        fetch: () => _fetch(type, userId, token),
        decode: _decodeLists,
        force: force,
        onData: (lists, {required isFresh}) {
          if (_userId != userId) return;
          _lists[type] = lists;
          gotFresh = gotFresh || isFresh;
          notifyListeners();
        },
      );
    } on Exception catch (e) {
      debugPrint('[MediaListStore] Loading $type failed: $e');
      if (_userId == userId) _errors[type] = e;
    } finally {
      _loading.remove(type);
      notifyListeners();
    }

    if (_reloadRequested.remove(type) && _userId == userId) {
      final reloaded = await load(type, userId: userId, token: token, force: true);
      return gotFresh || reloaded;
    }
    return gotFresh;
  }

  /// Shows the new progress immediately and saves only that field, so the
  /// entry's score, notes and custom lists are never rewritten. Restores the
  /// old value and returns false if AniList rejects it, or if a save for the
  /// same entry is still running.
  Future<bool> setProgress(
    String type,
    int mediaId,
    int progress, {
    required String token,
  }) async {
    final original = _findEntry(type, mediaId);
    if (original == null || !_saving.add(mediaId)) return false;
    _updateEntry(type, mediaId, (e) => {...e, 'progress': progress});
    notifyListeners();
    try {
      final saved = await _service.saveListEntry(
        mediaId: mediaId,
        progress: progress,
        token: token,
      );
      if (saved == null) {
        _updateEntry(type, mediaId, (e) => {...e, 'progress': original['progress']});
        return false;
      }
      _applySaved(type, mediaId, saved);
      return true;
    } finally {
      _saving.remove(mediaId);
      notifyListeners();
      _persist(type);
    }
  }

  /// Saves several fields of an entry already in the list (e.g. completing a
  /// series) and applies AniList's response, moving the entry if its status
  /// changed.
  Future<bool> saveFields(
    String type,
    int mediaId, {
    required String token,
    String? status,
    int? progress,
    int? scoreRaw,
  }) async {
    if (_findEntry(type, mediaId) == null || !_saving.add(mediaId)) return false;
    notifyListeners();
    try {
      final saved = await _service.saveListEntry(
        mediaId: mediaId,
        status: status,
        progress: progress,
        scoreRaw: scoreRaw,
        token: token,
      );
      if (saved == null) return false;
      _applySaved(type, mediaId, saved);
      return true;
    } finally {
      _saving.remove(mediaId);
      notifyListeners();
      _persist(type);
    }
  }

  /// Removes an entry deleted elsewhere (e.g. from the detail screen).
  void removeEntry(String type, int mediaId) {
    final lists = _lists[type];
    if (lists == null) return;
    _lists[type] = {
      for (final MapEntry(:key, :value) in lists.entries)
        key: [for (final e in value) if (_mediaIdOf(e) != mediaId) e],
    };
    notifyListeners();
    _persist(type);
  }

  /// Forgets everything, e.g. after logout.
  void reset() {
    _lists.clear();
    _errors.clear();
    _loading.clear();
    _reloadRequested.clear();
    _saving.clear();
    _userId = null;
    notifyListeners();
  }

  void _applySaved(String type, int mediaId, Map<String, dynamic> saved) {
    _updateEntry(type, mediaId, (e) => {
          ...e,
          if (saved['progress'] != null) 'progress': saved['progress'],
          if (saved['score'] != null) 'score': saved['score'],
        });
    final status = saved['status'];
    if (status is String) _moveToStatus(type, mediaId, status);
  }

  void _moveToStatus(String type, int mediaId, String status) {
    final lists = _lists[type];
    if (lists == null) return;
    final current = lists.entries
        .where((list) =>
            !list.key.startsWith(customListPrefix) &&
            list.value.any((e) => _mediaIdOf(e) == mediaId))
        .map((list) => list.key)
        .firstOrNull;
    if (current == null || current == status) return;
    final entry = lists[current]!.firstWhere((e) => _mediaIdOf(e) == mediaId);
    _lists[type] = {
      ...lists,
      current: [for (final e in lists[current]!) if (_mediaIdOf(e) != mediaId) e],
      status: [entry, ...?lists[status]],
    };
  }

  void _updateEntry(
    String type,
    int mediaId,
    Map<String, dynamic> Function(Map<String, dynamic> entry) update,
  ) {
    final lists = _lists[type];
    if (lists == null) return;
    _lists[type] = {
      for (final MapEntry(:key, :value) in lists.entries)
        key: [for (final e in value) _mediaIdOf(e) == mediaId ? update(e) : e],
    };
  }

  Map<String, dynamic>? _findEntry(String type, int mediaId) {
    for (final list in _lists[type]?.values ?? const <List<Map<String, dynamic>>>[]) {
      for (final entry in list) {
        if (_mediaIdOf(entry) == mediaId) return entry;
      }
    }
    return null;
  }

  void _persist(String type) {
    final userId = _userId;
    final lists = _lists[type];
    if (userId == null || lists == null) return;
    unawaited(_cache.write(_cacheKey(userId, type), lists).onError<Exception>(
          (e, _) => debugPrint('[MediaListStore] Caching $type failed: $e'),
        ));
  }

  Future<MediaLists> _fetch(String type, int userId, String token) async {
    final raw = type == 'ANIME'
        ? await _service.getUserAnimeList(userId, token)
        : await _service.getUserMangaList(userId, token);
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        key: [for (final e in value) e as Map<String, dynamic>],
    };
  }

  static String _cacheKey(int userId, String type) =>
      ApiCache.userKey(userId, 'list:$type');

  static MediaLists _decodeLists(Object? json) => {
        for (final MapEntry(:key, :value) in (json as Map).entries)
          key as String: [for (final e in value as List) e as Map<String, dynamic>],
      };

  static int? _mediaIdOf(Map<String, dynamic> entry) =>
      (entry['media'] as Map?)?['id'] as int? ?? entry['mediaId'] as int?;
}
