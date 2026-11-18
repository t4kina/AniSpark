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
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget,
        reason: 'the filter button counts the genres picked');
  });

  testWidgets('the content type and the sort are pickers of the same shape, and no filter is counted yet',
      (tester) async {
    await tester.pumpWidget(screenApp(const SearchScreen(), cache: ApiCache(MemoryCacheStore())));
    await tester.pump();

    BoxDecoration pillOf(String label) => tester
        .widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    final type = pillOf('All');
    final sort = pillOf('Popularity');
    expect(type.color, isNotNull);
    expect(type.color, sort.color);
    expect(type.borderRadius, sort.borderRadius);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('clearing the query dismisses the error', (tester) async {
    await searchFor(tester, 'cowboy');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text(loadErrorText), findsNothing);
    expect(find.text('Search for anime or manga'), findsOneWidget);
  });

  testWidgets('without Cancel the field keeps the page margin at its right', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screenApp(const SearchScreen(), cache: ApiCache(MemoryCacheStore())));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget, reason: 'it opens focused');
    expect(tester.getTopRight(find.byType(TextField)).dx, lessThan(tester.getTopLeft(find.text('Cancel')).dx));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing);
    expect(tester.getTopRight(find.byType(TextField)).dx, 400 - 16);
  });

  testWidgets('a recent search is removed with a cross that has a whole finger of room', (tester) async {
    SharedPreferences.setMockInitialValues({recentSearchesPrefsKey: ['frieren', 'bebop']});
    await tester.pumpWidget(screenApp(const SearchScreen(), cache: ApiCache(MemoryCacheStore())));
    await tester.pumpAndSettle();
    expect(find.text('frieren'), findsOneWidget);

    final cross = find.bySemanticsLabel('Remove from recent searches').first;
    expect(tester.getSize(cross).width, greaterThanOrEqualTo(36));
    expect(tester.getSize(cross).height, greaterThanOrEqualTo(36));

    // Near the edge of its area, well away from the drawn cross.
    await tester.tapAt(tester.getTopLeft(cross) + const Offset(3, 3));
    await tester.pumpAndSettle();

    expect(find.text('frieren'), findsNothing);
    expect(find.text('bebop'), findsOneWidget);
    expect(offline.requests, 0, reason: 'removing it does not search for it');
  });
}
