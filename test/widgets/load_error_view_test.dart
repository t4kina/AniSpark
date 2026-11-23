import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:anispark/widgets/load_error_view.dart';
import 'package:anispark/widgets/state_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child) => ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('StateMessage', () {
    testWidgets('shows its icon, title, message and action, centred', (tester) async {
      await tester.pumpWidget(_app(StateMessage(
        icon: Icons.inbox_outlined,
        title: 'Nothing here yet',
        message: 'Things you add will show up here.',
        action: AppButton(label: 'Explore', onPressed: () {}),
      )));

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Things you add will show up here.'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(tester.getCenter(find.byIcon(Icons.inbox_outlined)).dx, 400);
      expect(
        tester.getTopLeft(find.text('Nothing here yet')).dy,
        lessThan(tester.getTopLeft(find.text('Things you add will show up here.')).dy),
      );
    });

    testWidgets('a long message wraps instead of running edge to edge', (tester) async {
      await tester.pumpWidget(_app(StateMessage(icon: Icons.inbox_outlined, message: 'word ' * 60)));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.textContaining('word')).width, lessThanOrEqualTo(320));
    });
  });

  group('LoadErrorView', () {
    testWidgets('says the load failed and retries on tap', (tester) async {
      var retries = 0;
      await tester.pumpWidget(_app(LoadErrorView(onRetry: () => retries++)));

      expect(find.text("Couldn't load the content"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(retries, 1);
    });

    testWidgets('can say what failed', (tester) async {
      await tester.pumpWidget(_app(LoadErrorView(onRetry: () {}, message: "Couldn't load the feed")));

      expect(find.text("Couldn't load the feed"), findsOneWidget);
      expect(find.text("Couldn't load the content"), findsNothing);
    });

    testWidgets('fits a sliver that fills the rest of a scroll view', (tester) async {
      await tester.pumpWidget(_app(CustomScrollView(
        slivers: [SliverFillRemaining(hasScrollBody: false, child: LoadErrorView(onRetry: () {}))],
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
