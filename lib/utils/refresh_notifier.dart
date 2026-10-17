import 'package:flutter/foundation.dart';

/// Lightweight notifier to trigger background refreshes across screens.
/// Increment the value to notify listeners.
final profileRefreshNotifier = ValueNotifier<int>(0);
final listRefreshNotifier = ValueNotifier<int>(0);
final feedRefreshNotifier = ValueNotifier<int>(0);
final cacheSizeRefreshNotifier = ValueNotifier<int>(0);

/// Counts the requests AniList answered with 401 and tells listeners which
/// token it rejected, so only the session still using it is logged out —
/// a late response to a request made before switching accounts must not
/// end the new session.
class AuthExpiredNotifier extends ValueNotifier<int> {
  AuthExpiredNotifier() : super(0);

  String? _rejectedToken;

  /// The rejected token, only while listeners are being notified; it is
  /// forgotten right after so an old token isn't kept in memory.
  String? get rejectedToken => _rejectedToken;

  /// Records that AniList rejected [token] and notifies listeners.
  void report(String token) {
    _rejectedToken = token;
    try {
      value++;
    } finally {
      _rejectedToken = null;
    }
  }
}

/// Fired when AniList returns 401 for a request made with a token.
final authExpiredNotifier = AuthExpiredNotifier();

/// True while the app is waiting out a 429 rate-limit retry.
final rateLimitActiveNotifier = ValueNotifier<bool>(false);
