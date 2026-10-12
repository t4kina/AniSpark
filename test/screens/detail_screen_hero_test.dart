import 'dart:async';
import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/motion/cover_hero.dart';
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
}
