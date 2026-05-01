import 'package:flutter/foundation.dart';

/// Lightweight notifier to trigger background refreshes across screens.
/// Increment the value to notify listeners.
final profileRefreshNotifier = ValueNotifier<int>(0);
final listRefreshNotifier = ValueNotifier<int>(0);
final feedRefreshNotifier = ValueNotifier<int>(0);

/// Fired when the API returns 401 — listeners should log the user out.
final authExpiredNotifier = ValueNotifier<int>(0);
