import 'package:anispark/screens/settings_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:anispark/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

String _en(String key) => tr(key, 'English');

class _RecordingAuth extends FakeAuthService {
  _RecordingAuth() : super(fakeToken: 'token', fakeUser: {'id': 7, 'name': 'Faye'});

  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;
}

void main() {
  late _RecordingAuth auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _RecordingAuth();
  });

  /// Opens Settings on top of a first page, as the app does.
  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
            child: const Text('tabs'),
          ),
        ),
      ),
      cache: ApiCache(MemoryCacheStore()),
      auth: auth,
    ));
    await tester.tap(find.text('tabs'));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('logging out asks first, and cancelling keeps the session', (tester) async {
    await openSettings(tester);

    await tapRow(tester, _en('logout'));
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text(_en('logout_confirm')), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, _en('cancel')));
    await tester.pumpAndSettle();

    expect(auth.logouts, 0);
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('confirming logs out once and goes back to the first page', (tester) async {
    await openSettings(tester);

    await tapRow(tester, _en('logout'));
    await tester.tap(find.widgetWithText(AppButton, _en('logout')));
    await tester.pumpAndSettle();

    expect(auth.logouts, 1);
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('tabs'), findsOneWidget);
  });

  testWidgets('tapping outside the question keeps the session', (tester) async {
    await openSettings(tester);

    await tapRow(tester, _en('logout'));
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    expect(auth.logouts, 0);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('privacy is an app dialog that closes with its button', (tester) async {
    await openSettings(tester);

    await tapRow(tester, _en('privacy'));
    expect(find.descendant(of: find.byType(AppDialog), matching: find.text(_en('privacy_summary'))), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, _en('close')));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
  });

  testWidgets('about is an app dialog with the app name and what it is', (tester) async {
    await openSettings(tester);

    await tapRow(tester, _en('about_anispark'));
    final dialog = find.byType(AppDialog);
    expect(find.descendant(of: dialog, matching: find.text('AniSpark')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text(_en('about_description'))), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, _en('close')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('each setting has its icon on a tinted square: the accent, or red for logging out', (tester) async {
    await openSettings(tester);

    Color tintOf(IconData icon) {
      final square = tester.widget<Container>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)).first,
      );
      expect((square.decoration! as BoxDecoration).borderRadius, isNotNull);
      return tester.widget<Icon>(find.byIcon(icon)).color!;
    }

    final accent = Theme.of(tester.element(find.byType(SettingsScreen))).colorScheme.primary;
    expect(tintOf(Icons.language), accent);
    expect(tintOf(Icons.info_outline), accent);
    expect(tintOf(Icons.logout), Colors.red);
  });
}
