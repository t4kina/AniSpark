import 'dart:async';
import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/blurred_backdrop.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

const _cover = 'https://img.example/cover.jpg';
const _banner = 'https://img.example/banner.jpg';

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

Map<String, dynamic> _media({String? banner}) => {
      'id': 1,
      'type': 'ANIME',
      'title': {'english': 'Cowboy Bebop'},
      'coverImage': {'large': _cover},
      'bannerImage': banner,
    };

Finder _backdrop() => find.byType(BlurredBackdrop);

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  testWidgets('shows the blurred cover behind the header from the first frame', (tester) async {
    final cache = ApiCache(_GatedStore(Completer<void>().future));

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1, initialCoverUrl: _cover), cache: cache));

    expect(find.byType(DetailInfoSkeleton), findsOneWidget, reason: 'still loading');
    expect(tester.widget<BlurredBackdrop>(_backdrop()).url, _cover);
  });

  testWidgets('fades the banner in over the same backdrop once the page loads', (tester) async {
    final gate = Completer<void>();
    final cache = ApiCache(_GatedStore(gate.future));
    await cache.write('anon:media:1', _media(banner: _banner));
    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1, initialCoverUrl: _cover), cache: cache));
    final loadingBackdrop = tester.element(_backdrop());

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.element(_backdrop()), same(loadingBackdrop), reason: 'the backdrop is never rebuilt');
    final banner = tester.widget<CachedNetworkImage>(
      find.byWidgetPredicate((widget) => widget is CachedNetworkImage && widget.imageUrl == _banner),
    );
    expect(banner.fadeInDuration, greaterThan(Duration.zero), reason: 'it fades in over the backdrop');
  });

  testWidgets('keeps the blurred cover when the media has no banner', (tester) async {
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', _media());

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1, initialCoverUrl: _cover), cache: cache));
    await tester.pumpAndSettle();

    expect(tester.widget<BlurredBackdrop>(_backdrop()).url, _cover);
  });

  testWidgets('shimmers while loading when opened without a cover', (tester) async {
    final cache = ApiCache(_GatedStore(Completer<void>().future));

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));

    expect(_backdrop(), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);
  });
}
