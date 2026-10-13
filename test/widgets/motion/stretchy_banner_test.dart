import 'package:anispark/widgets/motion/stretchy_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bannerHeight = 200.0;

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  Widget page({bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion, padding: const EdgeInsets.only(top: 40)),
          child: Scaffold(
            body: CustomScrollView(
              controller: controller,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: _bannerHeight,
                    child: StretchyBanner(
                      controller: controller,
                      child: const ColoredBox(key: ValueKey('image'), color: Colors.teal),
                    ),
                  ),
                ),
                SliverList.list(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))]),
              ],
            ),
          ),
        ),
      );

  Matrix4 bannerTransform(WidgetTester tester) => tester
      .widget<Transform>(find.ancestor(of: find.byKey(const ValueKey('image')), matching: find.byType(Transform)).first)
      .transform;

  testWidgets('stretches to fill the gap when the page is pulled down', (tester) async {
    await tester.pumpWidget(page());

    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();

    final pulled = -controller.offset;
    expect(pulled, greaterThan(0), reason: 'the bouncing physics overscrolled');
    final box = tester.getRect(find.byType(StretchyBanner));
    final scale = bannerTransform(tester).entry(1, 1);
    // Scaled from its bottom edge, the image reaches the top of the screen.
    expect(box.bottom - box.height * scale, closeTo(0, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('drifts at half speed while the page scrolls', (tester) async {
    await tester.pumpWidget(page());

    controller.jumpTo(100);
    await tester.pump();

    expect(bannerTransform(tester).getTranslation().y, closeTo(50, 0.01));
  });

  testWidgets('keeps still while scrolling when motion is reduced', (tester) async {
    await tester.pumpWidget(page(reduceMotion: true));

    controller.jumpTo(100);
    await tester.pump();

    final transforms = find.ancestor(of: find.byKey(const ValueKey('image')), matching: find.byType(Transform));
    final moved = tester.widgetList<Transform>(transforms).any((t) => t.transform.getTranslation().y != 0);
    expect(moved, isFalse);
  });

  testWidgets('darkens the top so the status bar stays readable', (tester) async {
    await tester.pumpWidget(page());

    final scrims = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(StretchyBanner), matching: find.byType(DecoratedBox)))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient != null);
    expect(scrims, isNotEmpty);
    final colors = (scrims.first.gradient! as LinearGradient).colors;
    expect(colors.first.a, greaterThan(0), reason: 'dark at the top');
    expect(colors.last.a, 0, reason: 'clear further down');
  });
}
