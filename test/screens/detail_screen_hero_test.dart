import 'dart:async';
import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/detail/list_action_button.dart';
import 'package:anispark/widgets/motion/collapsing_title_bar.dart';
import 'package:anispark/widgets/motion/cover_hero.dart';
import 'package:anispark/widgets/motion/staggered_entrance.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

/// A store whose reads wait for [gate], so a test can look at the page
/// while it is still loading.
class _GatedStore implements CacheStore {
  _GatedStore(this.gate);

  final Future<void> gate;
  final _store = MemoryCacheStore();

  @override
  Future<String?> read(String key) async {
    await gate;
    return _store.read(key);
  }

  @override
  Future<void> write(String key, String value, DateTime at) => _store.write(key, value, at);

  @override
  Future<void> delete(String key) => _store.delete(key);

  @override
  Future<void> clear() => _store.clear();

  @override
  Iterable<String> get keys => _store.keys;

  @override
  DateTime? writtenAt(String key) => _store.writtenAt(key);
}

const _tag = 'cover:test-list:1';

Map<String, dynamic> _media({List<Map<String, dynamic>> relations = const []}) => {
      'id': 1,
      'type': 'ANIME',
      'title': {'english': 'Cowboy Bebop'},
      'coverImage': {'large': null},
      'relations': {'edges': relations},
    };

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  testWidgets("draws the opening list's cover in its hero while loading", (tester) async {
    final cache = ApiCache(_GatedStore(Completer<void>().future));

    await tester.pumpWidget(appWith(
      const DetailScreen(animeId: 1, heroTag: _tag, initialCoverUrl: 'https://img.example/1.jpg'),
      cache: cache,
    ));

    expect(find.byType(DetailInfoSkeleton), findsOneWidget, reason: 'still loading');
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, _tag);
    final cover = tester.widget<CachedNetworkImage>(
      find.descendant(of: find.byType(Hero), matching: find.byType(CachedNetworkImage)),
    );
    expect(cover.imageUrl, 'https://img.example/1.jpg');
  });

  testWidgets('keeps the same hero when the page loads, so a flight is not cut short', (tester) async {
    final gate = Completer<void>();
    final cache = ApiCache(_GatedStore(gate.future));
    await cache.write('anon:media:1', _media());

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1, heroTag: _tag), cache: cache));
    final loadingHero = tester.state(find.byType(Hero));

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Cowboy Bebop'), findsWidgets);
    expect(tester.state(find.byType(Hero)), same(loadingHero));
    expect(tester.widget<Hero>(find.byType(Hero)).tag, _tag);
  });

  testWidgets('without a list to fly from, the cover keeps its own tag', (tester) async {
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', _media());

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));
    await tester.pump();

    expect(tester.widget<Hero>(find.byType(Hero)).tag, 'cover_1');
  });

  testWidgets('opens a relation with its cover flying from the Relations row', (tester) async {
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', _media(relations: [
      {
        'relationType': 'SEQUEL',
        'node': {
          'id': 2,
          'title': {'english': 'The Movie'},
          'coverImage': {'large': null},
        },
      },
    ]));
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1, heroTag: _tag), cache: cache));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final relationTag = coverHeroTag('detail-1-relations-0', 2);
    expect(
      tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag),
      containsAll([_tag, relationTag]),
    );

    await tester.tap(find.text('The Movie'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final next = tester.widget<DetailScreen>(find.byType(DetailScreen).last);
    expect(next.animeId, 2);
    expect(next.heroTag, relationTag);
  });

  group('what the data fills in', () {
    Finder entranceOf(Finder content) => find.ancestor(of: content, matching: find.byType(StaggeredEntrance)).first;

    int step(WidgetTester tester, Finder content) => tester.widget<StaggeredEntrance>(entranceOf(content)).index;

    double opacity(WidgetTester tester, Finder content) => tester
        .widget<FadeTransition>(find.descendant(of: entranceOf(content), matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    final title = find.text('Cowboy Bebop').first;
    final stats = find.text(tr('detail_average_score', 'English'));
    final actions = find.text(tr('progress', 'English').toUpperCase());
    final seriesInfo = find.text(tr('detail_series_info', 'English'));

    Future<void> pumpLoaded(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cache = ApiCache(MemoryCacheStore());
      await cache.write('anon:media:1', _media());
      await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));
      await tester.pump();
    }

    testWidgets('cascades in from the title down', (tester) async {
      await pumpLoaded(tester);

      expect(step(tester, title), 0);
      expect(step(tester, stats), greaterThan(step(tester, title)));
      expect(step(tester, actions), greaterThan(step(tester, stats)));
      expect(step(tester, seriesInfo), greaterThan(step(tester, actions)));

      await tester.pump(const Duration(milliseconds: 80));
      expect(opacity(tester, title), greaterThan(0), reason: 'the title leads');
      expect(opacity(tester, actions), 0, reason: 'the sections wait their turn');

      // The later steps start on a timer; a second frame plays them out.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(opacity(tester, title), 1);
      expect(opacity(tester, actions), 1);
      expect(opacity(tester, seriesInfo), 1);
    });

    testWidgets('does not cascade again when the page is rebuilt later', (tester) async {
      await pumpLoaded(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final entrance = tester.state(entranceOf(actions));

      // A fresher copy of the data, or anything else, rebuilds the page.
      tester.element(find.byType(DetailScreen)).markNeedsBuild();
      await tester.pump();

      expect(tester.state(entranceOf(actions)), same(entrance));
      expect(opacity(tester, actions), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  testWidgets('scrolled past its title, the page shows it in a bar at the top', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', _media());
    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final barTitle = find.descendant(of: find.byType(CollapsingTitleBar), matching: find.text('Cowboy Bebop'));
    expect(barTitle, findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pump();

    expect(barTitle, findsOneWidget);
    expect(tester.getCenter(barTitle).dx, 200, reason: 'centred, clear of the buttons');
    expect(find.byTooltip(tr('tooltip_back', 'English')), findsOneWidget, reason: 'the buttons stay over the bar');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pump();
    expect(barTitle, findsNothing);
  });

  testWidgets('the add button is the status chip once the series is in the list', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<List<bool>> highlights(Map<String, dynamic>? entry) async {
      final cache = ApiCache(MemoryCacheStore());
      await cache.write('anon:media:1', {..._media(), 'mediaListEntry': entry});
      await tester.pumpWidget(appWith(DetailScreen(key: UniqueKey(), animeId: 1), cache: cache));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      return [for (final button in tester.widgetList<ListActionButton>(find.byType(ListActionButton))) button.highlighted];
    }

    expect(await highlights(null), [false, false, false]);
    expect(find.text(tr('add_to_list', 'English').toUpperCase()), findsOneWidget);

    expect(await highlights({'id': 5, 'status': 'CURRENT', 'progress': 3, 'score': 0}), [true, false, false]);
    expect(find.text(tr('add_to_list', 'English').toUpperCase()), findsNothing);
  });
}
