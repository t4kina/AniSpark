import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/settings_provider.dart';
import 'auth_service.dart';

/// Keeps the Android home-screen widget in step with the app: whose list it
/// shows (the logged-in AniList user, or what's popular when logged out) and
/// the accent colour. The widget fetches the episodes itself
/// (UpNextWidget.kt). The iOS widget is set up from its own settings, since
/// a free Apple ID can't share data between the app and a widget.
class HomeWidgets {
  static const channel = MethodChannel('anispark/widgets');

  // What the widget was last told, so unrelated changes say nothing.
  (String?, int)? _sent;

  Future<void> sync({required String? userName, required Color accent}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final next = (userName, accent.toARGB32());
    if (next == _sent) return;
    _sent = next;
    try {
      await channel.invokeMethod<void>('configure', {'user': userName, 'accent': next.$2});
    } on PlatformException catch (e) {
      debugPrint('[HomeWidgets] Updating the widget failed: $e');
    } on MissingPluginException catch (e) {
      debugPrint('[HomeWidgets] Updating the widget failed: $e');
    }
  }
}

/// Tells the widget about the session and accent now and whenever they
/// change.
void syncHomeWidgets(AuthService auth, SettingsProvider settings, {HomeWidgets? widgets}) {
  final target = widgets ?? HomeWidgets();
  void sync() {
    final name = auth.user?['name'] as String?;
    unawaited(target.sync(userName: auth.isLoggedIn ? name : null, accent: settings.accentColor));
  }

  auth.addListener(sync);
  settings.addListener(sync);
  sync();
}
