import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/entry_editor/entry_editor_fields.dart';
import 'package:anispark/widgets/motion/animated_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stepper that keeps the value it reports, like the editor's form.
class _Host extends StatefulWidget {
  const _Host({this.suffix, this.decimals = 0, this.initial = 5});

  final String? suffix;
  final int decimals;
  final num initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late num _value = widget.initial;

  @override
  Widget build(BuildContext context) => NumberStepper(
        value: _value,
        max: 12,
        step: widget.decimals == 0 ? 1 : 0.5,
        decimals: widget.decimals,
        suffix: widget.suffix,
        lang: 'English',
        onChanged: (value) => setState(() => _value = value),
      );
}

Future<void> _pump(WidgetTester tester, Widget host, {bool reduceMotion = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(Brightness.dark, Colors.blue),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: host)),
    ),
  ));
}

bool _fieldTextHidden(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).style?.color == Colors.transparent;

/// Where the first glyph the field itself draws sits on screen (its tight
/// box: top at the font's ascent above the baseline).
Offset _fieldGlyph(WidgetTester tester) {
  final editable = tester.renderObject<RenderEditable>(
    find.byElementPredicate((element) => element is RenderObjectElement && element.renderObject is RenderEditable),
  );
  final box = editable.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
  return editable.localToGlobal(Offset(box.left, box.top));
}

/// The same for the rolling copy's [text].
Offset _copyGlyph(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byType(AnimatedCount), matching: find.text(text)),
  );
  final box = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
  return paragraph.localToGlobal(Offset(box.left, box.top));
}

void main() {
  for (final suffix in [null, '/ 12 ep']) {
    testWidgets('a + tap rolls the new value in exactly over the field\'s text (suffix: $suffix)', (tester) async {
      await _pump(tester, _Host(suffix: suffix));
      expect(_fieldTextHidden(tester), isFalse);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // The field already holds the new value, hidden while the copy rolls.
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '6');
      expect(_fieldTextHidden(tester), isTrue);
      expect(tester.widget<AnimatedCount>(find.byType(AnimatedCount)).value, 6);
      // The old value is leaving from where the field draws its text.
      final field = _fieldGlyph(tester);
      final copy = _copyGlyph(tester, '5');
      expect(copy.dx, moreOrLessEquals(field.dx, epsilon: 0.5));
      expect(copy.dy, moreOrLessEquals(field.dy, epsilon: 0.5));

      await tester.pumpAndSettle();
      expect(_fieldTextHidden(tester), isFalse, reason: 'the field shows its own text again');
    });
  }

  testWidgets('decimal values roll in tenths', (tester) async {
    await _pump(tester, const _Host(decimals: 1, initial: 7.5));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.descendant(of: find.byType(AnimatedCount), matching: find.text('8')), findsOneWidget);
    expect(find.descendant(of: find.byType(AnimatedCount), matching: find.text('7.5')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('typed values just appear', (tester) async {
    await _pump(tester, const _Host());

    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();

    expect(_fieldTextHidden(tester), isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '9');
  });

  testWidgets('with reduced motion the new value just appears', (tester) async {
    await _pump(tester, const _Host(), reduceMotion: true);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(_fieldTextHidden(tester), isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '6');
  });
}
