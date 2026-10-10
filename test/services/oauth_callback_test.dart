import 'package:anispark/services/oauth_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const state = 'expected-state';
  const token = 'header.payload.signature';

  group('parseOAuthCallback', () {
    test('reads an implicit-grant token from the URL fragment', () {
      final result = parseOAuthCallback(
        'anispark://callback#access_token=$token&token_type=Bearer&expires_in=31536000&state=$state',
        expectedState: state,
      );

      expect(result, isA<OAuthTokenReceived>().having((r) => r.accessToken, 'accessToken', token));
    });

    test('reads an authorization code from the query string', () {
      final result = parseOAuthCallback(
        'anispark://callback?code=abc123&state=$state',
        expectedState: state,
      );

      expect(result, isA<OAuthCodeReceived>().having((r) => r.code, 'code', 'abc123'));
    });

    test('rejects a callback whose state does not match', () {
      final result = parseOAuthCallback(
        'anispark://callback#access_token=$token&state=forged',
        expectedState: state,
      );

      expect(result, isA<OAuthFailed>().having((r) => r.reason, 'reason', 'state_mismatch'));
    });

    test('accepts a callback without state, since AniList does not document echoing it', () {
      final result = parseOAuthCallback(
        'anispark://callback#access_token=$token',
        expectedState: state,
      );

      expect(result, isA<OAuthTokenReceived>());
    });

    test('rejects a callback without state once AniList is known to echo it', () {
      final result = parseOAuthCallback(
        'anispark://callback#access_token=$token',
        expectedState: state,
        requireState: true,
      );

      expect(result, isA<OAuthFailed>().having((r) => r.reason, 'reason', 'missing_state'));
    });

    test('reports whether the callback echoed the state', () {
      final echoed = parseOAuthCallback(
        'anispark://callback#access_token=$token&state=$state',
        expectedState: state,
      );
      final notEchoed = parseOAuthCallback(
        'anispark://callback?code=abc',
        expectedState: state,
      );

      expect(echoed, isA<OAuthTokenReceived>().having((r) => r.stateEchoed, 'stateEchoed', isTrue));
      expect(notEchoed, isA<OAuthCodeReceived>().having((r) => r.stateEchoed, 'stateEchoed', isFalse));
    });

    test('treats access_denied as a cancellation', () {
      final result = parseOAuthCallback(
        'anispark://callback?error=access_denied&state=$state',
        expectedState: state,
      );

      expect(result, isA<OAuthCancelled>());
    });

    test('reports other OAuth errors', () {
      final result = parseOAuthCallback(
        'anispark://callback?error=server_error&state=$state',
        expectedState: state,
      );

      expect(result, isA<OAuthFailed>().having((r) => r.reason, 'reason', 'server_error'));
    });

    test('rejects callbacks for another scheme or host', () {
      expect(
        parseOAuthCallback('https://evil.example/callback#access_token=$token', expectedState: state),
        isA<OAuthFailed>(),
      );
      expect(
        parseOAuthCallback('anispark://other#access_token=$token', expectedState: state),
        isA<OAuthFailed>(),
      );
    });

    test('rejects malformed tokens', () {
      expect(
        parseOAuthCallback('anispark://callback#access_token=', expectedState: state),
        isA<OAuthFailed>(),
      );
      expect(
        parseOAuthCallback('anispark://callback#access_token=has%20space', expectedState: state),
        isA<OAuthFailed>(),
      );
    });

    test('fails when the callback carries neither token nor code', () {
      expect(
        parseOAuthCallback('anispark://callback?state=$state', expectedState: state),
        isA<OAuthFailed>(),
      );
    });
  });

  test('generateOAuthState returns unpredictable URL-safe values', () {
    final a = generateOAuthState();
    final b = generateOAuthState();

    expect(a, isNot(b));
    expect(a.length, greaterThanOrEqualTo(32));
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(a), isTrue);
  });
}
