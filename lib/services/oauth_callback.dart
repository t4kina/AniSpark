/// URL scheme AniList redirects back to after the login page.
const oauthCallbackScheme = 'anispark';
const oauthRedirectUri = '$oauthCallbackScheme://callback';
const _callbackHost = 'callback';
const _maxTokenLength = 8192;

/// AniList's login page for [clientId].
///
/// The implicit grant (the token comes back in the URL fragment) carries
/// only `client_id` and `response_type`, exactly as AniList documents it:
/// adding `redirect_uri` makes AniList answer `unsupported_grant_type`, and
/// `state` breaks its approval page. AniList then redirects to the URL
/// registered for the client ([oauthRedirectUri]). The authorization-code
/// grant sends the redirect URI, which AniList requires there.
Uri anilistAuthorizeUri({required String clientId, required bool implicit}) => Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: implicit
          ? {'client_id': clientId, 'response_type': 'token'}
          : {'client_id': clientId, 'redirect_uri': oauthRedirectUri, 'response_type': 'code'},
    );

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

/// Parses AniList's OAuth redirect: an implicit-grant token in the URL
/// fragment, or an authorization code in the query string.
///
/// The login request never carries a `state` (AniList doesn't accept one),
/// so a callback with one didn't come from this app's login and is
/// rejected.
OAuthCallbackResult parseOAuthCallback(String callbackUrl) {
  final uri = Uri.tryParse(callbackUrl);
  if (uri == null || uri.scheme != oauthCallbackScheme || uri.host != _callbackHost) {
    return const OAuthFailed('unexpected_callback');
  }
  final params = _callbackParams(uri);
  if (params == null) return const OAuthFailed('malformed_callback');
  if (params.containsKey('state')) return const OAuthFailed('unexpected_state');

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
