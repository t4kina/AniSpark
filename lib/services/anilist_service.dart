import 'dart:convert';
import 'package:http/http.dart' as http;

class AniListService {
  static const String _baseUrl = 'https://graphql.anilist.co';

  Future<Map<String, String>> _headers([String? token]) => Future.value({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

  Future<List<dynamic>> _query(String query,
      [Map<String, dynamic>? variables, String? token]) async {
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': variables ?? {}}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']['Page']['media'] ?? [];
    }
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

  Future<List<dynamic>> searchAnime(
    String search, {
    String? genre,
    String? format,
    String? status,
    String? sort,
    int? year,
  }) {
    final variables = <String, dynamic>{'search': search};
    if (genre != null) variables['genre'] = genre;
    if (format != null) variables['format'] = format;
    if (status != null) variables['status'] = status;
    if (year != null) variables['seasonYear'] = year;
    final sortValue = sort ?? 'SEARCH_MATCH';
    return _query('''
      query(\$search: String, \$genre: String, \$format: MediaFormat,
            \$status: MediaStatus, \$seasonYear: Int, \$sort: [MediaSort]) {
        Page(page: 1, perPage: 30) {
          media(search: \$search, type: ANIME,
                genre: \$genre, format: \$format,
                status: \$status, seasonYear: \$seasonYear, sort: \$sort) {
            id title { romaji english native }
            coverImage { large } episodes averageScore genres status
          }
        }
      }
    ''', {...variables, 'sort': [sortValue]});
  }

  Future<List<dynamic>> searchManga(
    String search, {
    String? genre,
    String? format,
    String? status,
    String? sort,
    int? year,
  }) {
    final variables = <String, dynamic>{'search': search};
    if (genre != null) variables['genre'] = genre;
    if (format != null) variables['format'] = format;
    if (status != null) variables['status'] = status;
    if (year != null) variables['seasonYear'] = year;
    final sortValue = sort ?? 'SEARCH_MATCH';
    return _query('''
      query(\$search: String, \$genre: String, \$format: MediaFormat,
            \$status: MediaStatus, \$seasonYear: Int, \$sort: [MediaSort]) {
        Page(page: 1, perPage: 30) {
          media(search: \$search, type: MANGA,
                genre: \$genre, format: \$format,
                status: \$status, seasonYear: \$seasonYear, sort: \$sort) {
            id title { romaji english native }
            coverImage { large } chapters averageScore genres status
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
            id status progress score(format: POINT_10_DECIMAL)
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'id': id}}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['Media'];
    }
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
              mediaId progress score(format: POINT_10)
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode != 200) return {};
    final lists =
        jsonDecode(response.body)['data']['MediaListCollection']['lists']
            as List;
    final Map<String, List<dynamic>> result = {};
    for (final list in lists) {
      result[list['status'] as String] =
          (list['entries'] as List).cast<Map<String, dynamic>>().toList();
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
              mediaId progress score(format: POINT_10)
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode != 200) return {};
    final lists =
        jsonDecode(response.body)['data']['MediaListCollection']['lists']
            as List;
    final Map<String, List<dynamic>> result = {};
    for (final list in lists) {
      result[list['status'] as String] =
          (list['entries'] as List).cast<Map<String, dynamic>>().toList();
    }
    return result;
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['Page']['activities'] ?? [];
    }
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return {'user': body['data']?['User'] ?? {}};
    }
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode != 200) return [];
    final body = jsonDecode(response.body);
    return (body['data']?['Page']?['following'] as List<dynamic>?) ?? [];
  }

  /// Fetches a public user profile (no token required).
  Future<Map<String, dynamic>?> getPublicUserProfile(int userId) async {
    const query = '''
      query(\$userId: Int!) {
        User(id: \$userId) {
          id name bannerImage
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body)['data']['User'] as Map<String, dynamic>?;
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query, 'variables': {'userId': userId}}),
    );
    if (response.statusCode != 200) return {};
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
  }) async {
    const mutation = '''
      mutation(\$mediaId: Int, \$status: MediaListStatus,
               \$progress: Int, \$score: Float) {
        SaveMediaListEntry(mediaId: \$mediaId, status: \$status,
                           progress: \$progress, score: \$score) {
          id status progress score
        }
      }
    ''';
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({
        'query': mutation,
        'variables': {
          'mediaId': mediaId,
          'status': status,
          'progress': progress,
          'score': score,
        },
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']?['SaveMediaListEntry'] != null;
    }
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({
        'query': mutation,
        'variables': {'id': entryId},
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data']?['DeleteMediaListEntry']?['deleted'] == true;
    }
    return false;
  }

  /// Returns a map of "YYYY-MM-DD" → activity count for the past year.
  Future<Map<String, int>> getUserActivityDays(
      int userId, String token) async {
    const query = '''
      query(\$userId: Int!, \$page: Int!) {
        Page(page: \$page, perPage: 50) {
          activities(userId: \$userId, sort: ID_DESC, type: ANIME_LIST) {
            ... on ListActivity { createdAt }
          }
        }
      }
    ''';
    final cutoff =
        DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch ~/
            1000;
    final Map<String, int> result = {};
    for (int page = 1; page <= 6; page++) {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: await _headers(token),
        body: jsonEncode(
            {'query': query, 'variables': {'userId': userId, 'page': page}}),
      );
      if (response.statusCode != 200) break;
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
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({
        'query': mutation,
        'variables': {'animeId': animeId},
      }),
    );
    return response.statusCode == 200;
  }
}
