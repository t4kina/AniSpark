import 'dart:io';

import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

void main() {
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
  });

  testWidgets('shows an error with retry when offline and nothing is cached',
      (tester) async {
    await tester.pumpWidget(
        screenApp(const CharacterScreen(characterId: 1), cache: cache));
    await tester.pump();

    expect(find.text(loadErrorText), findsOneWidget);
    expect(offline.requests, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(offline.requests, 2);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('shows the cached character when offline', (tester) async {
    await cache.write('anon:character:1', {
      'id': 1,
      'isFavourite': false,
      'name': {'full': 'Spike Spiegel'},
      'media': {'nodes': []},
    });

    await tester.pumpWidget(
        screenApp(const CharacterScreen(characterId: 1), cache: cache));
    await tester.pump();

    expect(find.text('Spike Spiegel'), findsOneWidget);
    expect(find.text(loadErrorText), findsNothing);
    expect(offline.requests, 1, reason: 'cached data is still revalidated');
  });

  testWidgets('a photo that flies here lands on the photo the page was opened with, then on the loaded one',
      (tester) async {
    const tag = 'person:test:1';
    await cache.write('anon:character:1', {
      'id': 1,
      'isFavourite': false,
      'name': {'full': 'Spike Spiegel', 'native': 'NATIVE'},
      'media': {'nodes': []},
    });
    await tester.pumpWidget(screenApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const CharacterScreen(
                characterId: 1,
                name: 'Spike Spiegel',
                imageUrl: 'https://img.example/spike.jpg',
                heroTag: tag,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      cache: cache,
    ));
    final photo = find.descendant(of: find.byType(CharacterScreen), matching: find.byType(Hero));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(tester.widget<Hero>(photo).tag, tag);
    expect(find.text('Spike Spiegel'), findsOneWidget, reason: 'the name it was opened with');
    expect(find.text('NATIVE'), findsNothing, reason: 'the placeholder holds the landing spot');
    final landing = tester.getSize(photo);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('NATIVE'), findsOneWidget);
    expect(tester.widget<Hero>(photo).tag, tag, reason: 'so the photo can fly back');
    expect(tester.getSize(photo), landing);
  });
}
