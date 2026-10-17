import 'dart:io';

import 'package:anispark/screens/search_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

void main() {
  final offline = OfflineHttpOverrides();

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> searchFor(WidgetTester tester, String query) async {
    await tester.pumpWidget(
        screenApp(const SearchScreen(), cache: ApiCache(MemoryCacheStore())));
    await tester.enterText(find.byType(TextField), query);
    // Past the 400 ms debounce, then let the failed request settle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets('shows an error with retry when the search request fails',
      (tester) async {
    await searchFor(tester, 'cowboy');

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(loadErrorText), findsOneWidget);
    expect(offline.requests, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(offline.requests, 2);
    expect(find.text(loadErrorText), findsOneWidget);
  });

  testWidgets('picking a genre in the filters searches again', (tester) async {
    await searchFor(tester, 'cowboy');
    expect(offline.requests, 1);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(offline.requests, 2);
  });

  testWidgets('clearing the query dismisses the error', (tester) async {
    await searchFor(tester, 'cowboy');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text(loadErrorText), findsNothing);
    expect(find.text('Search for anime or manga'), findsOneWidget);
  });
}
