import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'web_bridge.dart';

class AuthService extends ChangeNotifier {
  static const _clientId =
      String.fromEnvironment('ANILIST_CLIENT_ID');
  static const _clientSecret =
      String.fromEnvironment('ANILIST_CLIENT_SECRET');
  static const _webRedirectUri =
      String.fromEnvironment('WEB_REDIRECT_URI', defaultValue: 'http://localhost:5000/');
  static const _mobileRedirectUri = 'anispark://callback';
  static String get _redirectUri =>
      kIsWeb ? _webRedirectUri : _mobileRedirectUri;
  static const _tokenUrl = 'https://anilist.co/api/v2/oauth/token';
  static const _baseUrl = 'https://graphql.anilist.co';

  String? _token;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _profileExtras;
  late Box _box;
  bool _loggingOut = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get profileExtras => _profileExtras;
  bool get isLoggedIn => _token != null;

  Future<void> init() async {
    _box = await Hive.openBox('auth');
    _token = _box.get('token');
    // Show the last known profile right away; fetchUser() refreshes it.
    if (_token != null) _user = _readCachedMap('user');
    _profileExtras = _readCachedMap('profileExtras');

    if (kIsWeb) {
      final fragment = Uri.base.fragment;
      if (fragment.isNotEmpty) {
        final params = Uri.splitQueryString(fragment);
        final token = params['access_token'];
        if (token != null) {
          webClearUrlParams();
          _token = token;
          await _box.put('token', _token);
          await fetchUser();
          notifyListeners();
          return;
        }
      }
    }

    if (_token != null) {
      notifyListeners();
      fetchUser();
    }
  }

  /// Reads a JSON map saved under [key]; corrupted data reads as null rather
  /// than crashing startup.
  Map<String, dynamic>? _readCachedMap(String key) {
    final raw = _box.get(key);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveProfileExtras(Map<String, dynamic> data) async {
    _profileExtras = data;
    await _box.put('profileExtras', jsonEncode(data));
  }

  Future<void> login() async {
    if (kIsWeb) {
      await _loginWeb();
    } else {
      await _loginMobile();
    }
  }

  // Web: implicit flow — token returned directly in URL fragment, no backend needed
  Future<void> _loginWeb() async {
    final authUrl = Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': _webRedirectUri,
        'response_type': 'token',
      },
    ).toString();

    webRedirectTo(authUrl);
  }

  Future<void> _exchangeCodeForToken(String code, String redirectUri, String tokenUrl) async {
    final tokenResponse = await http.post(
      Uri.parse(tokenUrl),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'redirect_uri': redirectUri,
        'code': code,
      }),
    );

    if (tokenResponse.statusCode == 200) {
      _token = jsonDecode(tokenResponse.body)['access_token'];
      await _box.put('token', _token);
      await fetchUser();
      notifyListeners();
    } else {
      throw Exception('Token exchange failed: ${tokenResponse.body}');
    }
  }

  // Mobile: authorization code flow
  Future<void> _loginMobile() async {
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

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'anispark',
      );
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('CANCELED') || msg.contains('cancel') || msg.contains('error 1')) return;
      rethrow;
    }

    // Extract code
    String? code;
    if (result.contains('?')) {
      code = Uri.parse(result).queryParameters['code'];
    } else if (result.contains('code=')) {
      code = Uri.splitQueryString(result.split('?').last)['code'];
    }
    if (code == null) throw Exception('No code in: $result');

    await _exchangeCodeForToken(code, _mobileRedirectUri, _tokenUrl);
  }

  Future<void> fetchUser() async {
    final requestToken = _token;
    const query = '''
      query {
        Viewer {
          id name avatar { large } bannerImage
          statistics {
            anime {
              count episodesWatched meanScore minutesWatched
              genres { genre count meanScore minutesWatched }
              scores { score count }
              releaseYears { releaseYear count meanScore }
            }
            manga {
              count chaptersRead volumesRead meanScore
              genres { genre count meanScore }
              scores { score count }
              releaseYears { releaseYear count meanScore }
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
      // Ignore a response that arrives after logout or an account switch.
      if (data['data'] != null && _token != null && _token == requestToken) {
        _user = data['data']['Viewer'];
        notifyListeners();
        await _box.put('user', jsonEncode(_user));
      }
    }
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _token = null;
    _user = null;
    _profileExtras = null;
    await _box.delete('token');
    await _box.delete('user');
    await _box.delete('profileExtras');
    _loggingOut = false;
    notifyListeners();
  }
}