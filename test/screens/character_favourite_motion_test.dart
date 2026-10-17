import 'package:anispark/screens/character_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/people_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

void main() {
  testWidgets('the heart pops with a light haptic when it becomes a favourite, not when it stops',
      (tester) async {
    var isFavourite = false;
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final api = PeopleApi(
      service: AniListService(
        client: mockAniList([], (_) => jsonResponse({
              'data': {
                'Character': {
                  'id': 1,
                  'isFavourite': isFavourite,
                  'name': {'full': 'Spike Spiegel'},
                  'media': {'edges': []},
                },
              },
            })),
      ),
    );
    final favourites = AniListService(
      client: MockClient((_) async {
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
    await tester.pumpWidget(appWith(
      CharacterScreen(characterId: 1, api: api, service: favourites),
      cache: ApiCache(MemoryCacheStore()),
      auth: FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7}),
    ));
    await tester.pumpAndSettle();

    double heartScale(IconData icon) => tester
        .widget<ScaleTransition>(find.ancestor(of: find.byIcon(icon), matching: find.byType(ScaleTransition)).first)
        .scale
        .value;

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(heartScale(Icons.favorite), greaterThan(1), reason: 'mid-pop');

    await tester.pumpAndSettle();
    expect(heartScale(Icons.favorite), 1);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(heartScale(Icons.favorite_border), 1);
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();
  });
}
