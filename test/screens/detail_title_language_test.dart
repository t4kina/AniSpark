import 'dart:io';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import 'screen_harness.dart';

Map<String, dynamic> _title(String english, String romaji, String native) =>
    {'english': english, 'romaji': romaji, 'native': native};

Map<String, dynamic> _media() => {
      'id': 1,
      'type': 'ANIME',
      'title': _title('Cowboy Bebop', 'Cowboy Bebop', 'カウボーイビバップ'),
      'coverImage': {'large': null},
      'relations': {
        'edges': [
          {
            'relationType': 'SEQUEL',
            'node': {'id': 2, 'type': 'ANIME', 'title': _title('Attack on Titan', 'Shingeki no Kyojin', '進撃の巨人')},
          },
        ],
      },
      'recommendations': {
        'nodes': [
          {
            'rating': 12,
            'mediaRecommendation': {
              'id': 3,
              'title': _title('Fullmetal Alchemist', 'Hagane no Renkinjutsushi', '鋼の錬金術師'),
            },
          },
        ],
      },
    };

void main() {
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  Future<void> pumpDetail(WidgetTester tester, String titleLanguage) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'titleLanguage': titleLanguage});
    final settings = SettingsProvider();
    await settings.load();
    final cache = ApiCache(MemoryCacheStore());
    await cache.write('anon:media:1', _media());

    await tester.pumpWidget(appWith(const DetailScreen(animeId: 1), cache: cache, settings: settings));
    await tester.pumpAndSettle();
  }

  testWidgets('relations and recommendations follow the Romaji title setting', (tester) async {
    await pumpDetail(tester, 'Romaji');

    expect(find.text('Shingeki no Kyojin'), findsOneWidget);
    expect(find.text('Hagane no Renkinjutsushi'), findsOneWidget);
    expect(find.text('Attack on Titan'), findsNothing);
    expect(find.text('Fullmetal Alchemist'), findsNothing);
  });

  testWidgets('relations and recommendations follow the Native title setting', (tester) async {
    await pumpDetail(tester, 'Native');

    expect(find.text('進撃の巨人'), findsOneWidget);
    expect(find.text('鋼の錬金術師'), findsOneWidget);
  });

  testWidgets('relations and recommendations keep English by default', (tester) async {
    await pumpDetail(tester, 'English');

    expect(find.text('Attack on Titan'), findsOneWidget);
    expect(find.text('Fullmetal Alchemist'), findsOneWidget);
  });
}
