import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService extends ChangeNotifier {
  static const _clientId =
      String.fromEnvironment('ANILIST_CLIENT_ID');
  static const _clientSecret =
      String.fromEnvironment('ANILIST_CLIENT_SECRET');
  static const _redirectUri = 'anispark://callback';
  static const _baseUrl = 'https://graphql.anilist.co';

  String? _token;
  Map<String, dynamic>? _user;
  late Box _box;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;

  Future<void> init() async {
    _box = await Hive.openBox('auth');
    _token = _box.get('token');
    if (_token != null) await fetchUser();
  }

  Future<void> login() async {
    // Step 1: Open authorization page (code flow)
    final authUrl = Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
      },
    ).toString();

    debugPrint('Opening OAuth URL: $authUrl');

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: 'anispark',
    );

    debugPrint('OAuth result: $result');

    // Step 2: Extract the code
    String? code;
    if (result.contains('?')) {
      final uri = Uri.parse(result);
      code = uri.queryParameters['code'];
    } else if (result.contains('code=')) {
      final params = Uri.splitQueryString(result.split('?').last);
      code = params['code'];
    }

    debugPrint('Code: ${code != null ? "found ✅" : "null ❌"}');

    if (code == null) throw Exception('No code in: $result');

    // Step 3: Exchange code for token
    final tokenResponse = await http.post(
      Uri.parse('https://anilist.co/api/v2/oauth/token'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'redirect_uri': _redirectUri,
        'code': code,
      }),
    );

    debugPrint('Token exchange status: ${tokenResponse.statusCode}');
    debugPrint('Token exchange body: ${tokenResponse.body}');

    if (tokenResponse.statusCode == 200) {
      final data = jsonDecode(tokenResponse.body);
      _token = data['access_token'];
      await _box.put('token', _token);
      await fetchUser();
      notifyListeners();
    } else {
      throw Exception('Token exchange failed: ${tokenResponse.body}');
    }
  }

  Future<void> fetchUser() async {
    const query = '''
      query {
        Viewer {
          id name avatar { large } bannerImage
          statistics {
            anime {
              count episodesWatched meanScore minutesWatched
              genres { genre count meanScore minutesWatched }
            }
            manga {
              count chaptersRead meanScore
              genres { genre count meanScore }
            }
          }
        }
      }
    ''';

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'query': query}),
    );

    debugPrint('fetchUser status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        _user = data['data']['Viewer'];
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _box.delete('token');
    notifyListeners();
  }
}