import 'dart:convert';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/people_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

Map<String, dynamic> _media(int id, {bool isAdult = false, String type = 'ANIME', String? english}) => {
      'id': id,
      'type': type,
      'format': type == 'MANGA' ? 'MANGA' : 'TV',
      'isAdult': isAdult,
      'averageScore': 84,
      'title': {'romaji': 'Romaji $id', 'english': ?english, 'native': null},
      'coverImage': {'large': 'https://img/m$id.jpg'},
      'startDate': {'year': 2006},
    };

Map<String, dynamic> _person(int id, String name, {String? language}) => {
      'id': id,
      'name': {'full': name},
      'image': {'large': null, 'medium': 'https://img/p$id.jpg'},
      'languageV2': ?language,
    };

Map<String, dynamic> _connection(List<Object?> edges, {bool hasNextPage = false}) => {
      'pageInfo': {'hasNextPage': hasNextPage},
      'edges': edges,
    };

/// What the cache does with a value: encode it, then decode it again.
Object? _throughCache(Object value) => jsonDecode(jsonEncode(value));

void main() {
  late List<RecordedRequest> log;

  setUp(() => log = []);

  PeopleApi apiAnswering(http.Response Function(RecordedRequest request) handler) =>
      PeopleApi(service: AniListService(client: mockAniList(log, handler)));

  PeopleApi apiReturning(Object body, {int status = 200}) =>
      apiAnswering((_) => jsonResponse(body, status: status));

  group('getStaff', () {
    final staffBody = {
      'data': {
        'Staff': {
          'id': 95011,
          'name': {'full': 'Kouichi Yamadera', 'native': '山寺宏一'},
          'image': {'large': 'https://img/s.jpg'},
          'description': '__Height:__ 176cm',
          'primaryOccupations': ['Voice Actor', null, 3, 'Singer'],
          'gender': 'Male',
          'age': 65,
          'yearsActive': [1985, 'x'],
          'homeTown': 'Shiogama',
          'bloodType': 'A',
          'favourites': 763,
          'dateOfBirth': {'year': 1961, 'month': 6, 'day': 17},
          'dateOfDeath': {'year': null, 'month': null, 'day': null},
          'characterMedia': _connection([
            {
              'characterRole': 'MAIN',
              'node': _media(1, english: 'Cowboy Bebop'),
              'characters': [_person(1, 'Spike Spiegel'), 'junk', _person(2, 'Faye')],
            },
            // The same character in another media is listed once.
            {'characterRole': 'MAIN', 'node': _media(5), 'characters': [_person(1, 'Spike Spiegel')]},
            {'characterRole': 'MAIN', 'node': _media(6, isAdult: true), 'characters': [_person(3, 'Hidden')]},
            {'node': null, 'characters': [_person(4, 'No media')]},
            'not an edge',
          ], hasNextPage: true),
          'staffMedia': _connection([
            {'staffRole': 'Theme Song Performance (OP)', 'node': _media(10)},
            {'staffRole': 'Theme Song Performance (ED)', 'node': _media(10)},
            {'staffRole': 'Narrator', 'node': _media(11, isAdult: true)},
            {'staffRole': null, 'node': _media(12, type: 'MANGA')},
          ]),
        },
      },
    };

    test('asks for the staff member and the first page of both lists, without a token', () async {
      final api = apiReturning(staffBody);

      await api.getStaff(95011);

      final request = log.single;
      expect(request.variables, {'id': 95011, 'perPage': PeopleApi.staffPageSize});
      expect(request.authorization, isNull, reason: 'staff pages are public');
      expect(request.query, contains('Staff(id: \$id)'));
      expect(request.query, contains('characterMedia(page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID])'));
      expect(request.query, contains('staffMedia(page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID])'));
    });

    test('parses the profile, skipping malformed values', () async {
      final staff = await apiReturning(staffBody).getStaff(95011);

      expect(staff.id, 95011);
      expect(staff.name, 'Kouichi Yamadera');
      expect(staff.nativeName, '山寺宏一');
      expect(staff.imageUrl, 'https://img/s.jpg');
      expect(staff.description, '__Height:__ 176cm');
      expect(staff.occupations, ['Voice Actor', 'Singer']);
      expect(staff.age, 65);
      expect(staff.yearsActive, [1985]);
      expect(staff.homeTown, 'Shiogama');
      expect(staff.favourites, 763);
      expect(staff.dateOfBirth?.toJson(), {'year': 1961, 'month': 6, 'day': 17});
      expect(staff.dateOfDeath, isNull, reason: 'an all-null date means unknown');
    });

    test('lists each voiced character once and leaves out adult media', () async {
      final staff = await apiReturning(staffBody).getStaff(95011);

      final characters = staff.characters.items;
      expect(characters.map((c) => c.character.name), ['Spike Spiegel', 'Faye']);
      expect(characters.first.media.id, 1, reason: 'the most popular media is kept');
      expect(characters.first.media.title, {'romaji': 'Romaji 1', 'english': 'Cowboy Bebop'});
      expect(characters.first.role, 'MAIN');
      expect(staff.characters.hasNextPage, isTrue);
    });

    test('groups the roles of each media and leaves out adult media', () async {
      final staff = await apiReturning(staffBody).getStaff(95011);

      final roles = staff.roles.items;
      expect(roles.map((r) => r.media.id), [10, 12]);
      expect(roles.first.roles, ['Theme Song Performance (OP)', 'Theme Song Performance (ED)']);
      expect(roles.last.roles, isEmpty);
      expect(roles.last.media.isManga, isTrue);
      expect(staff.roles.hasNextPage, isFalse);
    });

    test('survives the cache round trip', () async {
      final staff = await apiReturning(staffBody).getStaff(95011);

      final cached = StaffDetail.fromJson(_throughCache(staff))!;

      expect(cached.name, staff.name);
      expect(cached.occupations, staff.occupations);
      expect(cached.dateOfBirth?.toJson(), staff.dateOfBirth?.toJson());
      expect(cached.characters.items.map((c) => c.character.id), [1, 2]);
      expect(cached.characters.hasNextPage, isTrue);
      expect(cached.roles.items.first.roles, staff.roles.items.first.roles);
      expect(cached.roles.items.last.roles, isEmpty);
    });

    test('throws when AniList has no such staff member', () async {
      await expectLater(
        apiReturning({'data': {'Staff': null}}).getStaff(1),
        throwsA(isA<AniListRequestException>()),
      );
      await expectLater(
        apiReturning({'errors': [{'message': 'Not Found.'}]}, status: 404).getStaff(1),
        throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('next pages of a staff member', () {
    test('getVoicedCharacters asks for the page and parses it', () async {
      final api = apiReturning({
        'data': {
          'Staff': {
            'characterMedia': _connection([
              {'characterRole': 'SUPPORTING', 'node': _media(3), 'characters': [_person(9, 'Jet')]},
            ], hasNextPage: true),
          },
        },
      });

      final page = await api.getVoicedCharacters(95011, page: 2);

      expect(log.single.variables, {'id': 95011, 'page': 2, 'perPage': PeopleApi.staffPageSize});
      expect(log.single.query, contains('characterMedia(page: \$page, perPage: \$perPage'));
      expect(page.items.single.character.name, 'Jet');
      expect(page.hasNextPage, isTrue);
    });

    test('getStaffRoles asks for the page and parses it', () async {
      final api = apiReturning({
        'data': {
          'Staff': {
            'staffMedia': _connection([{'staffRole': 'Director', 'node': _media(3)}]),
          },
        },
      });

      final page = await api.getStaffRoles(7, page: 3);

      expect(log.single.variables, {'id': 7, 'page': 3, 'perPage': PeopleApi.staffPageSize});
      expect(page.items.single.roles, ['Director']);
      expect(page.hasNextPage, isFalse);
    });

    test('an unreadable page is an empty last page', () async {
      final page = await apiReturning({'data': {'Staff': null}}).getVoicedCharacters(1, page: 2);

      expect(page.items, isEmpty);
      expect(page.hasNextPage, isFalse);
    });
  });

  group('getStudio', () {
    final studioBody = {
      'data': {
        'Studio': {
          'id': 11,
          'name': 'MADHOUSE',
          'isAnimationStudio': true,
          'favourites': 20044,
          'main': {
            'pageInfo': {'hasNextPage': true},
            'nodes': [_media(1), _media(2, isAdult: true), null, {'title': 'no id'}],
          },
          'other': {
            'pageInfo': {'hasNextPage': false},
            'nodes': [_media(3)],
          },
        },
      },
    };

    test('asks for both groups of media, most popular first', () async {
      await apiReturning(studioBody).getStudio(11);

      final request = log.single;
      expect(request.variables, {'id': 11, 'perPage': PeopleApi.studioPageSize});
      expect(request.query, contains('main: media(isMain: true, page: 1'));
      expect(request.query, contains('other: media(isMain: false, page: 1'));
      expect(request.query, contains('sort: [POPULARITY_DESC, ID]'));
      expect(request.authorization, isNull);
    });

    test('parses the studio, leaving out adult and malformed media', () async {
      final studio = await apiReturning(studioBody).getStudio(11);

      expect(studio.name, 'MADHOUSE');
      expect(studio.isAnimationStudio, isTrue);
      expect(studio.favourites, 20044);
      expect(studio.main.media.map((m) => m.id), [1]);
      expect(studio.main.hasNextPage, isTrue);
      expect(studio.other.media.map((m) => m.id), [3]);

      final cached = StudioDetail.fromJson(_throughCache(studio))!;
      expect(cached.main.media.single.title, studio.main.media.single.title);
      expect(cached.main.hasNextPage, isTrue);
      expect(cached.other.media.single.id, 3);
    });

    test('getStudioMedia asks for one group and page', () async {
      final api = apiReturning({
        'data': {
          'Studio': {
            'media': {'pageInfo': {'hasNextPage': true}, 'nodes': [_media(4)]},
          },
        },
      });

      final page = await api.getStudioMedia(11, isMain: false, page: 2);

      expect(log.single.variables, {'id': 11, 'isMain': false, 'page': 2, 'perPage': PeopleApi.studioPageSize});
      expect(page.media.single.id, 4);
      expect(page.hasNextPage, isTrue);
    });

    test('throws when AniList has no such studio', () async {
      await expectLater(apiReturning({'data': {'Studio': null}}).getStudio(1), throwsA(isA<AniListRequestException>()));
    });
  });

  group('getCharacter', () {
    final characterBody = {
      'data': {
        'Character': {
          'id': 1,
          'isFavourite': true,
          'name': {'full': 'Spike Spiegel', 'native': 'スパイク'},
          'image': {'large': 'https://img/c.jpg'},
          'description': 'A bounty hunter.',
          'gender': 'Male',
          'age': '27',
          'bloodType': 'O',
          'dateOfBirth': {'year': 2044, 'month': 6, 'day': 26},
          'media': {
            'edges': [
              {
                'node': _media(1),
                'voiceActors': [
                  _person(20, 'Steven Blum', language: 'English'),
                  _person(10, 'Kouichi Yamadera', language: 'Japanese'),
                  _person(30, 'Genaro Vásquez', language: 'Spanish'),
                ],
              },
              {
                'node': _media(5),
                'voiceActors': [_person(10, 'Kouichi Yamadera', language: 'Japanese'), 'junk'],
              },
              {
                'node': _media(6, isAdult: true),
                'voiceActors': [_person(40, 'Adult only', language: 'Japanese')],
              },
            ],
          },
        },
      },
    };

    test('sends the token so isFavourite is the viewer\'s', () async {
      await apiReturning(characterBody).getCharacter(1, token: 'tok');

      final request = log.single;
      expect(request.authorization, 'Bearer tok');
      expect(request.variables, {'id': 1, 'perPage': PeopleApi.characterMediaCount});
      expect(request.query, contains('voiceActors(sort: [RELEVANCE, ID])'));
    });

    test('lists every voice actor once, Japanese first, and leaves out adult media', () async {
      final character = await apiReturning(characterBody).getCharacter(1);

      expect(character.name, 'Spike Spiegel');
      expect(character.isFavourite, isTrue);
      expect(character.age, '27');
      expect(character.media.map((m) => m.id), [1, 5]);
      expect(character.voiceActors.map((a) => a.name), ['Kouichi Yamadera', 'Steven Blum', 'Genaro Vásquez']);
      expect(character.voiceActors.first.imageUrl, 'https://img/p10.jpg', reason: 'falls back to medium');
    });

    test('survives the cache round trip and reads the old cached shape', () async {
      final character = await apiReturning(characterBody).getCharacter(1);

      final cached = CharacterDetail.fromJson(_throughCache(character))!;
      expect(cached.voiceActors.map((a) => a.id), [10, 20, 30]);
      expect(cached.media.map((m) => m.id), [1, 5]);
      expect(cached.dateOfBirth?.toJson(), {'year': 2044, 'month': 6, 'day': 26});

      final old = CharacterDetail.fromJson({
        'id': 1,
        'name': {'full': 'Spike Spiegel'},
        'media': {
          'nodes': [_media(1), 'junk'],
        },
      })!;
      expect(old.media.single.id, 1);
      expect(old.voiceActors, isEmpty);
      expect(old.isFavourite, isFalse);
    });

    test('copyWith only changes isFavourite', () async {
      final character = await apiReturning(characterBody).getCharacter(1);

      final unfavourited = character.copyWith(isFavourite: false);

      expect(unfavourited.isFavourite, isFalse);
      expect(unfavourited.name, character.name);
      expect(unfavourited.voiceActors, character.voiceActors);
    });
  });

  group('merging pages', () {
    MediaRef media(int id) => MediaRef(id: id);

    test('appendStaffRoles merges the roles of a media split across pages', () {
      final merged = appendStaffRoles(
        [StaffRole(media: media(1), roles: const ['Director']), StaffRole(media: media(2), roles: const ['Script'])],
        [StaffRole(media: media(1), roles: const ['Storyboard', 'Director']), StaffRole(media: media(3))],
      );

      expect(merged.map((r) => r.media.id), [1, 2, 3]);
      expect(merged.first.roles, ['Director', 'Storyboard']);
    });

    test('appendVoicedCharacters keeps the first media of a character', () {
      const spike = CharacterRef(id: 1, name: 'Spike');
      final merged = appendVoicedCharacters(
        [VoicedCharacter(character: spike, media: media(1))],
        [
          VoicedCharacter(character: spike, media: media(2)),
          VoicedCharacter(character: const CharacterRef(id: 2, name: 'Jet'), media: media(2)),
        ],
      );

      expect(merged.map((c) => '${c.character.name}@${c.media.id}'), ['Spike@1', 'Jet@2']);
    });

    test('appendMedia skips media already shown', () {
      expect(appendMedia([media(1), media(2)], [media(2), media(3)]).map((m) => m.id), [1, 2, 3]);
    });
  });

  test('sortVoiceActors puts Japanese first, then the preferred language', () {
    const actors = [
      StaffRef(id: 1, name: 'A', language: 'English'),
      StaffRef(id: 2, name: 'B', language: 'Spanish'),
      StaffRef(id: 3, name: 'C', language: 'Japanese'),
      StaffRef(id: 4, name: 'D'),
      StaffRef(id: 5, name: 'E', language: 'Spanish'),
    ];

    expect(sortVoiceActors(actors, preferredLanguage: 'Spanish').map((a) => a.name), ['C', 'B', 'E', 'A', 'D']);
    expect(sortVoiceActors(actors).map((a) => a.name), ['C', 'A', 'B', 'D', 'E']);
    expect(sortVoiceActors(actors, preferredLanguage: 'Japanese').map((a) => a.name), ['C', 'A', 'B', 'D', 'E']);
  });

  test('StaffCredit.listFromEdges merges roles and skips malformed edges', () {
    final credits = StaffCredit.listFromEdges([
      {'role': 'Director', 'node': _person(1, 'Shinichirou Watanabe')},
      {'role': 'Music', 'node': _person(2, 'Yoko Kanno')},
      {'role': 'Storyboard (eps 1, 5)', 'node': _person(1, 'Shinichirou Watanabe')},
      {'role': 'Director', 'node': _person(1, 'Shinichirou Watanabe')},
      {'role': 'Nameless', 'node': {'id': 3}},
      {'role': 'No node'},
      42,
    ]);

    expect(credits.map((c) => c.staff.name), ['Shinichirou Watanabe', 'Yoko Kanno']);
    expect(credits.first.roles, ['Director', 'Storyboard (eps 1, 5)']);
    expect(StaffCredit.listFromEdges(null), isEmpty);
  });

  test('StudioRef.listFromJson tolerates a missing id and edge-shaped input', () {
    final studios = StudioRef.listFromJson([
      {'name': 'Sunrise', 'isAnimationStudio': true},
      {'id': 17, 'name': 'Aniplex', 'isAnimationStudio': false},
      {'node': {'id': 18, 'name': 'Bandai Visual'}},
      {'id': 17, 'name': 'Aniplex'},
      {'id': 19},
      'junk',
    ]);

    expect(studios.map((s) => s.name), ['Sunrise', 'Aniplex', 'Bandai Visual']);
    expect(studios.first.id, isNull);
    expect(studios.first.isAnimationStudio, isTrue);
    expect(studios[1].id, 17);
    expect(StudioRef.listFromJson({'nodes': []}), isEmpty);
  });

  test('FuzzyDate drops impossible months and days', () {
    expect(FuzzyDate.fromJson({'year': 2000, 'month': 13, 'day': 0})?.toJson(), {'year': 2000, 'month': null, 'day': null});
    expect(FuzzyDate.fromJson({'month': 0}), isNull);
    expect(FuzzyDate.fromJson('2000-01-01'), isNull);
  });
}
