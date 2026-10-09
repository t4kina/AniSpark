import 'dart:io';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Text of the shared load error view (English `load_error`).
const loadErrorText = "Couldn't load the content";

/// Makes every HTTP request fail the way it does on a device without a
/// connection, and counts the attempts.
///
/// `AniListService` shares one HTTP client per isolate, so use a single
/// instance per test file and install it before the first screen is built.
class OfflineHttpOverrides extends HttpOverrides {
  int requests = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OfflineHttpClient(this);
}

class _OfflineHttpClient implements HttpClient {
  _OfflineHttpClient(this._overrides);

  final OfflineHttpOverrides _overrides;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    _overrides.requests++;
    throw const SocketException('No internet connection');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Wraps [screen] with the providers the app's screens read (logged out).
Widget screenApp(Widget screen, {required ApiCache cache}) => MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: screen),
    );
