import 'dart:ui' as ui;

import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/widgets/option_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging the options up keeps the sheet\'s top corners round', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        // The app's theme gives every ListTile a background of its own.
        theme: buildAppTheme(Brightness.dark, const Color(0xFF009688)),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF6A3D8F),
            body: Center(
              child: TextButton(
                onPressed: () => showOptionSheet<String>(
                  context: context,
                  title: 'Sort',
                  options: const ['Popularity', 'Score', 'Trending', 'Title'],
                  labelOf: (option) => option,
                  current: 'Popularity',
                  onSelected: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Hold the list dragged up, so the rows slide under the title.
    final gesture = await tester.startGesture(tester.getCenter(find.text('Score')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
    final pixels = await tester.runAsync(() async {
      final image = await captureImage(tester.element(find.byType(MaterialApp)));
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      Color at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      final y = sheetTop.round() + 2;
      return (corner: at(1, y), middle: at(image.width ~/ 2, y));
    });
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pixels!.corner, isNot(pixels.middle),
        reason: 'the corner shows what is behind the sheet, not a row\'s background');
    // iOS, where the list bounces even when its options fit.
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
