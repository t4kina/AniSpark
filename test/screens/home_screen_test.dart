import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/screens/home_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/theme/app_layout.dart';
import 'package:anispark/widgets/anime_card.dart';
import 'package:anispark/widgets/home_spotlight.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

    // Once leading the page, once in its row.
    expect(find.text('Cowboy Bebop'), findsNWidgets(2));
    expect(find.text(loadErrorText), findsNothing);
  });

  testWidgets('what scrolls under the search bar keeps a margin from it', (tester) async {
    await cache.write('discover:trending', [
      {'id': 1, 'title': {'english': 'Cowboy Bebop'}, 'averageScore': 86},
    ]);
    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
    await tester.pump();

    final field = tester.getRect(find.byType(TextField));
    final page = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(page.top - field.bottom, greaterThanOrEqualTo(AppSpace.md));
  });

  group('the spotlight', () {
    Future<void> pumpHome(WidgetTester tester, List<Map<String, dynamic>> trending) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await cache.write('discover:trending', trending);
      await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('leads the page with what is trending most: its title, score and genres', (tester) async {
      await pumpHome(tester, [
        {
          'id': 1,
          'title': {'english': 'Cowboy Bebop'},
          'averageScore': 86,
          'genres': ['Action', 'Sci-Fi', 'Drama'],
          'bannerImage': 'https://img.example/banner.jpg',
        },
        {'id': 2, 'title': {'english': 'Trigun'}, 'averageScore': 80},
      ]);

      final spotlight = find.byType(HomeSpotlight);
      expect(spotlight, findsOneWidget);
      expect(find.descendant(of: spotlight, matching: find.text('Cowboy Bebop')), findsOneWidget);
      expect(find.descendant(of: spotlight, matching: find.text('#1')), findsOneWidget);
      expect(find.descendant(of: spotlight, matching: find.textContaining(RegExp(r'8\.6 . Action . Sci-Fi$'))), findsOneWidget);
      expect(find.descendant(of: spotlight, matching: find.text('Trigun')), findsNothing);
      expect(tester.getTopLeft(spotlight).dy, lessThan(tester.getTopLeft(find.byType(AnimeCard).first).dy),
          reason: 'above the rows');
      final banner = tester.widgetList<CachedNetworkImage>(
        find.descendant(of: spotlight, matching: find.byType(CachedNetworkImage)),
      );
      expect(banner.map((image) => image.imageUrl), contains('https://img.example/banner.jpg'));
    });

    testWidgets('a tap opens its page', (tester) async {
      await pumpHome(tester, [
        {'id': 1, 'title': {'english': 'Cowboy Bebop'}, 'averageScore': 86},
      ]);

      await tester.tap(find.byType(HomeSpotlight));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(tester.widget<DetailScreen>(find.byType(DetailScreen)).animeId, 1);
    });

    testWidgets('its banner fills the box: no cover, the title large and a button to open it', (tester) async {
      await pumpHome(tester, [
        {
          'id': 1,
          'title': {'english': 'Cowboy Bebop'},
          'averageScore': 86,
          'bannerImage': 'https://img.example/banner.jpg',
          'coverImage': {'large': 'https://img.example/cover.jpg'},
        },
      ]);

      final spotlight = find.byType(HomeSpotlight);
      final images = tester.widgetList<CachedNetworkImage>(
        find.descendant(of: spotlight, matching: find.byType(CachedNetworkImage)),
      );
      expect(images.map((image) => image.imageUrl), ['https://img.example/banner.jpg']);
      expect(find.descendant(of: spotlight, matching: find.text('Open')), findsOneWidget);
      expect(find.descendant(of: spotlight, matching: find.text('trending')), findsOneWidget);
      expect(tester.getSize(spotlight).height, greaterThanOrEqualTo(HomeSpotlight.height));
    });

    testWidgets('is not there when nothing is trending', (tester) async {
      await pumpHome(tester, []);

      expect(find.byType(HomeSpotlight), findsNothing);
    });
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

  testWidgets('shows the shape of its rows in the app skeleton while they load', (tester) async {
    await tester.pumpWidget(screenApp(const HomeScreen(), cache: cache));

    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.descendant(of: find.byType(Skeleton), matching: find.byType(SkeletonBox)), findsWidgets);
    // Let the failed requests settle.
    await tester.pump();
  });
}
