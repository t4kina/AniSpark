import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/refresh_notifier.dart' show authExpiredNotifier, rateLimitActiveNotifier;

class AniListService {
  static const String _baseUrl = 'https://graphql.anilist.co';

  Future<Map<String, String>> _headers([String? token]) => Future.value({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

  void _handle401(int statusCode) {
    if (statusCode == 401) authExpiredNotifier.value++;
  }

  static int _rateLimitCount = 0;

  // Sends a GraphQL request, retrying once after Retry-After seconds on 429.
  Future<http.Response> _post(String body, [String? token]) async {
    final headers = await _headers(token);
    var response = await http.post(Uri.parse(_baseUrl), headers: headers, body: body);
    if (response.statusCode == 429) {
      _rateLimitCount++;
      if (_rateLimitCount == 1) rateLimitActiveNotifier.value = true;
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      await Future.delayed(Duration(seconds: retryAfter));
      response = await http.post(Uri.parse(_baseUrl), headers: headers, body: body);
      _rateLimitCount--;
      if (_rateLimitCount == 0) rateLimitActiveNotifier.value = false;
    }
    return response;
  }

  Future<List<dynamic>> _query(String query,
      [Map<String, dynamic>? variables, String? token]) async {
    final response = await _post(
      jsonEncode({'query': query, 'variables': variables ?? {}}),
      token,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']['Page']['media'] ?? [];
    }
    _handle401(response.statusCode);
    return [];
  }

  static (String season, int year) _currentSeason() {
    final now = DateTime.now();
    final month = now.month;
    final year = now.year;
    final season = switch (month) {
      1 || 2 || 3 => 'WINTER',
      4 || 5 || 6 => 'SPRING',
      7 || 8 || 9 => 'SUMMER',
      _ => 'FALL',
    };
    return (season, year);
  }

  /// Returns airing episodes for this week that are on the user's CURRENT list.
  Future<List<dynamic>> getWeeklySchedule(String token) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final weekEnd = now + 7 * 86400;
    const query = '''
      query(\$from: Int!, \$to: Int!) {
        Page(perPage: 50) {
          airingSchedules(airingAt_greater: \$from, airingAt_lesser: \$to, sort: TIME) {
            airingAt episode
            media {
              id title { romaji english native }
              coverImage { large }
              mediaListEntry { status }
            }
          }
        }
      }
    ''';
    final response = await _post(
      jsonEncode({'query': query, 'variables': {'from': now, 'to': weekEnd}}),
      token,
    );
    if (response.statusCode != 200) return [];
    final schedules = jsonDecode(response.body)['data']?['Page']?['airingSchedules'] as List<dynamic>? ?? [];
    return schedules.where((s) {
      final entry = s['media']?['mediaListEntry'];
      return entry != null && entry['status'] == 'CURRENT';
    }).toList();
  }

  Future<List<dynamic>> getTrending() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(sort: TRENDING_DESC, type: ANIME) {
          id title { romaji english native }
          coverImage { large } episodes averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> getThisSeason() {
    final (season, year) = _currentSeason();
    return _query('''
      query(\$season: MediaSeason, \$seasonYear: Int) {
        Page(page: 1, perPage: 20) {
          media(season: \$season, seasonYear: \$seasonYear, type: ANIME, sort: POPULARITY_DESC) {
            id title { romaji english native }
            coverImage { large } episodes averageScore genres
          }
        }
      }
    ''', {'season': season, 'seasonYear': year});
  }

  static (String season, int year) _nextSeason() {
    final (current, year) = _currentSeason();
    return switch (current) {
      'WINTER' => ('SPRING', year),
      'SPRING' => ('SUMMER', year),
      'SUMMER' => ('FALL', year),
      _ => ('WINTER', year + 1), // FALL
    };
  }

  Future<List<dynamic>> getNextSeason() {
    final (season, year) = _nextSeason();
    return _query('''
      query(\$season: MediaSeason, \$seasonYear: Int) {
        Page(page: 1, perPage: 20) {
          media(season: \$season, seasonYear: \$seasonYear, type: ANIME, sort: POPULARITY_DESC) {
            id title { romaji english native }
            coverImage { large } episodes averageScore genres
          }
        }
      }
    ''', {'season': season, 'seasonYear': year});
  }

  Future<List<dynamic>> getTopAiring() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(status: RELEASING, sort: POPULARITY_DESC, type: ANIME) {
          id title { romaji english native }
          coverImage { large } episodes averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> getTrendingManga() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(sort: TRENDING_DESC, type: MANGA, format_not: NOVEL) {
          id title { romaji english native }
          coverImage { large } chapters averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> getTopManga() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(sort: SCORE_DESC, type: MANGA, format_not: NOVEL) {
          id title { romaji english native }
          coverImage { large } chapters averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> getManhwa() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(sort: POPULARITY_DESC, type: MANGA, countryOfOrigin: "KR") {
          id title { romaji english native }
          coverImage { large } chapters averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> searchAnime(
    String search, {
    List<String>? genres,
    String? sort,
  }) {
    final variables = <String, dynamic>{'search': search};
    if (genres != null && genres.isNotEmpty) variables['genres'] = genres;
    final sortValue = sort ?? 'SEARCH_MATCH';
    return _query('''
      query(\$search: String, \$genres: [String], \$sort: [MediaSort]) {
        Page(page: 1, perPage: 30) {
          media(search: \$search, type: ANIME,
                genre_in: \$genres, sort: \$sort) {
            id title { romaji english native }
            coverImage { large } bannerImage
            episodes averageScore genres status format
            description(asHtml: false)
          }
        }
      }
    ''', {...variables, 'sort': [sortValue]});
  }

  Future<List<dynamic>> searchManga(
    String search, {
    List<String>? genres,
    String? sort,
  }) {
    final variables = <String, dynamic>{'search': search};
    if (genres != null && genres.isNotEmpty) variables['genres'] = genres;
    final sortValue = sort ?? 'SEARCH_MATCH';
    return _query('''
      query(\$search: String, \$genres: [String], \$sort: [MediaSort]) {
        Page(page: 1, perPage: 30) {
          media(search: \$search, type: MANGA,
                genre_in: \$genres, sort: \$sort) {
            id title { romaji english native }
            coverImage { large } bannerImage
            chapters averageScore genres status format
            description(asHtml: false)
          }
        }
      }
    ''', {...variables, 'sort': [sortValue]});
  }

  Future<Map<String, dynamic>?> getAnimeDetail(int id, [String? token]) async {
    const query = '''
      query(\$id: Int) {
        Media(id: \$id) {
          id title { romaji english native }
          coverImage { large extraLarge } bannerImage
          episodes chapters averageScore popularity favourites trending
          genres status type format source duration synonyms
          description(asHtml: false)
          studios { nodes { name isAnimationStudio } }
          startDate { year month day }
          endDate { year month day }
          season seasonYear
          nextAiringEpisode { episode airingAt }
          rankings { rank type allTime season year }
          tags { name isMediaSpoiler }
          isFavourite
          mediaListEntry {
            id status progress score(format: POINT_10_DECIMAL) notes customLists
          }
          relations {
            edges {
              relationType
              node { id title { romaji english native } coverImage { large } type }
            }
          }
          characters(sort: ROLE, perPage: 12) {
            edges {
              role
              node { id name { full } image { medium } }
              voiceActors(language: JAPANESE) { id name { full } image { medium } }
            }
          }
          staff(perPage: 8) {
            edges {
              role
              node { id name { full } image { medium } }
            }
          }
          recommendations(perPage: 8) {
            nodes {
              rating
              mediaRecommendation {
                id title { romaji english native }
                coverImage { large }
              }
            }
          }
          trailer { id site }
          externalLinks { url site color icon type }
          streamingEpisodes { title thumbnail url site }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'id': id}}), token);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['Media'];
    }
    _handle401(response.statusCode);
    return null;
  }

  Future<Map<String, List<dynamic>>> getUserAnimeList(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists {
            name status isCustomList
            entries {
              id mediaId progress score(format: POINT_10) notes customLists
              media {
                id title { romaji english native }
                coverImage { large }
                episodes averageScore genres
                nextAiringEpisode { episode airingAt }
              }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) {
      _handle401(response.statusCode);
      throw Exception('HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final lists = body['data']?['MediaListCollection']?['lists'] as List?;
    if (lists == null) throw Exception('Unexpected response');
    final Map<String, List<dynamic>> result = {};
    for (final list in lists) {
      final key = list['isCustomList'] == true
          ? 'custom:${list['name']}'
          : list['status'] as String;
      result[key] = (list['entries'] as List).cast<Map<String, dynamic>>().toList();
    }
    return result;
  }

  Future<Map<String, List<dynamic>>> getUserMangaList(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        MediaListCollection(userId: \$userId, type: MANGA) {
          lists {
            name status isCustomList
            entries {
              id mediaId progress score(format: POINT_10) notes customLists
              media {
                id title { romaji english native }
                coverImage { large }
                chapters averageScore genres
              }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) {
      _handle401(response.statusCode);
      throw Exception('HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final lists = body['data']?['MediaListCollection']?['lists'] as List?;
    if (lists == null) throw Exception('Unexpected response');
    final Map<String, List<dynamic>> result = {};
    for (final list in lists) {
      final key = list['isCustomList'] == true
          ? 'custom:${list['name']}'
          : list['status'] as String;
      result[key] = (list['entries'] as List).cast<Map<String, dynamic>>().toList();
    }
    return result;
  }

  Future<List<String>> getCustomListNames(int userId, String type, String token) async {
    final query = '''
      query(\$userId: Int!) {
        MediaListCollection(userId: \$userId, type: $type) {
          lists { name isCustomList }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) return [];
    final lists = jsonDecode(response.body)['data']?['MediaListCollection']?['lists'] as List?;
    if (lists == null) return [];
    return lists
        .where((l) => l['isCustomList'] == true)
        .map<String>((l) => l['name'] as String)
        .toList();
  }

  Future<List<dynamic>> getActivityFeed(String token,
      {bool isFollowing = true, int? userId}) async {
    final variables = <String, dynamic>{
      'isFollowing': isFollowing,
      'userId': ?userId,
    };
    final userFilter = userId != null ? ', userId: \$userId' : '';
    final query = '''
      query(\$isFollowing: Boolean${userId != null ? ', \$userId: Int' : ''}) {
        Page(page: 1, perPage: 30) {
          activities(isFollowing: \$isFollowing$userFilter, sort: ID_DESC) {
            ... on ListActivity {
              id type status progress createdAt
              user { id name avatar { large } }
              media { id title { romaji english native } coverImage { large } type }
            }
            ... on TextActivity {
              id type text createdAt
              user { id name avatar { large } }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': variables}), token);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['Page']['activities'] ?? [];
    }
    _handle401(response.statusCode);
    return [];
  }

  /// Fetches user favourites (anime + characters) and bannerImage.
  Future<Map<String, dynamic>> getUserProfileStats(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        User(id: \$userId) {
          id name bannerImage
          favourites {
            anime(perPage: 25) {
              nodes { id title { romaji english native } coverImage { large } }
            }
            characters(perPage: 25) {
              nodes { id name { full } image { medium } }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return {'user': body['data']?['User'] ?? {}};
    }
    _handle401(response.statusCode);
    return {};
  }

  /// Fetches followers and following counts for the user.
  Future<Map<String, int>> getUserFollowCounts(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        followersPage: Page(page: 1, perPage: 1) {
          pageInfo { total }
          followers(userId: \$userId) { id }
        }
        followingPage: Page(page: 1, perPage: 1) {
          pageInfo { total }
          following(userId: \$userId) { id }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body)['data'];
      return {
        'followers':
            (data?['followersPage']?['pageInfo']?['total'] as num?)
                    ?.toInt() ??
                0,
        'following':
            (data?['followingPage']?['pageInfo']?['total'] as num?)
                    ?.toInt() ??
                0,
      };
    }
    _handle401(response.statusCode);
    return {'followers': 0, 'following': 0};
  }

  /// Returns the list of users that [userId] is following.
  Future<List<dynamic>> getFollowing(int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        Page(page: 1, perPage: 50) {
          following(userId: \$userId) {
            id name
            avatar { large }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return []; }
    final body = jsonDecode(response.body);
    return (body['data']?['Page']?['following'] as List<dynamic>?) ?? [];
  }

  /// Fetches a public user profile (no token required).
  Future<Map<String, List<dynamic>>> getPublicUserList(
      int userId, String type) async {
    const query = '''
      query(\$userId: Int!, \$type: MediaType!) {
        MediaListCollection(userId: \$userId, type: \$type) {
          lists {
            status isCustomList
            entries {
              progress score(format: POINT_10)
              media {
                id type
                title { romaji english }
                coverImage { medium }
                episodes chapters
              }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId, 'type': type}}));
    if (response.statusCode != 200) { _handle401(response.statusCode); return {}; }
    final raw = jsonDecode(response.body)['data']['MediaListCollection'];
    if (raw == null) return {};
    final lists = raw['lists'] as List;
    final Map<String, List<dynamic>> result = {};
    for (final list in lists) {
      if (list['isCustomList'] == true) continue;
      final status = list['status'] as String;
      result[status] = (list['entries'] as List).cast<Map<String, dynamic>>();
    }
    return result;
  }

  Future<Map<String, dynamic>?> getPublicUserProfile(int userId, {String? token}) async {
    const query = '''
      query(\$userId: Int!) {
        User(id: \$userId) {
          id name bannerImage
          isFollowing isFollower
          avatar { large }
          statistics {
            anime { count meanScore minutesWatched episodesWatched }
            manga { count chaptersRead meanScore }
          }
          favourites {
            anime(perPage: 10) {
              nodes { id title { romaji english native } coverImage { large } }
            }
            characters(perPage: 10) {
              nodes { id name { full } image { medium } }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return null; }
    return jsonDecode(response.body)['data']['User'] as Map<String, dynamic>?;
  }

  /// Follows or unfollows a user. Returns whether the user is now being followed.
  Future<bool> toggleFollow(int userId, String token) async {
    const mutation = '''
      mutation(\$userId: Int!) {
        ToggleFollow(userId: \$userId) {
          id isFollowing
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': mutation, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return false; }
    final data = jsonDecode(response.body)['data']?['ToggleFollow'];
    return data?['isFollowing'] == true;
  }

  /// Returns a map of AniList status → entry count for the user's anime list.
  Future<Map<String, int>> getUserListCounts(int userId, String token) async {
    const query = '''
      query(\$userId: Int!) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists {
            status
            entries { mediaId }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'userId': userId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return {}; }
    final lists =
        jsonDecode(response.body)['data']['MediaListCollection']['lists'] as List;
    return {
      for (final list in lists)
        list['status'] as String: (list['entries'] as List).length,
    };
  }

  Future<bool> saveListEntry({
    required int mediaId,
    required String status,
    required int progress,
    required double score,
    required String token,
    String? notes,
    List<String>? customLists,
  }) async {
    const mutation = '''
      mutation(\$mediaId: Int, \$status: MediaListStatus,
               \$progress: Int, \$score: Float, \$notes: String, \$customLists: [String]) {
        SaveMediaListEntry(mediaId: \$mediaId, status: \$status,
                           progress: \$progress, score: \$score, notes: \$notes,
                           customLists: \$customLists) {
          id status progress score notes customLists
        }
      }
    ''';
    final response = await _post(jsonEncode({
      'query': mutation,
      'variables': {
        'mediaId': mediaId, 'status': status, 'progress': progress,
        'score': score, 'notes': notes, 'customLists': customLists,
      },
    }), token);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']?['SaveMediaListEntry'] != null;
    }
    _handle401(response.statusCode);
    return false;
  }

  Future<bool> deleteListEntry({
    required int entryId,
    required String token,
  }) async {
    const mutation = '''
      mutation(\$id: Int) {
        DeleteMediaListEntry(id: \$id) {
          deleted
        }
      }
    ''';
    final response = await _post(jsonEncode({
      'query': mutation,
      'variables': {'id': entryId},
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']?['DeleteMediaListEntry']?['deleted'] == true;
    }
    _handle401(response.statusCode);
    return false;
  }

  /// Returns a map of "YYYY-MM-DD" → activity count for the past year.
  Future<Map<String, int>> getUserActivityDays(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!, \$page: Int!) {
        Page(page: \$page, perPage: 50) {
          activities(userId: \$userId, sort: ID_DESC) {
            ... on ListActivity { createdAt }
            ... on TextActivity { createdAt }
            ... on MessageActivity { createdAt }
          }
        }
      }
    ''';
    final cutoff =
        DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch ~/
            1000;
    final Map<String, int> result = {};
    for (int page = 1; page <= 6; page++) {
      final response = await _post(
        jsonEncode({'query': query, 'variables': {'userId': userId, 'page': page}}),
        token,
      );
      if (response.statusCode != 200) { _handle401(response.statusCode); break; }
      final activities = jsonDecode(response.body)['data']['Page']
          ['activities'] as List<dynamic>;
      if (activities.isEmpty) break;
      bool done = false;
      for (final act in activities) {
        final ts = act['createdAt'] as int?;
        if (ts == null) continue;
        if (ts < cutoff) { done = true; break; }
        final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        result[key] = (result[key] ?? 0) + 1;
      }
      if (done) break;
    }
    return result;
  }

  Future<Map<String, dynamic>?> getCharacterDetail(int id, [String? token]) async {
    const query = '''
      query(\$id: Int!) {
        Character(id: \$id) {
          id
          isFavourite
          name { full native alternative }
          image { large }
          description(asHtml: false)
          gender
          age
          bloodType
          dateOfBirth { year month day }
          media(perPage: 10, sort: POPULARITY_DESC) {
            nodes {
              id type
              title { romaji english }
              coverImage { medium }
            }
          }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': query, 'variables': {'id': id}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return null; }
    return jsonDecode(response.body)['data']['Character'] as Map<String, dynamic>?;
  }

  Future<bool> toggleCharacterFavourite({
    required int characterId,
    required String token,
  }) async {
    const mutation = '''
      mutation(\$characterId: Int) {
        ToggleFavourite(characterId: \$characterId) {
          characters { nodes { id } }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': mutation, 'variables': {'characterId': characterId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return false; }
    return true;
  }

  Future<bool> toggleFavourite({
    required int animeId,
    required String token,
  }) async {
    const mutation = '''
      mutation(\$animeId: Int) {
        ToggleFavourite(animeId: \$animeId) {
          anime { nodes { id } }
        }
      }
    ''';
    final response = await _post(jsonEncode({'query': mutation, 'variables': {'animeId': animeId}}), token);
    if (response.statusCode != 200) { _handle401(response.statusCode); return false; }
    return true;
  }
}
