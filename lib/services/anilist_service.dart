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
          id title { romaji english }
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
            id title { romaji english }
            coverImage { large } episodes averageScore genres
          }
        }
      }
    ''', {'season': season, 'seasonYear': year});
  }

  Future<List<dynamic>> getPopularAllTime() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(sort: POPULARITY_DESC, type: ANIME) {
          id title { romaji english }
          coverImage { large } episodes averageScore genres
        }
      }
    }
  ''');

  Future<List<dynamic>> getTopAiring() => _query('''
    query {
      Page(page: 1, perPage: 20) {
        media(status: RELEASING, sort: POPULARITY_DESC, type: ANIME) {
          id title { romaji english }
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
            id title { romaji english }
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
            id title { romaji english }
            coverImage { large } chapters averageScore genres status
          }
        }
      }
    ''', {...variables, 'sort': [sortValue]});
  }

  Future<Map<String, dynamic>?> getAnimeDetail(int id) async {
    const query = '''
      query(\$id: Int) {
        Media(id: \$id) {
          id title { romaji english }
          coverImage { large extraLarge } bannerImage
          episodes averageScore genres status
          format source
          description(asHtml: false)
          studios { nodes { name } }
          startDate { year month day }
          nextAiringEpisode { episode airingAt }
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
        }
      }
    ''';
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(),
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
      query(\$userId: Int) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists {
            name status isCustomList
            entries {
              mediaId progress score(format: POINT_10)
              media {
                id title { romaji english }
                coverImage { large }
                episodes averageScore genres
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
      query(\$userId: Int) {
        MediaListCollection(userId: \$userId, type: MANGA) {
          lists {
            name status isCustomList
            entries {
              mediaId progress score(format: POINT_10)
              media {
                id title { romaji english }
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

  Future<List<dynamic>> getActivityFeed(String token) async {
    const query = '''
      query {
        Page(page: 1, perPage: 30) {
          activities(isFollowing: true, sort: ID_DESC) {
            ... on ListActivity {
              id type status progress createdAt
              user { name avatar { large } }
              media { id title { romaji english } coverImage { large } type }
            }
            ... on TextActivity {
              id type text createdAt
              user { name avatar { large } }
            }
          }
        }
      }
    ''';
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: await _headers(token),
      body: jsonEncode({'query': query}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data']['Page']['activities'] ?? [];
    }
    return [];
  }

  /// Returns a map of AniList status → entry count for the user's anime list.
  Future<Map<String, int>> getUserListCounts(int userId, String token) async {
    const query = '''
      query(\$userId: Int) {
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
}
