import 'dart:io';

import 'package:anispark/screens/browse_screen.dart';
import 'package:anispark/screens/studio_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/browse_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/detail/detail_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../screens/screen_harness.dart';

String _en(String key, [Map<String, Object>? values]) =>
    values == null ? tr(key, 'English') : trf(key, 'English', values);

Map<String, dynamic> _tag(String name, int rank, {bool spoiler = false}) =>
    {'name': name, 'rank': rank, 'isMediaSpoiler': spoiler};

Map<String, dynamic> _link(String site, String type, {String? color, String? language, String? url}) => {
      'site': site,
      'type': type,
      'url': url ?? 'https://example.com/${site.toLowerCase()}',
      'color': color,
      'icon': null,
      'language': language,
    };

void main() {
  // The grid a genre opens loads with the shared client.
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      cache: ApiCache(MemoryCacheStore()),
    ));
  }

  group('GenreChips', () {
    testWidgets('a genre opens the grid of its anime, already filtered by it', (tester) async {
      await pump(tester, const GenreChips(genres: ['Action', 'Sci-Fi'], isManga: false));
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Sci-Fi'), findsOneWidget);

      await tester.tap(find.text('Sci-Fi'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final grid = tester.widget<BrowseScreen>(find.byType(BrowseScreen));
      expect(grid.query.genres, {'Sci-Fi'});
      expect(grid.query.type, BrowseQuery.anime);
      expect(grid.title, 'SCI-FI');
    });

    testWidgets('on a manga it opens the manga of that genre', (tester) async {
      await pump(tester, const GenreChips(genres: ['Drama'], isManga: true));

      await tester.tap(find.text('Drama'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.widget<BrowseScreen>(find.byType(BrowseScreen)).query.type, BrowseQuery.manga);
    });

    testWidgets('each genre has its own colour and icon, the name in the page text colour', (tester) async {
      await pump(tester, const GenreChips(genres: ['Action', 'Romance', 'Made Up'], isManga: false));

      Color? iconColor(IconData icon) => IconTheme.of(tester.element(find.byIcon(icon))).color;
      expect(iconColor(Icons.bolt_rounded), genreStyles['Action']!.color);
      expect(iconColor(Icons.favorite_rounded), genreStyles['Romance']!.color);
      expect(find.byIcon(fallbackGenreStyle.icon), findsOneWidget, reason: 'a genre AniList adds later');
      final onSurface = Theme.of(tester.element(find.text('Action'))).colorScheme.onSurface;
      expect(tester.widget<Text>(find.text('Action')).style?.color, onSurface);
    });
  });

  group('TagChips', () {
    testWidgets('each tag says how much it weighs, and the spoilers stay hidden until asked for', (tester) async {
      await pump(
        tester,
        TagChips(tags: [
          _tag('Elf', 94),
          _tag('Travel', 88),
          _tag('Hero Dies', 80, spoiler: true),
          _tag('Twist', 60, spoiler: true),
        ]),
      );

      expect(find.text('Elf'), findsOneWidget);
      expect(find.text('94'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Hero Dies'), findsNothing);
      final show = _en('detail_show_spoiler_tags', {'n': 2});

      await tester.tap(find.text(show));
      await tester.pumpAndSettle();
      expect(find.text('Hero Dies'), findsOneWidget);
      expect(find.text('Twist'), findsOneWidget);
      expect(find.text(show), findsNothing);

      await tester.tap(find.text(_en('detail_hide_spoiler_tags')));
      await tester.pumpAndSettle();
      expect(find.text('Hero Dies'), findsNothing);
    });

    testWidgets('past the first few, the rest are a tap away', (tester) async {
      final tags = [for (var i = 1; i <= 14; i++) _tag('Tag $i', 100 - i)];
      await pump(tester, TagChips(tags: tags));

      expect(find.text('Tag ${TagChips.collapsedCount}'), findsOneWidget);
      expect(find.text('Tag ${TagChips.collapsedCount + 1}'), findsNothing);

      await tester.tap(find.text(_en('detail_show_all_tags', {'n': 14})));
      await tester.pumpAndSettle();
      expect(find.text('Tag 14'), findsOneWidget);

      await tester.tap(find.text(_en('detail_show_less')));
      await tester.pumpAndSettle();
      expect(find.text('Tag 14'), findsNothing);
    });

    testWidgets('a short list without spoilers has nothing to toggle', (tester) async {
      await pump(tester, TagChips(tags: [_tag('Elf', 94), _tag('Travel', 88)]));

      expect(find.textContaining('Spoiler'), findsNothing);
      expect(find.text(_en('detail_show_less')), findsNothing);
    });

    testWidgets('showing the spoilers shows all of them, folded or not', (tester) async {
      final tags = [
        for (var i = 1; i <= 12; i++) _tag('Tag $i', 100 - i),
        for (var i = 1; i <= 3; i++) _tag('Spoiler $i', 50 - i, spoiler: true),
      ];
      await pump(tester, TagChips(tags: tags));

      expect(find.text(_en('detail_show_all_tags', {'n': 12})), findsOneWidget,
          reason: 'show all counts the tags that are not spoilers');
      await tester.tap(find.text(_en('detail_show_spoiler_tags', {'n': 3})));
      await tester.pumpAndSettle();

      for (var i = 1; i <= 3; i++) {
        expect(find.text('Spoiler $i'), findsOneWidget);
      }
      expect(find.text('Tag 12'), findsNothing, reason: 'the other tags stay folded');
    });
  });

  group('ExternalLinks', () {
    final links = [
      _link('Crunchyroll', 'STREAMING', color: '#F47521', language: 'English'),
      _link('Netflix', 'STREAMING', color: '#E50914'),
      _link('Official Site', 'INFO'),
      _link('Twitter', 'SOCIAL', color: '#1DA1F2'),
    ];

    testWidgets('where to watch comes first, as cards two to a row; the rest are chips under it', (tester) async {
      await pump(tester, ExternalLinks(links: links, isManga: false, onOpenUrl: (_) {}));

      final watch = find.text(_en('detail_where_to_watch').toUpperCase());
      final more = find.text(_en('detail_more_links').toUpperCase());
      expect(watch, findsOneWidget);
      expect(more, findsOneWidget);
      final crunchyroll = tester.getRect(find.text('Crunchyroll'));
      final netflix = tester.getRect(find.text('Netflix'));
      expect(netflix.left, greaterThan(200), reason: 'in the second half of the row');
      expect(netflix.center.dy, greaterThan(crunchyroll.top), reason: 'side by side');
      expect(netflix.center.dy, lessThan(tester.getRect(find.text('English')).bottom));
      expect(tester.getTopLeft(more).dy, greaterThan(crunchyroll.bottom));
      expect(tester.getTopLeft(find.text('Official Site')).dy, greaterThan(tester.getTopLeft(more).dy));
      expect(find.text('English'), findsOneWidget, reason: 'the language a service has it in');
    });

    testWidgets('a manga is read, not watched', (tester) async {
      await pump(tester, ExternalLinks(links: links, isManga: true, onOpenUrl: (_) {}));

      expect(find.text(_en('detail_where_to_read').toUpperCase()), findsOneWidget);
      expect(find.text(_en('detail_where_to_watch').toUpperCase()), findsNothing);
    });

    testWidgets('a card or a chip opens its link', (tester) async {
      final opened = <String>[];
      await pump(tester, ExternalLinks(links: links, isManga: false, onOpenUrl: opened.add));

      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twitter'));
      await tester.pumpAndSettle();

      expect(opened, ['https://example.com/netflix', 'https://example.com/twitter']);
    });

    testWidgets('only what there is gets a heading', (tester) async {
      await pump(tester, ExternalLinks(links: [_link('Official Site', 'INFO')], isManga: false, onOpenUrl: (_) {}));

      expect(find.text(_en('detail_where_to_watch').toUpperCase()), findsNothing);
      expect(find.text(_en('detail_more_links').toUpperCase()), findsOneWidget);
    });

    testWidgets('shows nothing without a link that can be opened', (tester) async {
      await pump(
        tester,
        ExternalLinks(links: [_link('Broken', 'STREAMING', url: '')], isManga: false, onOpenUrl: (_) {}),
      );

      expect(find.text('Broken'), findsNothing);
      expect(find.text(_en('detail_where_to_watch').toUpperCase()), findsNothing);
    });

    test('reads the colour AniList sends, and only that shape', () {
      expect(ExternalLinks.colorOf({'color': '#F47521'}), const Color(0xFFF47521));
      expect(ExternalLinks.colorOf({'color': 'orange'}), isNull);
      expect(ExternalLinks.colorOf({'color': '#FFF'}), isNull);
      expect(ExternalLinks.colorOf({'color': null}), isNull);
    });
  });

  group('ProducerChips', () {
    const studios = [
      {'id': 1, 'name': 'Aniplex', 'isAnimationStudio': false},
      {'id': 2, 'name': 'Bones', 'isAnimationStudio': true},
      {'id': 3, 'name': 'Square Enix', 'isAnimationStudio': false},
      {'name': 'No Id', 'isAnimationStudio': false},
    ];

    testWidgets('shows the producers that can be opened, in plain chips', (tester) async {
      await pump(tester, const ProducerChips(studios: studios));

      expect(find.text('Aniplex'), findsOneWidget);
      expect(find.text('Square Enix'), findsOneWidget);
      expect(find.text('Bones'), findsNothing, reason: 'the animation studio is shown under the title');
      expect(find.text('No Id'), findsNothing);
      expect(find.byIcon(Icons.business_rounded), findsNWidgets(2));
      final quiet = Theme.of(tester.element(find.text('Aniplex'))).colorScheme.surfaceContainerHighest;
      final chip = tester.widget<Container>(
        find.ancestor(of: find.text('Aniplex'), matching: find.byType(Container)).first,
      );
      expect((chip.decoration! as BoxDecoration).color, quiet, reason: 'the genres carry the colour, not the producers');
    });

    testWidgets('a producer opens its studio page', (tester) async {
      await pump(tester, const ProducerChips(studios: studios));

      await tester.tap(find.text('Aniplex'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.widget<StudioScreen>(find.byType(StudioScreen)).studioId, 1);
    });
  });
}
