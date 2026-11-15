import 'dart:async';

import 'package:anispark/screens/login_gate_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/app_logo.dart';
import 'package:anispark/widgets/motion/staggered_entrance.dart';
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
    // The text and the button cascade in under the logo.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
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

  group('arriving from the splash', () {
    /// A stand-in for the splash: the big logo, then the login screen
    /// replaces it with the same fade the app uses.
    Future<void> pumpSplash(WidgetTester tester, {bool reduceMotion = false}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      auth = _GatedAuth();
      await tester.pumpWidget(appWith(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushReplacement(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, _, _) => const LoginGateScreen(),
                      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
                      transitionDuration: const Duration(milliseconds: 500),
                    ),
                  ),
                  child: const AppLogo(size: 140),
                ),
              ),
            ),
          ),
        ),
        cache: ApiCache(MemoryCacheStore()),
        auth: auth,
      ));
    }

    testWidgets('it is one logo that shrinks into its place on the login screen', (tester) async {
      await pumpSplash(tester);
      expect(tester.getSize(find.byType(AppLogo)), const Size.square(140));

      await tester.tap(find.byType(AppLogo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
      // Mid-flight: one logo on screen, between the two sizes.
      final flying = tester.getSize(find.byType(Image).last).width;
      expect(flying, inExclusiveRange(LoginGateScreen.logoSize, 140));

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppLogo), findsOneWidget);
      expect(tester.getSize(find.byType(AppLogo)), const Size.square(LoginGateScreen.logoSize));
      expect(tester.getCenter(find.byType(AppLogo)).dx, 200);
    });

    testWidgets('the words and the button come in after the logo, the title first', (tester) async {
      await pumpSplash(tester);
      await tester.tap(find.byType(AppLogo));
      await tester.pump();
      await tester.pump();

      int step(Finder content) => tester
          .widget<StaggeredEntrance>(find.ancestor(of: content, matching: find.byType(StaggeredEntrance)).first)
          .index;
      expect(step(find.text('Connect your AniList')), greaterThan(0));
      expect(step(button), greaterThan(step(find.text('Connect your AniList'))));
      expect(find.ancestor(of: find.byType(AppLogo), matching: find.byType(StaggeredEntrance)), findsNothing,
          reason: 'the logo travels, it does not fade in');

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('with motion reduced the login screen simply replaces the splash', (tester) async {
      await pumpSplash(tester, reduceMotion: true);
      expect(find.byType(Hero), findsNothing);
    });
  });
}
