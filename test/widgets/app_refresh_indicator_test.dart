import 'dart:async';

import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/app_refresh_indicator.dart';
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

  /// A second of frames: the pull, the snap and the spark each need several.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final spark = find.byType(SparkMark);

  double sparkScale(WidgetTester tester) => tester
      .widget<Transform>(find.ancestor(of: spark, matching: find.byType(Transform)).at(1))
      .transform
      .entry(0, 0);

  double sparkAngle(WidgetTester tester) {
    final matrix = tester.widget<Transform>(find.ancestor(of: spark, matching: find.byType(Transform)).first).transform;
    return matrix.entry(1, 0);
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('on ${platform.name}', () {
      testWidgets('nothing is drawn until the list is pulled', (tester) async {
        await pumpList(tester);

        expect(spark, findsNothing);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('the spark comes out and grows with the pull', (tester) async {
        await pumpList(tester);

        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump();
        expect(spark, findsOneWidget);
        final small = sparkScale(tester);
        expect(small, lessThan(1));

        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(sparkScale(tester), greaterThan(small));

        await gesture.up();
        await frames(tester);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('a long pull refreshes: the spark stays, turning, until it is done', (tester) async {
        await pumpList(tester);

        await tester.fling(find.text('first row'), const Offset(0, 400), 1000);
        await frames(tester);
        expect(refreshes, 1);
        expect(spark, findsOneWidget);
        expect(sparkScale(tester), 1);

        final angle = sparkAngle(tester);
        await tester.pump(const Duration(milliseconds: 200));
        expect(sparkAngle(tester), isNot(angle), reason: 'it keeps turning while refreshing');

        refreshing.complete();
        await frames(tester);
        expect(spark, findsNothing);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('a short pull refreshes nothing and the spark goes away', (tester) async {
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
    final angle = sparkAngle(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sparkAngle(tester), angle);

    refreshing.complete();
    await frames(tester);
  });

  testWidgets('taps reach the list under the spark', (tester) async {
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
}
