import 'dart:io';

import 'package:anispark/theme/app_layout.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Size(400, 800);
  const statusBar = 47.0;

  Future<void> open(
    WidgetTester tester,
    WidgetBuilder builder, {
    double maxHeightFraction = 1,
    ValueChanged<Object?>? onClosed,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.teal),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await showAppSheet<Object>(
                  context: context,
                  maxHeightFraction: maxHeightFraction,
                  builder: builder,
                );
                onClosed?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Material surface(WidgetTester tester) => tester.widget<Material>(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first,
      );

  testWidgets('is the app surface with the sheet corners, and starts with the handle', (tester) async {
    await open(tester, (_) => const SizedBox(height: 120, child: Text('content')));

    final material = surface(tester);
    final theme = Theme.of(tester.element(find.text('content')));
    expect(material.color, theme.colorScheme.surface);
    expect(material.shape, const RoundedRectangleBorder(borderRadius: AppRadius.sheet));

    expect(find.byType(SheetHandle), findsOneWidget);
    expect(tester.getTopLeft(find.byType(SheetHandle)).dy, tester.getTopLeft(find.byType(BottomSheet)).dy);
    expect(tester.getTopLeft(find.text('content')).dy, tester.getBottomLeft(find.byType(SheetHandle)).dy);
  });

  testWidgets('is as tall as its content', (tester) async {
    await open(tester, (_) => const SizedBox(height: 120));

    final handle = tester.getSize(find.byType(SheetHandle)).height;
    expect(tester.getSize(find.byType(BottomSheet)).height, 120 + handle);
  });

  testWidgets('content taller than the screen stops under the status bar', (tester) async {
    await open(tester, (_) => const SingleChildScrollView(child: SizedBox(height: 2000)));

    expect(tester.getTopLeft(find.byType(BottomSheet)).dy, statusBar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can be kept to a fraction of the screen', (tester) async {
    await open(tester, (_) => const SingleChildScrollView(child: SizedBox(height: 2000)), maxHeightFraction: 0.5);

    expect(tester.getSize(find.byType(BottomSheet)).height, screen.height * 0.5);
  });

  testWidgets('a sheet that grows when dragged starts at its own size', (tester) async {
    await open(
      tester,
      (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 1,
        builder: (_, controller) => ListView(controller: controller, children: const [SizedBox(height: 2000)]),
      ),
    );

    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThan(screen.height * 0.6));
    expect(height, greaterThan(screen.height * 0.4));
  });

  testWidgets('returns what the content pops with', (tester) async {
    Object? result;
    await open(
      tester,
      (context) => TextButton(onPressed: () => Navigator.pop(context, 'picked'), child: const Text('pick')),
      onClosed: (value) => result = value,
    );

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(result, 'picked');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a sheet title is the same headline everywhere, centred', (tester) async {
    await open(tester, (_) => const SheetTitle('Sort by'));

    final title = tester.widget<Text>(find.text('Sort by'));
    expect(title.style?.fontSize, 17);
    expect(title.textAlign, TextAlign.center);
    expect(tester.getCenter(find.text('Sort by')).dx, screen.width / 2);
  });

  test('every bottom sheet in the app is opened with showAppSheet', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            !file.path.endsWith('app_sheet.dart') &&
            file.readAsStringSync().contains('showModalBottomSheet'))
          file.path,
    ];

    expect(offenders, isEmpty);
  });
}
