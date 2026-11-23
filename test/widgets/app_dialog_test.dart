import 'dart:io';

import 'package:anispark/theme/app_colors.dart';
import 'package:anispark/theme/app_layout.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:anispark/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<bool> answers;

  setUp(() => answers = []);

  Future<void> pumpApp(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onOpen, {
    Size size = const Size(400, 800),
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.teal),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TextButton(onPressed: () => onOpen(context), child: const Text('open')),
          ),
        ),
      ),
    ));
  }

  Future<void> openConfirm(WidgetTester tester, {bool destructive = false, bool reduceMotion = false}) async {
    await pumpApp(
      tester,
      (context) async => answers.add(await showAppConfirm(
        context: context,
        title: 'Log out',
        message: 'Are you sure?',
        confirmLabel: 'Yes',
        cancelLabel: 'Cancel',
        destructive: destructive,
      )),
      reduceMotion: reduceMotion,
    );
    await tester.tap(find.text('open'));
  }

  Color? fill(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.descendant(of: find.widgetWithText(AppButton, label), matching: find.byType(Container)).first,
    );
    return (container.decoration! as BoxDecoration).color;
  }

  testWidgets('a confirmation answers true only when it is confirmed', (tester) async {
    await openConfirm(tester);
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Are you sure?'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
    expect(find.byType(AppDialog), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [true, false]);
  });

  testWidgets('tapping outside a confirmation answers no', (tester) async {
    await openConfirm(tester);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 780));
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(find.byType(AppDialog), findsNothing);
  });

  testWidgets('the two answers are app buttons of the same width, the accent on the one that confirms', (tester) async {
    await openConfirm(tester);
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(AppDialog)));
    expect(fill(tester, 'Yes'), theme.colorScheme.primary);
    expect(fill(tester, 'Cancel'), theme.colorScheme.surfaceContainerHighest);
    expect(
      tester.getSize(find.widgetWithText(AppButton, 'Yes')).width,
      tester.getSize(find.widgetWithText(AppButton, 'Cancel')).width,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(AppButton, 'Cancel')).dx,
      lessThan(tester.getTopLeft(find.widgetWithText(AppButton, 'Yes')).dx),
      reason: 'the way out comes first',
    );
  });

  testWidgets('something that cannot be undone is confirmed in the danger colour', (tester) async {
    await openConfirm(tester, destructive: true);
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(AppDialog)));
    expect(fill(tester, 'Yes'), theme.extension<AppColors>()!.danger);
  });

  testWidgets('is a card of the app surface, no wider than a phone needs', (tester) async {
    await pumpApp(
      tester,
      (context) => showAppDialog<void>(
        context: context,
        builder: (_) => const AppDialog(title: 'About', content: Text('AniSpark')),
      ),
      size: const Size(1000, 800),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final card = find.descendant(of: find.byType(AppDialog), matching: find.byType(Material)).first;
    final material = tester.widget<Material>(card);
    expect(material.color, Theme.of(tester.element(card)).colorScheme.surface);
    expect(material.borderRadius, AppRadius.lgAll);
    expect(tester.getSize(card).width, 340);
    expect(tester.getCenter(card).dx, 500);
  });

  testWidgets('text too long for the screen scrolls inside the card', (tester) async {
    await pumpApp(
      tester,
      (context) => showAppDialog<void>(
        context: context,
        builder: (dialogContext) => AppDialog(
          title: 'Privacy',
          content: Text('What happens to your data. ' * 200),
          actions: [
            AppButton(label: 'Close', expand: true, onPressed: () => Navigator.pop(dialogContext)),
          ],
        ),
      ),
      size: const Size(360, 500),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final card = find.descendant(of: find.byType(AppDialog), matching: find.byType(Material)).first;
    expect(tester.getRect(card).bottom, lessThan(500));
    expect(tester.getRect(find.widgetWithText(AppButton, 'Close')).bottom, lessThan(500), reason: 'the way out stays in view');
    expect(find.descendant(of: find.byType(AppDialog), matching: find.byType(Scrollable)), findsOneWidget);
  });

  testWidgets('grows in from slightly smaller', (tester) async {
    await openConfirm(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: find.byType(AppDialog), matching: find.byType(ScaleTransition)).first,
    );
    expect(scale.scale.value, inExclusiveRange(0.9, 1));

    await tester.pumpAndSettle();
    expect(scale.scale.value, 1);
  });

  testWidgets('is there at once when motion is reduced', (tester) async {
    await openConfirm(tester, reduceMotion: true);
    await tester.pump();
    await tester.pump();

    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: find.byType(AppDialog), matching: find.byType(ScaleTransition)).first,
    );
    expect(scale.scale.value, 1);
  });

  test('every dialog in the app is an AppDialog', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            !file.path.endsWith('app_dialog.dart') &&
            file.readAsStringSync().contains(RegExp(r'AlertDialog|SimpleDialog|showDialog\b')))
          file.path,
    ];

    expect(offenders, isEmpty);
  });
}
