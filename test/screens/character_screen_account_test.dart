import 'dart:async';

import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/people_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

Map<String, dynamic> _character(String name, {bool isFavourite = false}) => {
      'id': 1,
      'isFavourite': isFavourite,
      'name': {'full': name},
      'media': {'edges': []},
    };

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;
  // What AniList holds.
  var isFavourite = false;

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
    isFavourite = false;
  });

  PeopleApi peopleApi() => PeopleApi(
        service: AniListService(
          client: mockAniList(log, (_) => jsonResponse({
                'data': {'Character': _character('Spike Spiegel', isFavourite: isFavourite)},
              })),
        ),
      );

  Future<void> pumpCharacter(WidgetTester tester, AuthService auth, {AniListService? service}) async {
    await tester.pumpWidget(appWith(
      CharacterScreen(characterId: 1, api: peopleApi(), service: service),
      cache: cache,
      auth: auth,
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('a second tap while the favourite is saving sends nothing', (tester) async {
    final gate = Completer<void>();
    var toggles = 0;
    final favourites = AniListService(
      client: MockClient((request) async {
        toggles++;
        await gate.future;
        isFavourite = !isFavourite;
        return jsonResponse({
          'data': {
            'ToggleFavourite': {
              'characters': {'nodes': []},
            },
          },
        });
      }),
    );
    await pumpCharacter(tester, FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7}), service: favourites);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(toggles, 1);

    gate.complete();
    await tester.pumpAndSettle();

    expect(toggles, 1);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('with a token but no account id, the logged-out cache is left alone', (tester) async {
    // The profile fetch failed, so the account id is unknown; the response
    // still carries this account's isFavourite.
    await cache.write('anon:character:1', _character('Cached for everyone'));

    await pumpCharacter(tester, FakeAuthService(fakeToken: 'tok'));

    expect(find.text('Cached for everyone'), findsNothing);
    expect(find.text('Spike Spiegel'), findsWidgets);
    expect(log.single.authorization, 'Bearer tok');
    final cached = await cache.read('anon:character:1');
    expect((cached!.value as Map)['name'], {'full': 'Cached for everyone'});
  });
}
