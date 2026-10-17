import 'package:anispark/theme/app_motion.dart';
import 'package:anispark/widgets/profile/count_up_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

String _shown(WidgetTester tester) => tester.widget<Text>(find.byType(Text)).data!;

void main() {
  testWidgets('counts up from zero once and ends on the real value', (tester) async {
    await tester.pumpWidget(_app(const CountUpText(1234)));
    expect(_shown(tester), '0');

    await tester.pump(AppMotion.long ~/ 2);
    final halfway = int.parse(_shown(tester));
    expect(halfway, inExclusiveRange(0, 1234));

    await tester.pumpAndSettle();
    expect(_shown(tester), '1234');
    expect(tester.getSemantics(find.byType(CountUpText)).label, '1234');
  });

  testWidgets('rebuilding with the same value does not count again', (tester) async {
    await tester.pumpWidget(_app(const CountUpText(1234)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(const CountUpText(1234, style: TextStyle(fontSize: 20))));

    expect(_shown(tester), '1234');
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing is animating');
  });

  testWidgets('a new value counts on from the one shown', (tester) async {
    await tester.pumpWidget(_app(const CountUpText(100)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(const CountUpText(200)));
    await tester.pump(AppMotion.long ~/ 2);
    expect(int.parse(_shown(tester)), inExclusiveRange(100, 200));

    await tester.pumpAndSettle();
    expect(_shown(tester), '200');
  });

  testWidgets('keeps the decimals it is asked for', (tester) async {
    await tester.pumpWidget(_app(const CountUpText(12.34, fractionDigits: 1)));
    await tester.pumpAndSettle();

    expect(_shown(tester), '12.3');
  });

  testWidgets('shows the value at once when animations are reduced', (tester) async {
    await tester.pumpWidget(_app(const CountUpText(1234), reduceMotion: true));
    await tester.pump();

    expect(_shown(tester), '1234');
  });

  _tabularFiguresTest();
}

void _tabularFiguresTest() {
  testWidgets('counts with equal-width digits so the number does not wobble', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CountUpText(1234, style: TextStyle(fontSize: 20))));

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(text.style?.fontSize, 20);
    await tester.pumpAndSettle();
  });
}
