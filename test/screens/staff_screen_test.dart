import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/screens/staff_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/people_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/people/media_cover_tile.dart';
import 'package:anispark/widgets/people/voiced_character_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import 'screen_harness.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _media(int id, {bool isAdult = false}) => {
      'id': id,
      'type': 'ANIME',
      'format': 'TV',
      'isAdult': isAdult,
      'title': {'english': 'Show $id'},
    };

Map<String, dynamic> _voiced(int characterId, int mediaId) => {
      'characterRole': 'MAIN',
      'node': _media(mediaId),
      'characters': [
        {'id': characterId, 'name': {'full': 'Character $characterId'}},
      ],
    };

Map<String, dynamic> _connection(List<Object?> edges, {bool hasNextPage = false}) => {
      'pageInfo': {'hasNextPage': hasNextPage},
      'edges': edges,
    };

http.Response _staff({
  List<Object?> characters = const [],
  List<Object?> roles = const [],
  bool moreCharacters = false,
}) =>
    jsonResponse({
      'data': {
        'Staff': {
          'id': 1,
          'name': {'full': 'Kouichi Yamadera', 'native': 'Native Name'},
          'primaryOccupations': ['Voice Actor', 'Singer'],
          'description': '__Height:__ 176cm',
          'homeTown': 'Shiogama',
          'characterMedia': _connection(characters, hasNextPage: moreCharacters),
          'staffMedia': _connection(roles),
        },
      },
    });

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  PeopleApi apiAnswering(http.Response Function(RecordedRequest) handler) =>
      PeopleApi(service: AniListService(client: mockAniList(log, handler)));

  // Spinners never settle, so pump a fixed number of frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpStaff(WidgetTester tester, PeopleApi api) async {
    await tester.pumpWidget(appWith(StaffScreen(staffId: 1, api: api), cache: cache));
    await settle(tester);
  }

  testWidgets('shows the profile and the voiced characters, and caches them', (tester) async {
    await pumpStaff(
      tester,
      apiAnswering((_) => _staff(characters: [_voiced(1, 10), _voiced(2, 11)])),
    );

    expect(find.text('Kouichi Yamadera'), findsOneWidget);
    expect(find.text('Native Name'), findsOneWidget);
    expect(find.text('Voice Actor · Singer'), findsOneWidget);
    expect(find.text('Height: 176cm'), findsWidgets, reason: 'markdown is cleaned (collapsed and expanded copies)');
    expect(find.text('Shiogama'), findsOneWidget);
    expect(find.byType(VoicedCharacterTile), findsNWidgets(2));
    expect(find.text('Character 1'), findsOneWidget);
    expect(find.text('Show 10'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is SegmentedButton), findsNothing);
    expect(log, hasLength(1));
    expect(await cache.read('staff:1'), isNotNull);
  });

  testWidgets('switches between voiced characters and staff roles', (tester) async {
    await pumpStaff(
      tester,
      apiAnswering((_) => _staff(
            characters: [_voiced(1, 10), _voiced(2, 11)],
            roles: [
              {'staffRole': 'Theme Song Performance', 'node': _media(20)},
            ],
          )),
    );
    expect(find.byType(VoicedCharacterTile), findsNWidgets(2));

    await tester.tap(find.text(_en('staff_roles')));
    await settle(tester);

    expect(find.byType(VoicedCharacterTile), findsNothing);
    expect(find.byType(MediaCoverTile), findsOneWidget);
    expect(find.text('Show 20'), findsOneWidget);
    expect(find.text('Theme Song Performance'), findsOneWidget);
  });

  testWidgets('shows only staff roles for someone who voiced nobody', (tester) async {
    await pumpStaff(
      tester,
      apiAnswering((_) => _staff(roles: [
            {'staffRole': 'Director', 'node': _media(20)},
            {'staffRole': 'Storyboard', 'node': _media(20)},
            {'staffRole': 'Director', 'node': _media(21, isAdult: true)},
          ])),
    );

    expect(find.byType(MediaCoverTile), findsOneWidget);
    expect(find.text('Director, Storyboard'), findsOneWidget);
    expect(find.text('Show 21'), findsNothing, reason: 'adult media are left out');
    expect(find.text(_en('staff_roles').toUpperCase()), findsOneWidget);
  });

  testWidgets('loads the next page of voiced characters near the end of the list', (tester) async {
    await pumpStaff(
      tester,
      apiAnswering((request) {
        if (request.query.contains('characterMedia(page: \$page')) {
          return jsonResponse({
            'data': {
              'Staff': {'characterMedia': _connection([_voiced(3, 12), _voiced(1, 13)])},
            },
          });
        }
        return _staff(characters: [_voiced(1, 10), _voiced(2, 11)], moreCharacters: true);
      }),
    );

    expect(log, hasLength(2));
    expect(log.last.variables, {'id': 1, 'page': 2, 'perPage': PeopleApi.staffPageSize});
    expect(find.text('Character 3'), findsOneWidget);
    expect(find.text('Character 1'), findsOneWidget, reason: 'a character already shown is not repeated');
    expect(find.byType(VoicedCharacterTile), findsNWidgets(3));
  });

  testWidgets('opens a voiced character', (tester) async {
    await pumpStaff(tester, apiAnswering((_) => _staff(characters: [_voiced(1, 10)])));

    await tester.ensureVisible(find.text('Character 1'));
    await tester.pump();
    await tester.tap(find.text('Character 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CharacterScreen), findsOneWidget);
    expect(tester.widget<CharacterScreen>(find.byType(CharacterScreen)).characterId, 1);
  });

  testWidgets('shows an error with retry when the page fails to load', (tester) async {
    await pumpStaff(tester, apiAnswering((_) => jsonResponse({'errors': []}, status: 500)));

    expect(find.text(loadErrorText), findsOneWidget);
    expect(log, hasLength(1));

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(log, hasLength(2));
  });
}
