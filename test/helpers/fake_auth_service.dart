import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// An [AuthService] with a fixed session (logged out when [fakeToken] is
/// null), for screens that only read `token`, `user` and `isLoggedIn`.
class FakeAuthService extends AuthService {
  FakeAuthService({this.fakeToken, this.fakeUser});

  final String? fakeToken;
  final Map<String, dynamic>? fakeUser;

  @override
  String? get token => fakeToken;

  @override
  Map<String, dynamic>? get user => fakeUser;

  @override
  bool get isLoggedIn => fakeToken != null;
}

/// Wraps [screen] with the providers screens read, using [auth] (logged out
/// by default) and [settings] (defaults when omitted).
Widget appWith(Widget screen, {required ApiCache cache, AuthService? auth, SettingsProvider? settings}) =>
    MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>(create: (_) => auth ?? FakeAuthService()),
        if (settings != null)
          ChangeNotifierProvider.value(value: settings)
        else
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: screen),
    );
