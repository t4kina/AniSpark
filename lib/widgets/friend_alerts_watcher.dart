import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/friend_alerts.dart';
import '../services/notification_service.dart';

/// Looks for what the friends whose bell is on have done when the app
/// opens and each time it comes back to the front, and notifies about it.
class FriendAlertsWatcher extends StatefulWidget {
  const FriendAlertsWatcher({super.key, required this.child, this.checker});

  final Widget child;

  /// Injected by tests; a default one is created otherwise.
  final FriendAlertsChecker? checker;

  /// No new look sooner than this after the last one.
  static const minGap = Duration(minutes: 2);

  @override
  State<FriendAlertsWatcher> createState() => _FriendAlertsWatcherState();
}

class _FriendAlertsWatcherState extends State<FriendAlertsWatcher> with WidgetsBindingObserver {
  late final FriendAlertsChecker _checker = widget.checker ?? FriendAlertsChecker();
  DateTime? _lastLook;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_look()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_look());
  }

  Future<void> _look() async {
    if (!mounted || _looking) return;
    final now = DateTime.now();
    final last = _lastLook;
    if (last != null && now.difference(last) < FriendAlertsWatcher.minGap) return;
    final store = context.read<FriendAlertsStore?>();
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (store == null || !auth.isLoggedIn || token == null || store.watches.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    _looking = true;
    _lastLook = now;
    try {
      final fresh = await _checker.newActivities(store, token: token);
      await NotificationService().showFriendAlerts(fresh, settings);
    } on Exception catch (e) {
      debugPrint('[FriendAlerts] Looking for friend activity failed: $e');
    } finally {
      _looking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
