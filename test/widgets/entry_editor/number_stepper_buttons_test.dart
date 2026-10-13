import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/entry_editor/entry_editor_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Color? _boxColour(WidgetTester tester, IconData icon) => tester
    .widget<Material>(find.descendant(of: find.widgetWithIcon(IconButton, icon), matching: find.byType(Material)).first)
    .color;

void main() {
  testWidgets('a button that can not step keeps its box, only dimmed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.dark, Colors.blue),
      home: Scaffold(
        body: NumberStepper(value: 0, max: 12, lang: 'English', onChanged: (_) {}),
      ),
    ));

    final minus = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove));
    expect(minus.onPressed, isNull, reason: 'nothing below 0');

    final disabledBox = _boxColour(tester, Icons.remove);
    final enabledBox = _boxColour(tester, Icons.add);
    expect(disabledBox, isNotNull);
    expect(disabledBox!.a, greaterThan(0), reason: 'the box is still drawn');
    expect(disabledBox.a, lessThan(enabledBox!.a), reason: 'but dimmer than an active one');
  });
}
