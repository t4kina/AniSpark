import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/my_list_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/widgets/anime_card.dart';
import 'package:anispark/widgets/entry_editor/entry_editor_fields.dart' show UnknownValue;
import 'package:anispark/widgets/entry_editor/entry_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

// The editor these screens open uses the app's own AniList client, which
// `flutter test` answers with HTTP 400: its lookup fails, so it shows what
// the screen passed (or a retry for quick add).

Widget _app(Widget child, {required AuthService auth, required MediaListStore store, required ApiCache cache}) =>
    MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: child),
    );

FakeAuthService _loggedIn() => FakeAuthService(fakeToken: 'token', fakeUser: {
      'id': 7,
      'mediaListOptions': {'scoreFormat': 'POINT_10_DECIMAL'},
    });

void main() {
  late List<RecordedRequest> log;
  late ApiCache cache;
  late MediaListStore store;

  setUp(() {
    log = [];
    cache = ApiCache(MemoryCacheStore());
    store = MediaListStore(
      service: AniListService(
        client: mockAniList(
          log,
          (_) => jsonResponse({
            'data': {
              'MediaListCollection': {
                'lists': [
                  {
                    'name': 'Reading',
                    'status': 'CURRENT',
                    'isCustomList': false,
                    'entries': [
                      {
                        'id': 300,
                        'mediaId': 30,
                        'progress': 42,
                        'score': 8.0,
                        'notes': 'So good',
                        'customLists': null,
                        'media': {
                          'id': 30,
                          'title': {'english': 'Vagabond'},
                          'chapters': 327,
                        },
                      },
                    ],
                  },
                ],
              },
            },
          }),
        ),
      ),
      cache: cache,
      persistDelay: Duration.zero,
    );
  });

  tearDown(() => store.dispose());

  testWidgets('My List: long-press opens the editor with the row\'s entry', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const MangaListScreen(), auth: _loggedIn(), store: store, cache: cache));
    await tester.pumpAndSettle();
    expect(find.text('Vagabond'), findsOneWidget);

    await tester.longPress(find.text('Vagabond'));
    await tester.pumpAndSettle();

    expect(find.byType(EntryEditorSheet), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('entry-editor-status-CURRENT'))).selected, isTrue);
    final progress = find.descendant(
      of: find.byKey(const ValueKey('entry-editor-progress')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(progress).controller!.text, '42');
    // Volumes, rereads, dates and switches aren't in the list data: locked.
    expect(find.byKey(const ValueKey('entry-editor-volumes')), findsNothing);
    expect(find.byType(UnknownValue), findsNWidgets(2));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('entry-editor-notes'))).controller!.text, 'So good');
  });

  group('Discover card long-press', () {
    const card = {
      'id': 30,
      'title': {'english': 'Vagabond'},
      'chapters': 327,
    };

    Widget cardApp(AuthService auth) => _app(
          const Scaffold(body: Center(child: SizedBox(width: 120, height: 222, child: AnimeCard(animeData: card)))),
          auth: auth,
          store: store,
          cache: cache,
        );

    testWidgets('does nothing when logged out', (tester) async {
      await tester.pumpWidget(cardApp(FakeAuthService()));

      await tester.longPress(find.byType(AnimeCard));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditorSheet), findsNothing);
    });

    testWidgets('opens the editor to look the media up when logged in', (tester) async {
      await tester.pumpWidget(cardApp(_loggedIn()));

      await tester.longPress(find.byType(AnimeCard));
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditorSheet), findsOneWidget);
      // Nothing can be saved before AniList says whether it's in the list.
      expect(find.byKey(const ValueKey('entry-editor-save')), findsNothing);
      expect(find.text('Vagabond'), findsWidgets);
    });
  });
}
