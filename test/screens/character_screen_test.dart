import 'dart:io';

import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/services/api_cache.dart';
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
}
