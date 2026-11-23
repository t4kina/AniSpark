import 'package:anispark/widgets/motion/arrival_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page() => Scaffold(
        body: ArrivalBuilder(builder: (_, arrived) => Text(arrived ? 'arrived' : 'arriving')),
      );

  testWidgets('the first page has arrived from the start', (tester) async {
    await tester.pumpWidget(MaterialApp(home: page()));

    expect(find.text('arrived'), findsOneWidget);
  });

  testWidgets('a pushed page arrives when its transition ends, and stays arrived while it leaves', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page())),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('arriving'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('arrived'), findsOneWidget);

    Navigator.pop(tester.element(find.text('arrived')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('arrived'), findsOneWidget);
    expect(find.text('arriving'), findsNothing);
    await tester.pumpAndSettle();
  });
}
