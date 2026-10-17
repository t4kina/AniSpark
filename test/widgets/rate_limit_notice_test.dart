import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/rate_limit_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => rateLimitActiveNotifier.value = false);
  tearDown(() => rateLimitActiveNotifier.value = false);

  Widget app() => ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          builder: (context, child) => RateLimitNotice(child: child!),
          home: const Scaffold(body: Text('page')),
        ),
      );

  testWidgets('shows a snack bar while AniList rate-limits and hides it after', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(SnackBar), findsNothing);

    rateLimitActiveNotifier.value = true;
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBar, tr('rate_limit_banner', 'English')), findsOneWidget);

    // It stays for as long as the wait lasts, however long that is.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(SnackBar), findsOneWidget);

    rateLimitActiveNotifier.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('does not stack notices when the rate limit is reported again', (tester) async {
    await tester.pumpWidget(app());

    rateLimitActiveNotifier.value = true;
    await tester.pumpAndSettle();
    rateLimitActiveNotifier.value = false;
    rateLimitActiveNotifier.value = true;
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    rateLimitActiveNotifier.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
