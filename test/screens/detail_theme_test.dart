import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/detail/detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  testWidgets("uses the app's accent colour, not the cover's", (tester) async {
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', {
      'id': 1,
      'type': 'ANIME',
      'title': {'english': 'Cowboy Bebop'},
      // AniList's colour for this cover, which used to tint the page.
      'coverImage': {'large': null, 'color': '#f16b50'},
    });

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache));
    await tester.pumpAndSettle();

    final appPrimary = Theme.of(tester.element(find.byType(DetailScreen))).colorScheme.primary;
    final pagePrimary = Theme.of(tester.element(find.byType(DetailHeader))).colorScheme.primary;
    expect(pagePrimary, appPrimary);
  });
}
