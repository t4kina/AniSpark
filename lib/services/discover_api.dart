import 'anilist_service.dart';

/// One page of a season's anime from [DiscoverApi.seasonMedia].
class SeasonPage {
  const SeasonPage({required this.media, required this.hasNextPage});

  /// Reads a page saved with [toJson]; throws if [json] has another shape.
  factory SeasonPage.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return SeasonPage(
      media: [for (final item in map['media'] as List) item as Map<String, dynamic>],
      hasNextPage: map['hasNextPage'] as bool,
    );
  }

  final List<Map<String, dynamic>> media;
  final bool hasNextPage;

  Map<String, Object?> toJson() => {'media': media, 'hasNextPage': hasNextPage};
}

/// AniList queries behind the airing calendar and the season browser.
class DiscoverApi {
  DiscoverApi({AniListService? service}) : _service = service ?? AniListService();

  final AniListService _service;

  /// AniList's largest page size.
  static const schedulePageSize = 50;

  /// Safety cap on schedule pages (a week is usually 3–6 pages).
  static const maxSchedulePages = 20;

  static const seasonPageSize = 30;

  static const airingScheduleQuery = r'''
    query($page: Int, $perPage: Int, $from: Int, $to: Int, $withListStatus: Boolean!) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: [TIME]) {
          id airingAt episode
          media {
            id isAdult format
            title { romaji english native }
            coverImage { large }
            mediaListEntry @include(if: $withListStatus) { status }
          }
        }
      }
    }
  ''';

  static const seasonMediaQuery = r'''
    query($page: Int, $perPage: Int, $season: MediaSeason, $seasonYear: Int,
          $sort: [MediaSort], $formats: [MediaFormat]) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        media(season: $season, seasonYear: $seasonYear, type: ANIME, isAdult: false,
              sort: $sort, format_in: $formats) {
          id format episodes averageScore
          title { romaji english native }
          coverImage { large }
        }
      }
    }
  ''';

  /// Every episode airing in [from, to), in time order, fetching pages until
  /// AniList reports no more. With a [token] each media carries the user's
  /// `mediaListEntry { status }` (null when it's not on their list). Adult
  /// titles are left out. Throws [AniListRequestException] on HTTP errors and
  /// [FormatException] on an unexpected response.
  Future<List<Map<String, dynamic>>> airingSchedule({
    required DateTime from,
    required DateTime to,
    String? token,
  }) async {
    final episodes = <Map<String, dynamic>>[];
    for (var page = 1; page <= maxSchedulePages; page++) {
      final data = await _service.request(
        airingScheduleQuery,
        {
          'page': page,
          'perPage': schedulePageSize,
          // airingAt_greater is exclusive; include episodes airing at [from].
          'from': _epochSeconds(from) - 1,
          'to': _epochSeconds(to),
          'withListStatus': token != null,
        },
        token: token,
      );
      final pageData = data['Page'];
      final schedules = pageData is Map ? pageData['airingSchedules'] : null;
      if (schedules is! List) {
        throw const FormatException('Unexpected airing schedule response');
      }
      episodes.addAll(schedules.whereType<Map<String, dynamic>>().where(_isShown));
      if (schedules.isEmpty || !_hasNextPage(pageData)) break;
    }
    return List.unmodifiable(episodes);
  }

  /// The episodes airing in the next seven days (from [now]) of titles on the
  /// user's CURRENT list. Throws like [airingSchedule].
  Future<List<Map<String, dynamic>>> watchingThisWeek(String token, {DateTime? now}) async {
    final from = now ?? DateTime.now();
    final week = await airingSchedule(from: from, to: from.add(const Duration(days: 7)), token: token);
    return List.unmodifiable(week.where((schedule) {
      final entry = (schedule['media'] as Map)['mediaListEntry'];
      return entry is Map && entry['status'] == 'CURRENT';
    }));
  }

  /// Page [page] of the anime airing in [season] of [year] (`WINTER`…`FALL`),
  /// ordered by [sort] (an AniList `MediaSort`, ties broken by id so pages
  /// don't overlap) and limited to [formats] (`MediaFormat`s; empty = all).
  /// Adult titles are left out. Throws like [airingSchedule].
  Future<SeasonPage> seasonMedia({
    required String season,
    required int year,
    required String sort,
    Set<String> formats = const {},
    int page = 1,
  }) async {
    final data = await _service.request(seasonMediaQuery, {
      'page': page,
      'perPage': seasonPageSize,
      'season': season,
      'seasonYear': year,
      'sort': [sort, if (sort != 'ID') 'ID'],
      // AniList answers `format_in: null` with a 500, so only send a filter.
      if (formats.isNotEmpty) 'formats': formats.toList()..sort(),
    });
    final pageData = data['Page'];
    final media = pageData is Map ? pageData['media'] : null;
    if (media is! List) throw const FormatException('Unexpected season response');
    return SeasonPage(
      media: List.unmodifiable(media.whereType<Map<String, dynamic>>()),
      hasNextPage: _hasNextPage(pageData),
    );
  }

  static int _epochSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  static bool _hasNextPage(Object? pageData) =>
      pageData is Map &&
      pageData['pageInfo'] is Map &&
      (pageData['pageInfo'] as Map)['hasNextPage'] == true;

  static bool _isShown(Map<String, dynamic> schedule) {
    final media = schedule['media'];
    return media is Map && media['id'] is int && media['isAdult'] != true;
  }
}
