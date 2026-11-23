import 'dart:async';
import 'dart:io';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/completion_celebration.dart';
import 'package:anispark/theme/app_theme.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

const _accent = Color(0xFF009688);
const _cover = 'https://img.example/bebop.jpg';

void main() {
  late List<double> completedWith;
  late Future<bool> Function() answer;

  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  setUp(() {
    completedWith = [];
    answer = () async => true;
  });

  /// Opens the celebration over a first page, as My List does.
  Future<void> open(
    WidgetTester tester, {
    String? coverUrl = _cover,
    bool isManga = false,
    double initialScore = 0,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark, _accent),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCompletionCelebration(
                context,
                title: 'Cowboy Bebop',
                coverUrl: coverUrl,
                averageScore: 86,
                initialScore: initialScore,
                isManga: isManga,
                onComplete: (score) {
                  completedWith.add(score);
                  return answer();
                },
              ),
              child: const Text('list'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('list'));
    // Confetti keeps moving for a while: step, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  ConfettiWidget confetti(WidgetTester tester) => tester.widget<ConfettiWidget>(find.byType(ConfettiWidget));

  final completeButton = find.widgetWithText(AppButton, _en('list_complete_series'));

  testWidgets('is built around the cover, with what was finished and the tick on it', (tester) async {
    await open(tester);

    expect(find.text(_en('list_congrats_finished')), findsOneWidget);
    expect(find.text('Cowboy Bebop'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final cover = find.byWidgetPredicate((widget) => widget is CachedNetworkImage && widget.memCacheWidth == 360);
    expect(tester.getSize(cover), CompletionCelebration.coverSize);
    expect(tester.getCenter(cover).dx, 200, reason: 'centred');
    expect(tester.getCenter(cover).dy, lessThan(tester.getCenter(find.text('Cowboy Bebop')).dy),
        reason: 'the title sits under its cover');
  });

  testWidgets('throws one burst of confetti, in the accent colour and its lighter shades only', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark, _accent),
        home: CompletionCelebration(
          title: 'Cowboy Bebop',
          coverUrl: _cover,
          averageScore: null,
          initialScore: 0,
          isManga: false,
          onComplete: (_) async => true,
        ),
      ),
    ));

    expect(find.byType(ConfettiWidget), findsOneWidget);
    expect(confetti(tester).confettiController.state, ConfettiControllerState.playing);
    final colors = confetti(tester).colors!;
    expect(colors, contains(_accent));
    for (final color in colors) {
      final hsl = HSLColor.fromColor(color);
      expect(
        color == Colors.white || (hsl.hue - HSLColor.fromColor(_accent).hue).abs() < 2,
        isTrue,
        reason: '$color is the accent, a tint of it, or white',
      );
    }

    // The pieces fall off the screen and nothing more is thrown.
    for (var i = 0; i < 900 && confetti(tester).confettiController.state == ConfettiControllerState.playing; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(confetti(tester).confettiController.state, ConfettiControllerState.stopped, reason: 'a burst, not a shower');
  });

  testWidgets('is all there at once, with no confetti, when motion is reduced', (tester) async {
    await open(tester, reduceMotion: true);

    expect(confetti(tester).confettiController.state, ConfettiControllerState.stopped);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(tester.getSize(find.byIcon(Icons.check_rounded)).width, greaterThan(0));
  });

  testWidgets('completing saves with the score shown and closes', (tester) async {
    await open(tester, initialScore: 8.5);
    expect(find.text('8.5'), findsOneWidget);

    await tester.tap(completeButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(completedWith, [8.5]);
    expect(find.byType(CompletionCelebration), findsNothing);
    expect(find.text('list'), findsOneWidget);
  });

  testWidgets('stays open and says so when the save fails, and can be tried again', (tester) async {
    answer = () async => false;
    await open(tester);

    await tester.tap(completeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CompletionCelebration), findsOneWidget);
    expect(find.text(_en('save_failed')), findsWidgets);

    // Once the message has gone from over the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    answer = () async => true;
    await tester.tap(completeButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(completedWith, hasLength(2));
    expect(find.byType(CompletionCelebration), findsNothing);
  });

  testWidgets('cannot be left while it is saving', (tester) async {
    final saving = Completer<bool>();
    answer = () => saving.future;
    await open(tester);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);

    await tester.tap(completeButton);
    await tester.pump();
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    saving.complete(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CompletionCelebration), findsNothing);
  });

  testWidgets('closing it leaves the series as it was', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip(_en('close')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(completedWith, isEmpty);
    expect(find.byType(CompletionCelebration), findsNothing);
  });

  testWidgets('a manga is asked about and completed as a manga', (tester) async {
    await open(tester, isManga: true);

    expect(find.text(_en('list_final_rating_manga')), findsOneWidget);
    expect(find.widgetWithText(AppButton, _en('list_complete_manga')), findsOneWidget);
  });

  testWidgets('without a cover the tick stands alone', (tester) async {
    await open(tester, coverUrl: null);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
