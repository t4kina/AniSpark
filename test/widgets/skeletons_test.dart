import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  Widget app(
    Widget child, {
    bool reduceMotion = false,
    Brightness brightness = Brightness.dark,
    EdgeInsets padding = EdgeInsets.zero,
  }) =>
      MaterialApp(
        theme: buildAppTheme(brightness, Colors.teal),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion, padding: padding),
          child: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
        ),
      );

  Shimmer shimmer(WidgetTester tester) => tester.widget(find.byType(Shimmer));

  Iterable<Size> boxSizes(WidgetTester tester) => tester.widgetList<SkeletonBox>(find.byType(SkeletonBox)).map(
        (box) => Size(box.width ?? double.infinity, box.height),
      );

  for (final brightness in Brightness.values) {
    testWidgets('rests on the colour images load over (${brightness.name})', (tester) async {
      await tester.pumpWidget(app(const Skeleton(child: SkeletonBox(height: 20)), brightness: brightness));

      final surface = Theme.of(tester.element(find.byType(Skeleton))).colorScheme.surfaceContainerHighest;
      final colors = (shimmer(tester).gradient as LinearGradient).colors;
      expect(colors.first, surface);
      expect(colors.last, surface);
      expect(colors[colors.length ~/ 2], isNot(surface), reason: 'a lighter band sweeps across it');
    });
  }

  testWidgets('shimmers', (tester) async {
    await tester.pumpWidget(app(const Skeleton(child: SkeletonBox(height: 20))));

    expect(shimmer(tester).enabled, isTrue);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('holds still when motion is reduced', (tester) async {
    await tester.pumpWidget(app(const Skeleton(child: SkeletonBox(height: 20)), reduceMotion: true));

    expect(shimmer(tester).enabled, isFalse);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('list rows can take the size of the covers they stand in for', (tester) async {
    await tester.pumpWidget(app(const ListSkeleton(rows: 2)));
    expect(boxSizes(tester), contains(const Size(80, 115)));

    await tester.pumpWidget(app(const ListSkeleton(rows: 2, coverSize: Size(46, 64))));
    expect(boxSizes(tester), contains(const Size(46, 64)));
    expect(boxSizes(tester), isNot(contains(const Size(80, 115))));
    expect(tester.takeException(), isNull, reason: 'the lines fit beside a short cover');
  });

  testWidgets('a grid has as many covers as asked, laid out like the real one', (tester) async {
    const delegate = SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.5);
    await tester.pumpWidget(app(const GridSkeleton(gridDelegate: delegate, count: 6)));

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.gridDelegate, delegate);
    expect(grid.padding, const EdgeInsets.all(12));
    expect(grid.physics, isA<NeverScrollableScrollPhysics>());
    expect(boxSizes(tester).where((size) => size.height == double.infinity), hasLength(6));
  });

  testWidgets('a grid inside a scrolling page is as tall as its rows', (tester) async {
    const delegate = SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.5);
    await tester.pumpWidget(app(const SingleChildScrollView(
      child: GridSkeleton(gridDelegate: delegate, count: 6, shrinkWrap: true, padding: EdgeInsets.zero),
    )));

    // 800 wide: three columns of 800 / 3, twice as tall as wide, two rows.
    expect(tester.getSize(find.byType(GridSkeleton)).height, moreOrLessEquals(800 / 3 * 2 * 2, epsilon: 0.5));
  });

  testWidgets('people rows are only as tall as their rows, with round avatars', (tester) async {
    await tester.pumpWidget(app(const PeopleSkeleton(rows: 3, avatarSize: 44)));

    expect(tester.getSize(find.byType(PeopleSkeleton)).height, 3 * (44 + 12));
    final avatars = tester
        .widgetList<SkeletonBox>(find.byType(SkeletonBox))
        .where((box) => box.width == 44 && box.height == 44);
    expect(avatars, hasLength(3));
    expect(avatars.every((box) => box.radius == 22), isTrue);
    expect(find.byType(SkeletonBox), findsNWidgets(6), reason: 'an avatar and a name each');
  });

  testWidgets('people rows can have a second line, for what they wrote', (tester) async {
    await tester.pumpWidget(app(const PeopleSkeleton(
      rows: 2,
      avatarSize: 32,
      lines: 2,
      padding: EdgeInsets.fromLTRB(16, 6, 8, 6),
    )));

    expect(find.byType(SkeletonBox), findsNWidgets(6));
    expect(tester.getTopLeft(find.byType(SkeletonBox).first), const Offset(16, 6));
  });

  testWidgets('a profile starts under the status bar and the room asked above it', (tester) async {
    await tester.pumpWidget(app(const ProfileSkeleton(topGap: 52), padding: const EdgeInsets.only(top: 47)));

    final card = find.byType(SkeletonBox).first;
    expect(tester.getTopLeft(card), const Offset(16, 47 + 52));
    expect(tester.getSize(card).width, 800 - 32);
    expect(tester.takeException(), isNull);
  });
}
