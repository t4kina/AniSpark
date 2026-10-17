import 'package:flutter/foundation.dart' show immutable, setEquals;

import 'anilist_service.dart';

/// What a Discover row's "See all" grid lists: the row's own query (media
/// type, fixed filters and default sort) plus the filters the user picked on
/// top of it (sort, genres, formats and a minimum rating).
@immutable
class BrowseQuery {
  const BrowseQuery({
    required this.id,
    required this.type,
    required this.defaultSort,
    this.status,
    this.countryOfOrigin,
    this.formatNot,
    String? sort,
    this.genres = const {},
    this.formats = const {},
    this.minScore = 0,
  }) : sort = sort ?? defaultSort;

  static const anime = 'ANIME';
  static const manga = 'MANGA';

  /// The Discover rows, with the filters of the queries behind them (see
  /// `AniListService.getTrending` and the others).
  static const trending = BrowseQuery(id: 'trending', type: anime, defaultSort: 'TRENDING_DESC');
  static const topAiring =
      BrowseQuery(id: 'topAiring', type: anime, status: 'RELEASING', defaultSort: 'POPULARITY_DESC');
  static const trendingManga =
      BrowseQuery(id: 'trendingManga', type: manga, formatNot: 'NOVEL', defaultSort: 'TRENDING_DESC');
  static const topManga =
      BrowseQuery(id: 'topManga', type: manga, formatNot: 'NOVEL', defaultSort: 'SCORE_DESC');
  static const manhwa =
      BrowseQuery(id: 'manhwa', type: manga, countryOfOrigin: 'KR', defaultSort: 'POPULARITY_DESC');

  static const rows = [trending, topAiring, trendingManga, topManga, manhwa];

  /// Sort by newest start date (an AniList `MediaSort`).
  static const newestSort = 'START_DATE_DESC';

  /// A `FuzzyDateInt` (YYYYMMDD) before any real start date. AniList lists
  /// titles without a start date first when sorting by [newestSort]; asking
  /// for a later start date leaves them out.
  static const anyStartDate = 10000000;

  /// Names the row, e.g. for its cache key; unique among [rows].
  final String id;

  /// AniList `MediaType`: [anime] or [manga].
  final String type;

  /// The row's fixed filters: a `MediaStatus`, a country code and a
  /// `MediaFormat` to leave out.
  final String? status;
  final String? countryOfOrigin;
  final String? formatNot;

  /// The row's own order, an AniList `MediaSort`.
  final String defaultSort;

  /// The order picked by the user, an AniList `MediaSort`.
  final String sort;

  /// AniList genre names; titles must have every one of them.
  final Set<String> genres;

  /// AniList `MediaFormat`s; empty means any.
  final Set<String> formats;

  /// Lowest average score shown (0–100, as AniList reports it); 0 is any.
  final int minScore;

  bool get isManga => type == manga;

  /// Whether no user filter is set.
  bool get isDefault => sort == defaultSort && genres.isEmpty && formats.isEmpty && minScore == 0;

  /// This row without the user's filters.
  BrowseQuery get defaults => copyWith(sort: defaultSort, genres: const {}, formats: const {}, minScore: 0);

  /// The user's filters, e.g. `SCORE_DESC|Action+Drama|MOVIE|70`. Another
  /// filter set of the same row has another key.
  String get filterKey => [
        sort,
        (genres.toList()..sort()).join('+'),
        (formats.toList()..sort()).join('+'),
        minScore,
      ].join('|');

  BrowseQuery copyWith({String? sort, Set<String>? genres, Set<String>? formats, int? minScore}) => BrowseQuery(
        id: id,
        type: type,
        defaultSort: defaultSort,
        status: status,
        countryOfOrigin: countryOfOrigin,
        formatNot: formatNot,
        sort: sort ?? this.sort,
        genres: genres == null ? this.genres : Set.unmodifiable(genres),
        formats: formats == null ? this.formats : Set.unmodifiable(formats),
        minScore: minScore ?? this.minScore,
      );

  /// The GraphQL variables for [page], with only the filters that are set
  /// (AniList answers `format_in: null` with a 500). [today] bounds the
  /// [newestSort] to titles that have started.
  Map<String, Object> variables({required int page, required DateTime today}) {
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    return {
      'page': page,
      'perPage': BrowseApi.pageSize,
      'type': type,
      // Ties broken by id so pages don't overlap.
      'sort': [sort, if (sort != 'ID') 'ID'],
      'status': ?status,
      'countryOfOrigin': ?countryOfOrigin,
      'format_not': ?formatNot,
      if (genres.isNotEmpty) 'genre_in': genres.toList()..sort(),
      if (formats.isNotEmpty) 'format_in': formats.toList()..sort(),
      // AniList compares the unrounded score, so this also returns titles
      // shown one point lower; [BrowseApi.browse] drops those.
      if (minScore > 0) 'averageScore_greater': minScore - 1,
      if (sort == newestSort) ...{
        'startDate_greater': anyStartDate,
        'startDate_lesser': tomorrow.year * 10000 + tomorrow.month * 100 + tomorrow.day,
      },
    };
  }

  @override
  bool operator ==(Object other) =>
      other is BrowseQuery &&
      other.id == id &&
      other.type == type &&
      other.status == status &&
      other.countryOfOrigin == countryOfOrigin &&
      other.formatNot == formatNot &&
      other.defaultSort == defaultSort &&
      other.sort == sort &&
      setEquals(other.genres, genres) &&
      setEquals(other.formats, formats) &&
      other.minScore == minScore;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        status,
        countryOfOrigin,
        formatNot,
        defaultSort,
        sort,
        Object.hashAllUnordered(genres),
        Object.hashAllUnordered(formats),
        minScore,
      );

  @override
  String toString() => 'BrowseQuery($id, $type, $filterKey)';
}

/// One page of [BrowseApi.browse].
@immutable
class BrowsePage {
  const BrowsePage({required this.media, required this.hasNextPage});

  /// Reads a page saved with [toJson], leaving out malformed items. Throws a
  /// [FormatException] if [json] has another shape.
  factory BrowsePage.fromJson(Object? json) {
    if (json case {'media': final List<Object?> media, 'hasNextPage': final bool hasNextPage}) {
      return BrowsePage(
        media: List.unmodifiable([for (final item in media) ?_parseMedia(item)]),
        hasNextPage: hasNextPage,
      );
    }
    throw const FormatException('Unexpected cached browse page');
  }

  /// Each media as `{id, type, format, episodes, chapters, averageScore,
  /// title {romaji, english, native}, coverImage {large}}`, without the
  /// fields AniList left empty.
  final List<Map<String, dynamic>> media;
  final bool hasNextPage;

  Map<String, Object?> toJson() => {'media': media, 'hasNextPage': hasNextPage};
}

/// AniList query behind the Discover rows' "See all" grids.
class BrowseApi {
  /// [clock] replaces the current time, for tests.
  BrowseApi({AniListService? service, DateTime Function()? clock})
      : _service = service ?? AniListService(),
        _now = clock ?? DateTime.now;

  final AniListService _service;
  final DateTime Function() _now;

  static const pageSize = 30;

  static const browseMediaQuery = r'''
    query($page: Int, $perPage: Int, $type: MediaType, $sort: [MediaSort],
          $status: MediaStatus, $countryOfOrigin: CountryCode, $format_not: MediaFormat,
          $genre_in: [String], $format_in: [MediaFormat], $averageScore_greater: Int,
          $startDate_greater: FuzzyDateInt, $startDate_lesser: FuzzyDateInt) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { hasNextPage }
        media(type: $type, sort: $sort, status: $status, countryOfOrigin: $countryOfOrigin,
              format_not: $format_not, genre_in: $genre_in, format_in: $format_in,
              averageScore_greater: $averageScore_greater,
              startDate_greater: $startDate_greater, startDate_lesser: $startDate_lesser,
              isAdult: false) {
          id type format episodes chapters averageScore
          title { romaji english native }
          coverImage { large }
        }
      }
    }
  ''';

  /// Page [page] of [query]. Malformed items are left out, as are titles
  /// AniList scores below [BrowseQuery.minScore] once rounded the way it
  /// shows them; a page AniList returned empty ends the list. Adult titles
  /// are never listed. Throws [AniListRequestException] on HTTP errors and
  /// [FormatException] on an unexpected response.
  Future<BrowsePage> browse(BrowseQuery query, {int page = 1}) async {
    final data = await _service.request(browseMediaQuery, query.variables(page: page, today: _now()));
    final pageData = data['Page'];
    final media = pageData is Map ? pageData['media'] : null;
    if (media is! List) throw const FormatException('Unexpected browse response');
    final parsed = [for (final raw in media) ?_parseMedia(raw, type: query.type)];
    return BrowsePage(
      media: List.unmodifiable(parsed.where((item) => _meetsMinScore(item, query.minScore))),
      hasNextPage: media.isNotEmpty && _hasNextPage(pageData),
    );
  }

  static bool _meetsMinScore(Map<String, dynamic> media, int minScore) {
    if (minScore <= 0) return true;
    final score = media['averageScore'];
    return score is int && score >= minScore;
  }

  static bool _hasNextPage(Object? pageData) =>
      pageData is Map && pageData['pageInfo'] is Map && (pageData['pageInfo'] as Map)['hasNextPage'] == true;
}

/// A media of [browseMediaQuery] with only well-typed fields, or null without
/// an int id. [type] fills in a missing media type, which tells quick add
/// whether it's a manga.
Map<String, dynamic>? _parseMedia(Object? raw, {String? type}) {
  if (raw is! Map) return null;
  final id = raw['id'];
  if (id is! int) return null;
  final title = raw['title'];
  final cover = raw['coverImage'];
  final titles = <String, dynamic>{
    if (title is Map)
      for (final language in const ['romaji', 'english', 'native'])
        if (title[language] case final String name) language: name,
  };
  return {
    'id': id,
    'type': ?_string(raw['type']) ?? type,
    'format': ?_string(raw['format']),
    'episodes': ?_int(raw['episodes']),
    'chapters': ?_int(raw['chapters']),
    'averageScore': ?_int(raw['averageScore']),
    if (titles.isNotEmpty) 'title': titles,
    if (cover is Map && cover['large'] is String) 'coverImage': <String, dynamic>{'large': cover['large']},
  };
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;
