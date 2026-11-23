import 'dart:async';

import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int refreshes;
  late Completer<void> refreshing;

  setUp(() => refreshes = 0);

  Future<void> pumpList(WidgetTester tester, {double edgeOffset = 0}) async {
    // Made inside the test, so it completes on the test's own clock.
    refreshing = Completer<void>();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.teal),
      home: Scaffold(
        body: AppRefreshIndicator(
          edgeOffset: edgeOffset,
          onRefresh: () {
            refreshes++;
            return refreshing.future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 300, child: Text('first row'))],
          ),
        ),
      ),
    ));
  }

  /// A second of frames: the pull, the snap and the spinner each need several.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final spinner = find.byType(RefreshProgressIndicator);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a long pull refreshes once, with the spinner until it is done', (tester) async {
      await pumpList(tester);
      expect(spinner, findsNothing);

      await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
      await frames(tester);
      expect(refreshes, 1);
      expect(spinner, findsOneWidget);

      refreshing.complete();
      await frames(tester);
      expect(spinner, findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('is the stock spinner, in the accent colour', (tester) async {
    await pumpList(tester);
    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);

    final theme = Theme.of(tester.element(spinner));
    expect(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).color, theme.colorScheme.primary);
    refreshing.complete();
    await frames(tester);
  });

  testWidgets('comes down lower when the list starts under something', (tester) async {
    await pumpList(tester, edgeOffset: 90);

    expect(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset, 90);
  });
}
