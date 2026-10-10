import 'dart:convert';
import 'dart:math';

/// URL scheme AniList redirects back to after the login page.
const oauthCallbackScheme = 'anispark';
const oauthRedirectUri = '$oauthCallbackScheme://callback';
const _callbackHost = 'callback';
const _maxTokenLength = 8192;

/// Outcome of the redirect AniList sends back after its login page.
sealed class OAuthCallbackResult {
  const OAuthCallbackResult();
}

final class OAuthTokenReceived extends OAuthCallbackResult {
  const OAuthTokenReceived(this.accessToken);
  final String accessToken;
}

final class OAuthCodeReceived extends OAuthCallbackResult {
  const OAuthCodeReceived(this.code);
  final String code;
}

final class OAuthCancelled extends OAuthCallbackResult {
  const OAuthCancelled();
}

final class OAuthFailed extends OAuthCallbackResult {
  const OAuthFailed(this.reason);
  final String reason;
}

/// A random value sent with the login request. A callback carrying a
/// different value didn't come from this login attempt.
String generateOAuthState() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Parses AniList's OAuth redirect: an implicit-grant token in the URL
/// fragment, or an authorization code in the query string.
///
/// A `state` that doesn't match [expectedState] is rejected. AniList doesn't
/// document echoing `state` back, so a callback without one is accepted.
OAuthCallbackResult parseOAuthCallback(
  String callbackUrl, {
  required String expectedState,
}) {
  final uri = Uri.tryParse(callbackUrl);
  if (uri == null || uri.scheme != oauthCallbackScheme || uri.host != _callbackHost) {
    return const OAuthFailed('unexpected_callback');
  }
  final params = _callbackParams(uri);
  if (params == null) return const OAuthFailed('malformed_callback');

  final state = params['state'];
  if (state != null && state != expectedState) return const OAuthFailed('state_mismatch');

  final error = params['error'];
  if (error != null) {
    return error == 'access_denied' ? const OAuthCancelled() : OAuthFailed(error);
  }
  final token = params['access_token'];
  if (token != null) {
    return _isPlausibleToken(token) ? OAuthTokenReceived(token) : const OAuthFailed('invalid_token');
  }
  final code = params['code'];
  if (code != null && code.isNotEmpty) return OAuthCodeReceived(code);
  return const OAuthFailed('missing_credentials');
}

Map<String, String>? _callbackParams(Uri uri) {
  try {
    return {
      ...uri.queryParameters,
      if (uri.fragment.isNotEmpty) ...Uri.splitQueryString(uri.fragment),
    };
  } on FormatException {
    return null;
  } on ArgumentError {
    // Thrown for invalid percent-encoding.
    return null;
  }
}

bool _isPlausibleToken(String token) =>
    token.isNotEmpty && token.length <= _maxTokenLength && !RegExp(r'\s').hasMatch(token);
