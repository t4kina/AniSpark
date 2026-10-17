import 'package:flutter/foundation.dart';

import '../utils/refresh_notifier.dart' show authExpiredNotifier;
import 'auth_service.dart';

/// Logs [auth] out when AniList rejects the token it is using now, then
/// calls [onExpired] (e.g. to tell the user). A 401 for any other token —
/// a late response to a request made before switching accounts — is
/// ignored, and requests rejected together cause a single logout.
///
/// Returns a function that stops watching.
VoidCallback watchSessionExpiry(AuthService auth, {required VoidCallback onExpired}) {
  var loggingOut = false;

  Future<void> onRejected() async {
    // Read synchronously: the rejected token is only set during the
    // notification.
    final rejected = authExpiredNotifier.rejectedToken;
    if (loggingOut || !auth.isLoggedIn || rejected == null || rejected != auth.token) return;
    loggingOut = true;
    try {
      await auth.logout();
      onExpired();
    } finally {
      loggingOut = false;
    }
  }

  authExpiredNotifier.addListener(onRejected);
  return () => authExpiredNotifier.removeListener(onRejected);
}
