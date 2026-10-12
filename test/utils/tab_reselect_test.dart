import 'package:anispark/utils/tab_reselect.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tells listeners which tab was tapped again, every time', () {
    final notifier = TabReselectNotifier();
    final tabs = <int?>[];
    notifier.addListener(() => tabs.add(notifier.tab));

    notifier.reselect(2);
    notifier.reselect(2);
    notifier.reselect(0);

    expect(tabs, [2, 2, 0]);
  });

  test('scrollToTopOnReselect scrolls only for its own tab and detaches', () {
    final notifier = TabReselectNotifier();
    final requests = <int>[];
    final stop = scrollToTopOnReselect(notifier, tab: 1, onReselected: () => requests.add(1));

    notifier.reselect(0);
    notifier.reselect(1);
    stop();
    notifier.reselect(1);

    expect(requests, [1]);
  });

  testWidgets('scrollToTop animates an attached controller to the top', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(controller: controller, children: [for (var i = 0; i < 50; i++) SizedBox(height: 100, child: Text('$i'))]),
    ));
    controller.jumpTo(2000);

    scrollToTop(controller);
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
  });

  test('scrollToTop ignores controllers without a scroll view', () {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    expect(() => scrollToTop(controller), returnsNormally);
  });
}
