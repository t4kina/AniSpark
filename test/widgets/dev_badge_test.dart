import 'package:anispark/utils/developers.dart';
import 'package:anispark/widgets/dev_badge.dart';
import 'package:anispark/widgets/profile/profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('knows the developer by AniList name, whatever the case', () {
    expect(isAniSparkDeveloper('t4kina'), isTrue);
    expect(isAniSparkDeveloper('T4Kina'), isTrue);
    expect(isAniSparkDeveloper('faye'), isFalse);
    expect(isAniSparkDeveloper(null), isFalse);
  });

  Future<void> pump(WidgetTester tester, Widget child, {bool reduceMotion = false}) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  testWidgets('the developer\'s name carries the seal, anyone else\'s does not', (tester) async {
    await pump(tester, const Column(children: [BadgedName('t4kina'), BadgedName('faye')]));

    expect(find.byType(DevBadge), findsOneWidget);
    final seal = tester.getRect(find.byType(DevBadge));
    expect(seal.left, greaterThan(tester.getRect(find.text('t4kina')).right), reason: 'after the name');
    expect(find.bySemanticsLabel('AniSpark developer'), findsOneWidget);
  });

  testWidgets('the seal sparkles all the time, and holds still when motion is reduced', (tester) async {
    await pump(tester, const DevBadge());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it keeps animating');

    await pump(tester, const DevBadge(), reduceMotion: true);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('is beside the name on the developer\'s profile', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ProfileCard(name: 't4kina', lang: 'en'))),
    ));
    await tester.pump();

    expect(find.byType(DevBadge), findsOneWidget);
  });
}
