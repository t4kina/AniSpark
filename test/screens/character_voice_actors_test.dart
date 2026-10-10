import 'dart:io';

import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/screens/staff_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/people_api.dart';
import 'package:anispark/widgets/people/person_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

Map<String, dynamic> _actor(int id, String name, String language) => {
      'id': id,
      'name': {'full': name},
      'languageV2': language,
    };

http.Response _character() => jsonResponse({
      'data': {
        'Character': {
          'id': 1,
          'isFavourite': false,
          'name': {'full': 'Spike Spiegel'},
          'description': 'A __bounty__ hunter. ~!Secret!~',
          'media': {
            'edges': [
              {
                'node': {
                  'id': 1,
                  'type': 'ANIME',
                  'title': {'romaji': 'Cowboy Bebop (romaji)', 'english': 'Cowboy Bebop'},
                },
                'voiceActors': [
                  _actor(20, 'Steven Blum', 'English'),
                  _actor(30, 'Genaro Vasquez', 'Spanish'),
                  _actor(10, 'Kouichi Yamadera', 'Japanese'),
                ],
              },
              {
                'node': {'id': 2, 'type': 'ANIME', 'isAdult': true, 'title': {'english': 'Adult show'}},
                'voiceActors': [_actor(40, 'Adult only', 'Japanese')],
              },
            ],
          },
        },
      },
    });

void main() {
  // The staff page opened from a voice actor loads offline.
  final offline = OfflineHttpOverrides();
  late ApiCache cache;
  late List<RecordedRequest> log;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  PeopleApi apiAnswering(http.Response Function(RecordedRequest) handler) =>
      PeopleApi(service: AniListService(client: mockAniList(log, handler)));

  Future<void> pumpCharacter(WidgetTester tester, {AuthService? auth}) async {
    await tester.pumpWidget(appWith(
      CharacterScreen(characterId: 1, api: apiAnswering((_) => _character())),
      cache: cache,
      auth: auth,
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  double leftOf(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dx;

  testWidgets('lists the voice actors, Japanese first, without adult media', (tester) async {
    await pumpCharacter(tester);

    expect(find.byType(PersonCard), findsNWidgets(3));
    expect(leftOf(tester, 'Kouichi Yamadera'), lessThan(leftOf(tester, 'Steven Blum')));
    expect(leftOf(tester, 'Steven Blum'), lessThan(leftOf(tester, 'Genaro Vasquez')));
    expect(find.text('Adult only'), findsNothing);
    expect(find.text('Adult show'), findsNothing);
    expect(log.single.authorization, isNull, reason: 'logged out');
  });

  testWidgets('puts the dub in the app language right after the Japanese cast', (tester) async {
    SharedPreferences.setMockInitialValues({'language': 'Spanish'});
    final settings = SettingsProvider();
    await settings.load();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>(create: (_) => FakeAuthService()),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(home: CharacterScreen(characterId: 1, api: apiAnswering((_) => _character()))),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(leftOf(tester, 'Kouichi Yamadera'), lessThan(leftOf(tester, 'Genaro Vasquez')));
    expect(leftOf(tester, 'Genaro Vasquez'), lessThan(leftOf(tester, 'Steven Blum')));
  });

  testWidgets('shows the cleaned description and titles in the chosen language', (tester) async {
    await pumpCharacter(tester);

    // The collapsed and expanded copies of the text are both built.
    expect(find.text('A bounty hunter. [Spoiler]'), findsWidgets);
    expect(find.textContaining('Secret'), findsNothing);
    // "Appears in" is below the test screen's fold.
    expect(find.text('Cowboy Bebop', skipOffstage: false), findsOneWidget);
    expect(find.text('Cowboy Bebop (romaji)', skipOffstage: false), findsNothing);
    expect(await cache.read('anon:character:1'), isNotNull);
  });

  testWidgets('sends the token and caches per viewer when logged in', (tester) async {
    await pumpCharacter(tester, auth: FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7}));

    expect(log.single.authorization, 'Bearer tok');
    expect(await cache.read(ApiCache.userKey(7, 'character:1')), isNotNull);
  });

  testWidgets('opens the staff page of a voice actor', (tester) async {
    await pumpCharacter(tester);

    await tester.tap(find.text('Kouichi Yamadera'));
    await tester.pumpAndSettle();

    final screen = tester.widget<StaffScreen>(find.byType(StaffScreen));
    expect(screen.staffId, 10);
    expect(screen.name, 'Kouichi Yamadera');
  });
}
