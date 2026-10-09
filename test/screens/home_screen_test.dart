import 'dart:io';

import 'package:anispark/screens/home_screen.dart';
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
    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();

    expect(find.text(loadErrorText), findsOneWidget);
    expect(offline.requests, 7, reason: 'one request per section');

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(offline.requests, 14);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('shows cached sections when offline', (tester) async {
    await cache.write('discover:trending', [
      {
        'id': 1,
        'title': {'english': 'Cowboy Bebop'},
        'averageScore': 86,
      },
    ]);

    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();

    expect(find.text('Cowboy Bebop'), findsOneWidget);
    expect(find.text(loadErrorText), findsNothing);
  });

  testWidgets('does not refetch sections cached less than an hour ago',
      (tester) async {
    await cache.write('discover:trending', [
      {
        'id': 1,
        'title': {'english': 'Cowboy Bebop'},
        'averageScore': 86,
      },
    ]);

    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();

    expect(offline.requests, 6, reason: 'only the uncached sections');
  });
}
