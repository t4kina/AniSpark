import 'dart:async';

import 'package:anispark/theme/app_colors.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_refresh_indicator.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int refreshes;
  late Completer<void> refreshing;

  setUp(() {
    refreshes = 0;
    refreshing = Completer<void>();
  });

  Future<void> pumpList(WidgetTester tester, {double edgeOffset = 0, bool reduceMotion = false}) async {
    // Made inside the test, so it completes on the test's own clock.
    refreshing = Completer<void>();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.teal),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduceMotion),
        child: Scaffold(
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
      ),
    ));
  }

  /// A second of frames: the pull, the snap and the indicator each need several.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final spark = find.byType(CupertinoActivityIndicator);

  /// How many of its spokes the indicator shows (1: all of them).
  double revealed(WidgetTester tester) => tester.widget<CupertinoActivityIndicator>(spark).progress;

  bool spinning(WidgetTester tester) => tester.widget<CupertinoActivityIndicator>(spark).animating;

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('on ${platform.name}', () {
      testWidgets('nothing is drawn until the list is pulled', (tester) async {
        await pumpList(tester);

        expect(spark, findsNothing);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('the indicator comes out, its spokes appearing with the pull', (tester) async {
        await pumpList(tester);

        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump();
        expect(spark, findsOneWidget);
        final some = revealed(tester);
        expect(some, lessThan(1));
        expect(spinning(tester), isFalse, reason: 'it only spins once it refreshes');

        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(revealed(tester), greaterThan(some));

        await gesture.up();
        await frames(tester);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('a long pull refreshes: the indicator stays, spinning, until it is done', (tester) async {
        await pumpList(tester);

        await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
        await frames(tester);
        expect(refreshes, 1);
        expect(spark, findsOneWidget);
        expect(revealed(tester), 1);
        expect(spinning(tester), isTrue, reason: 'it keeps spinning while refreshing');

        refreshing.complete();
        await frames(tester);
        expect(spark, findsNothing);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('a short pull refreshes nothing and the indicator goes away', (tester) async {
        await pumpList(tester);

        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        expect(spark, findsOneWidget);

        await gesture.up();
        await frames(tester);
        expect(refreshes, 0);
        expect(spark, findsNothing);
      }, variant: TargetPlatformVariant.only(platform));
    });
  }

  testWidgets('sits at the top of the list, lower when the list starts under something', (tester) async {
    await pumpList(tester);
    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);
    final top = tester.getCenter(spark);
    expect(top.dx, 200);
    expect(top.dy, lessThan(100));
    refreshing.complete();
    await frames(tester);

    await pumpList(tester, edgeOffset: 90);
    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);
    expect(tester.getCenter(spark).dy, top.dy + 90);
    refreshing.complete();
    await frames(tester);
  });

  testWidgets('holds still while refreshing when motion is reduced', (tester) async {
    await pumpList(tester, reduceMotion: true);

    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);
    expect(refreshes, 1);
    expect(spark, findsOneWidget);
    expect(spinning(tester), isFalse);

    refreshing.complete();
    await frames(tester);
  });

  testWidgets('taps reach the list under the indicator', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppRefreshIndicator(
          onRefresh: () => refreshing.future,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GestureDetector(onTap: () => taps++, child: const SizedBox(height: 120, child: Text('first row'))),
            ],
          ),
        ),
      ),
    ));
    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);
    expect(spark, findsOneWidget);

    await tester.tapAt(tester.getCenter(spark));
    expect(taps, 1);

    refreshing.complete();
    await frames(tester);
  });

  testWidgets('is the bare indicator, in the secondary text colour, with no disc around it', (tester) async {
    await pumpList(tester);
    await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
    await frames(tester);

    final indicator = tester.widget<CupertinoActivityIndicator>(spark);
    final theme = Theme.of(tester.element(spark));
    expect(indicator.color, theme.extension<AppColors>()!.textSecondary);
    expect(
      find.ancestor(
        of: spark,
        matching: find.byWidgetPredicate((widget) => widget is Container && widget.decoration != null),
      ),
      findsNothing,
    );
    refreshing.complete();
    await frames(tester);
  });
}
