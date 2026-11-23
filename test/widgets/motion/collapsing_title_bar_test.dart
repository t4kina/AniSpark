import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/motion/collapsing_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const statusBar = 47.0;
  late ScrollController controller;
  late int taps;

  setUp(() {
    controller = ScrollController();
    taps = 0;
  });
  tearDown(() => controller.dispose());

  Future<void> pumpPage(WidgetTester tester, {bool attached = true, double sideInset = 56}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.teal),
      home: Scaffold(
        body: Stack(
          children: [
            ListView(
              controller: attached ? controller : null,
              padding: EdgeInsets.zero,
              children: [
                GestureDetector(
                  onTap: () => taps++,
                  child: Container(height: 300, color: Colors.indigo, child: const Text('header')),
                ),
                const SizedBox(height: 2000),
              ],
            ),
            CollapsingTitleBar(
              controller: controller,
              title: 'Cowboy Bebop: Knockin on Heavens Door, the very long title',
              revealAt: 200,
              sideInset: sideInset,
            ),
          ],
        ),
      ),
    ));
  }

  final bar = find.byType(BackdropFilter);
  final title = find.textContaining('Cowboy Bebop');

  double titleOpacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.ancestor(of: title, matching: find.byType(Opacity)).first).opacity;

  testWidgets('stays away until the page title has scrolled off', (tester) async {
    await pumpPage(tester);
    expect(bar, findsNothing);
    expect(title, findsNothing);

    controller.jumpTo(200);
    await tester.pump();
    expect(bar, findsNothing, reason: 'no blur is paid for while there is nothing to show');
  });

  testWidgets('comes in with the scroll: the frost builds up and the title rises into place', (tester) async {
    await pumpPage(tester);

    controller.jumpTo(224);
    await tester.pump();
    expect(bar, findsOneWidget);
    expect(titleOpacity(tester), closeTo(0.5, 0.01));
    final halfway = tester.getCenter(title).dy;

    controller.jumpTo(600);
    await tester.pump();
    expect(titleOpacity(tester), 1);
    expect(tester.getCenter(title).dy, lessThan(halfway), reason: 'it rose');
    expect(tester.getCenter(title).dy, statusBar + CollapsingTitleBar.height / 2);
    expect(tester.getSize(bar).height, statusBar + CollapsingTitleBar.height);

    controller.jumpTo(0);
    await tester.pump();
    expect(bar, findsNothing, reason: 'and leaves the same way');
  });

  testWidgets('a long title is cut short, clear of the buttons at each side', (tester) async {
    await pumpPage(tester, sideInset: 140);
    controller.jumpTo(600);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(title);
    expect(rect.left, greaterThanOrEqualTo(140));
    expect(rect.right, lessThanOrEqualTo(400 - 140));
  });

  testWidgets('lets taps through to the page under it', (tester) async {
    await pumpPage(tester);
    controller.jumpTo(250);
    await tester.pump();
    expect(bar, findsOneWidget);

    // What is left of the header is under the bar.
    await tester.tapAt(const Offset(20, 30));
    expect(taps, 1);
  });

  testWidgets('stays away while the page has not attached its scroll view yet', (tester) async {
    await pumpPage(tester, attached: false);

    expect(tester.takeException(), isNull);
    expect(bar, findsNothing);
  });
}
