import 'package:anispark/widgets/motion/swipe_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> ran;

  Future<void> pumpRow(WidgetTester tester) async {
    ran = [];
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SwipeAction(
            startToEnd: SwipeActionSide(
              color: Colors.green,
              icon: Icons.add,
              label: 'Episode',
              onTriggered: () => ran.add('+1'),
            ),
            endToStart: SwipeActionSide(
              color: Colors.red,
              icon: Icons.remove,
              label: 'Episode',
              onTriggered: () => ran.add('-1'),
            ),
            child: const SizedBox(height: 100, child: Center(child: Text('Row'))),
          ),
        ),
      ),
    ));
  }

  testWidgets('a quarter of the width is enough to run the action', (tester) async {
    await pumpRow(tester);

    await tester.timedDrag(find.text('Row'), const Offset(80, 0), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(ran, isEmpty, reason: 'a fifth of the width is not enough');

    await tester.timedDrag(find.text('Row'), const Offset(110, 0), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(ran, ['+1']);

    await tester.timedDrag(find.text('Row'), const Offset(-110, 0), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(ran, ['+1', '-1']);
  });

  testWidgets('a quick flick runs the action too', (tester) async {
    await pumpRow(tester);

    await tester.fling(find.text('Row'), const Offset(60, 0), 1500);
    await tester.pumpAndSettle();

    expect(ran, ['+1']);
  });

  testWidgets('the row springs back to its place after a swipe', (tester) async {
    await pumpRow(tester);
    final start = tester.getTopLeft(find.text('Row'));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Row')));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Row')).dx, greaterThan(start.dx), reason: 'it follows the finger');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    final midway = tester.getTopLeft(find.text('Row')).dx;
    expect(midway, greaterThan(start.dx), reason: 'it glides back rather than jumping');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Row')), start);
  });

  testWidgets('a haptic ticks once, when the swipe reaches the trigger point', (tester) async {
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpRow(tester);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Row')));
    for (var i = 0; i < 16; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(haptics, hasLength(1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the row resists being pulled far past the trigger point', (tester) async {
    await pumpRow(tester);
    final start = tester.getTopLeft(find.text('Row')).dx;

    final gesture = await tester.startGesture(tester.getCenter(find.text('Row')));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(280, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.text('Row')).dx - start, lessThan(200));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
