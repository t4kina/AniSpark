import 'package:anispark/services/oauth_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'header.payload.signature';

  group('anilistAuthorizeUri', () {
    test('asks for an implicit-grant token with exactly the documented parameters', () {
      final uri = anilistAuthorizeUri(clientId: '37324', implicit: true);

      expect(uri.scheme, 'https');
      expect(uri.host, 'anilist.co');
      expect(uri.path, '/api/v2/oauth/authorize');
      // AniList answers unsupported_grant_type when redirect_uri is added and
      // its page breaks with state, so nothing else may be sent.
      expect(uri.queryParameters, {'client_id': '37324', 'response_type': 'token'});
    });

    test('asks for an authorization code with the registered redirect URI', () {
      final uri = anilistAuthorizeUri(clientId: '37324', implicit: false);

      expect(uri.queryParameters, {
        'client_id': '37324',
        'redirect_uri': 'anispark://callback',
        'response_type': 'code',
      });
    });
  });

  group('parseOAuthCallback', () {
    test('reads an implicit-grant token from the URL fragment', () {
      final result = parseOAuthCallback(
        'anispark://callback#access_token=$token&token_type=Bearer&expires_in=31536000',
      );

      expect(result, isA<OAuthTokenReceived>().having((r) => r.accessToken, 'accessToken', token));
    });

    test('reads an authorization code from the query string', () {
      final result = parseOAuthCallback('anispark://callback?code=abc123');

      expect(result, isA<OAuthCodeReceived>().having((r) => r.code, 'code', 'abc123'));
    });

    test('rejects a callback carrying a state, which this app never sends', () {
      final result = parseOAuthCallback('anispark://callback#access_token=$token&state=forged');

      expect(result, isA<OAuthFailed>().having((r) => r.reason, 'reason', 'unexpected_state'));
    });

    test('treats access_denied as a cancellation', () {
      expect(parseOAuthCallback('anispark://callback?error=access_denied'), isA<OAuthCancelled>());
    });

    test('reports other OAuth errors', () {
      expect(
        parseOAuthCallback('anispark://callback?error=server_error'),
        isA<OAuthFailed>().having((r) => r.reason, 'reason', 'server_error'),
      );
    });

    test('rejects callbacks for another scheme or host', () {
      expect(parseOAuthCallback('https://evil.example/callback#access_token=$token'), isA<OAuthFailed>());
      expect(parseOAuthCallback('anispark://other#access_token=$token'), isA<OAuthFailed>());
    });

    test('rejects malformed tokens', () {
      expect(parseOAuthCallback('anispark://callback#access_token='), isA<OAuthFailed>());
      expect(parseOAuthCallback('anispark://callback#access_token=has%20space'), isA<OAuthFailed>());
    });

    test('fails when the callback carries neither token nor code', () {
      expect(parseOAuthCallback('anispark://callback'), isA<OAuthFailed>());
    });
  });
}
