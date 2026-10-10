import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'auth_storage.dart';
import 'oauth_callback.dart';
import 'secure_store.dart';
import 'web_bridge.dart';

/// A login attempt AniList didn't complete, e.g. a rejected callback.
class AuthException implements Exception {
  const AuthException(this.reason);

  final String reason;

  @override
  String toString() => 'AuthException: $reason';
}

class AuthService extends ChangeNotifier {
  AuthService({SecureStore secureStore = const DeviceSecureStore()})
      : _secureStore = secureStore;

  static const _clientId =
      String.fromEnvironment('ANILIST_CLIENT_ID');
  // Only used by the authorization-code fallback flow. The default implicit
  // flow keeps the client secret out of the app binary.
  static const _clientSecret =
      String.fromEnvironment('ANILIST_CLIENT_SECRET');
  // `implicit` (default; AniList's recommended flow for mobile apps, which
  // can't keep a client secret) or `code` (the previous flow, kept as a
  // fallback: build with --dart-define=ANILIST_OAUTH_FLOW=code).
  static const _oauthFlow =
      String.fromEnvironment('ANILIST_OAUTH_FLOW', defaultValue: 'implicit');
  static const _webRedirectUri =
      String.fromEnvironment('WEB_REDIRECT_URI', defaultValue: 'http://localhost:5000/');
  static const _tokenUrl = 'https://anilist.co/api/v2/oauth/token';
  static const _baseUrl = 'https://graphql.anilist.co';
  static const _requestTimeout = Duration(seconds: 20);

  final SecureStore _secureStore;
  late AuthStorage _storage;
  String? _token;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _profileExtras;
  bool _loggingOut = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get profileExtras => _profileExtras;
  bool get isLoggedIn => _token != null;

  /// Restores the session. With a [cipher] the session lives in the keystore
  /// and an encrypted box (migrating the old plaintext box); without one it
  /// stays in the plaintext box as before.
  Future<void> init({HiveCipher? cipher}) async {
    _storage = await AuthStorage.open(secure: _secureStore, cipher: cipher);
    _token = await _storage.readToken();
    // Show the last known profile right away; fetchUser() refreshes it.
    if (_token != null) _user = _storage.readMap('user');
    _profileExtras = _storage.readMap('profileExtras');

    if (kIsWeb) {
      final fragment = Uri.base.fragment;
      if (fragment.isNotEmpty) {
        final params = Uri.splitQueryString(fragment);
        final token = params['access_token'];
        if (token != null) {
          webClearUrlParams();
          await _startSession(token);
          return;
        }
      }
    }

    if (_token != null) {
      notifyListeners();
      unawaited(fetchUser());
    }
  }

  Future<void> saveProfileExtras(Map<String, dynamic> data) async {
    _profileExtras = data;
    await _storage.writeMap('profileExtras', data);
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

  // Mobile: implicit flow by default (token in the redirect's fragment), or
  // the authorization-code flow when built with ANILIST_OAUTH_FLOW=code.
  Future<void> _loginMobile() async {
    final state = generateOAuthState();
    final authUrl = Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': oauthRedirectUri,
        'response_type': _oauthFlow == 'code' ? 'code' : 'token',
        'state': state,
      },
    ).toString();

    final String callback;
    try {
      callback = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: oauthCallbackScheme,
      );
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('CANCELED') || msg.contains('cancel') || msg.contains('error 1')) return;
      rethrow;
    }

    switch (parseOAuthCallback(callback, expectedState: state)) {
      case OAuthTokenReceived(:final accessToken):
        await _startSession(accessToken);
      case OAuthCodeReceived(:final code):
        await _exchangeCodeForToken(code);
      case OAuthCancelled():
        return;
      case OAuthFailed(:final reason):
        throw AuthException(reason);
    }
  }

  Future<void> _exchangeCodeForToken(String code) async {
    final tokenResponse = await http
        .post(
          Uri.parse(_tokenUrl),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'grant_type': 'authorization_code',
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'redirect_uri': oauthRedirectUri,
            'code': code,
          }),
        )
        .timeout(_requestTimeout);

    if (tokenResponse.statusCode != 200) {
      debugPrint('[AuthService] Token exchange failed: ${tokenResponse.statusCode} ${tokenResponse.body}');
      throw const AuthException('token_exchange_failed');
    }
    final token = jsonDecode(tokenResponse.body)['access_token'];
    if (token is! String || token.isEmpty) {
      throw const AuthException('invalid_token_response');
    }
    await _startSession(token);
  }

  Future<void> _startSession(String token) async {
    _token = token;
    await _storage.writeToken(token);
    await fetchUser();
    notifyListeners();
  }

  Future<void> fetchUser() async {
    final requestToken = _token;
    if (requestToken == null) return;
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

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $requestToken',
            },
            body: jsonEncode({'query': query}),
          )
          .timeout(_requestTimeout);

      debugPrint('fetchUser status: ${response.statusCode}');
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final viewer = data['data']?['Viewer'];
      // Ignore a response that arrives after logout or an account switch.
      if (viewer is Map<String, dynamic> && _token != null && _token == requestToken) {
        _user = viewer;
        notifyListeners();
        await _storage.writeMap('user', viewer);
      }
    } on Exception catch (e) {
      // The cached profile stays on screen; the next launch retries.
      debugPrint('[AuthService] Fetching the profile failed: $e');
    }
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    _token = null;
    _user = null;
    _profileExtras = null;
    try {
      await _storage.clear();
    } finally {
      _loggingOut = false;
      notifyListeners();
    }
  }
}
