import 'dart:async';

import 'package:anispark/main.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

/// A session that the test starts and ends, and a login that stays pending
/// until the test finishes it.
class _SessionAuth extends AuthService {
  _SessionAuth({String? token}) : _token = token;

  String? _token;
  int logins = 0;
  Completer<void>? pendingLogin;

  @override
  String? get token => _token;

  @override
  bool get isLoggedIn => _token != null;

  @override
  Map<String, dynamic>? get user => null;

  void begin() {
    _token = 'tok';
    notifyListeners();
  }

  void end() {
    _token = null;
    notifyListeners();
  }

  @override
  Future<void> login() {
    logins++;
    return (pendingLogin = Completer<void>()).future;
  }
}

const _loginLabel = 'Login with AniList';

Widget _gate(_SessionAuth auth) => appWith(
      AuthGate(
        signedIn: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('a page on top'))),
              ),
              child: const Text('the tabs'),
            ),
          ),
        ),
      ),
      cache: ApiCache(MemoryCacheStore()),
      auth: auth,
    );

void main() {
  testWidgets('signed out, only the login screen shows (no tabs)', (tester) async {
    await tester.pumpWidget(_gate(_SessionAuth()));

    expect(find.text(_loginLabel), findsOneWidget);
    expect(find.text('the tabs'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the tabs replace the login screen once a session starts', (tester) async {
    final auth = _SessionAuth();
    await tester.pumpWidget(_gate(auth));

    auth.begin();
    await tester.pump();

    expect(find.text('the tabs'), findsOneWidget);
    expect(find.text(_loginLabel), findsNothing);
  });

  testWidgets('a session ending closes the pages opened on top of the tabs', (tester) async {
    final auth = _SessionAuth(token: 'tok');
    await tester.pumpWidget(_gate(auth));
    await tester.tap(find.text('the tabs'));
    await tester.pumpAndSettle();
    expect(find.text('a page on top'), findsOneWidget);

    auth.end();
    await tester.pumpAndSettle();

    expect(find.text('a page on top'), findsNothing);
    expect(find.text(_loginLabel), findsOneWidget);
  });

  testWidgets('a second tap while logging in does not start another login', (tester) async {
    final auth = _SessionAuth();
    await tester.pumpWidget(_gate(auth));

    await tester.tap(find.text(_loginLabel));
    await tester.pump();
    await tester.tap(find.text(_loginLabel));
    await tester.pump();
    expect(auth.logins, 1);

    auth.pendingLogin!.complete();
    await tester.pump();
    await tester.tap(find.text(_loginLabel));
    expect(auth.logins, 2, reason: 'usable again once the first attempt ended');
  });

  testWidgets('a failed login shows an error and can be retried', (tester) async {
    final auth = _SessionAuth();
    await tester.pumpWidget(_gate(auth));

    await tester.tap(find.text(_loginLabel));
    await tester.pump();
    auth.pendingLogin!.completeError(const AuthException('rejected'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.text(_loginLabel));
    expect(auth.logins, 2);
  });
}
