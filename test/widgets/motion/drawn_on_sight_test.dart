import 'package:anispark/widgets/motion/drawn_on_sight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  /// The current progress of the chart labelled [name], on screen or not.
  double progress(WidgetTester tester, String name) =>
      double.parse(tester.widget<Text>(find.byKey(ValueKey(name), skipOffstage: false)).data!);

  Widget chart(String name, {Duration delay = Duration.zero}) => DrawnOnSight(
        delay: delay,
        builder: (_, progress) => AnimatedBuilder(
          animation: progress,
          builder: (_, _) => SizedBox(height: 100, child: Text('${progress.value}', key: ValueKey(name))),
        ),
      );

  Future<void> pumpPage(WidgetTester tester, {bool reduceMotion = false, List<Widget>? children}) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 600), disableAnimations: reduceMotion),
        child: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              // Adapters, like the profile: built and laid out even when
              // they are far below the fold.
              for (final child in children ??
                  [chart('top'), const SizedBox(height: 900), chart('bottom'), const SizedBox(height: 900)])
                SliverToBoxAdapter(child: child),
            ],
          ),
        ),
      ),
    ));
  }

  testWidgets('what is in view when the page opens is drawn at once', (tester) async {
    await pumpPage(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester, 'top'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(progress(tester, 'top'), 1);
  });

  testWidgets('what is below the fold waits until it is scrolled into view', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(progress(tester, 'bottom'), 0, reason: 'laid out, but not seen yet');

    controller.jumpTo(300);
    await tester.pumpAndSettle();
    expect(progress(tester, 'bottom'), 0, reason: 'still under the fold');

    controller.jumpTo(500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester, 'bottom'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(progress(tester, 'bottom'), 1);
  });

  testWidgets('it is drawn once: scrolling away and back does not replay it', (tester) async {
    await pumpPage(tester);
    controller.jumpTo(500);
    await tester.pumpAndSettle();
    expect(progress(tester, 'bottom'), 1);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    controller.jumpTo(500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(progress(tester, 'bottom'), 1);
  });

  testWidgets('rows given growing delays fill in one after the other', (tester) async {
    await pumpPage(tester, children: [
      chart('first'),
      chart('second', delay: const Duration(milliseconds: 150)),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(progress(tester, 'first'), greaterThan(0));
    expect(progress(tester, 'second'), 0);

    await tester.pumpAndSettle();
    expect(progress(tester, 'second'), 1);
  });

  testWidgets('everything is drawn from the start when motion is reduced', (tester) async {
    await pumpPage(tester, reduceMotion: true);

    expect(progress(tester, 'top'), 1);
    expect(progress(tester, 'bottom'), 1);
  });

  testWidgets('outside anything that scrolls it is drawn at once', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: chart('alone'))));
    await tester.pumpAndSettle();

    expect(progress(tester, 'alone'), 1);
  });
}
