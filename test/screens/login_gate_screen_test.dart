import 'dart:async';

import 'package:anispark/screens/login_gate_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

/// Counts the login flows started and lets the test decide how each ends.
class _GatedAuth extends FakeAuthService {
  int logins = 0;
  Completer<void> flow = Completer<void>();

  @override
  Future<void> login() {
    logins++;
    return flow.future;
  }
}

void main() {
  late _GatedAuth auth;

  Future<void> pumpGate(WidgetTester tester) async {
    // Made inside the test: a completer from setUp would finish outside the
    // test's fake clock.
    auth = _GatedAuth();
    await tester.pumpWidget(appWith(const LoginGateScreen(), cache: ApiCache(MemoryCacheStore()), auth: auth));
    await tester.pump();
  }

  final button = find.text('Login with AniList');

  testWidgets('a tap starts the login and shows the wait in the button', (tester) async {
    await pumpGate(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.logins, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a second tap while AniList is opening does not start another flow', (tester) async {
    await pumpGate(tester);
    await tester.tap(button);
    await tester.pump();

    await tester.tap(button, warnIfMissed: false);
    await tester.pump();

    expect(auth.logins, 1);
  });

  testWidgets('a failed login says so and offers the button again', (tester) async {
    await pumpGate(tester);
    await tester.tap(button);
    await tester.pump();

    auth.flow.completeError(Exception('cancelled'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't log in. Please try again."), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    auth.flow = Completer<void>();
    await tester.tap(button);
    await tester.pump();
    expect(auth.logins, 2);
  });

  testWidgets('a login that goes through gives the button back', (tester) async {
    await pumpGate(tester);
    await tester.tap(button);
    await tester.pump();

    auth.flow.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}
