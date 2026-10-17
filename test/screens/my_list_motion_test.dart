import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/screens/my_list_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/utils/tab_reselect.dart';
import 'package:anispark/widgets/motion/animated_count.dart';
import 'package:anispark/widgets/motion/staggered_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

// The manga list is used throughout: a fresh anime list also reschedules
// episode notifications, whose plugin isn't available under `flutter test`.
const _mangaTab = 1;

Map<String, dynamic> _entry(int mediaId, {int progress = 3}) => {
      'id': mediaId * 10,
      'mediaId': mediaId,
      'progress': progress,
      'score': 0,
      'notes': null,
      'customLists': null,
      'media': {
        'id': mediaId,
        'title': {'english': 'Manga $mediaId'},
        'chapters': 100,
      },
    };

Map<String, dynamic> _list(String name, List<Map<String, dynamic>> entries, {String? status}) => {
      'name': name,
      'status': status,
      'isCustomList': status == null,
      'entries': entries,
    };

void main() {
  late List<RecordedRequest> log;
  late ApiCache cache;
  late MediaListStore store;
  late List<Map<String, dynamic>> lists;

  setUp(() {
    log = [];
    cache = ApiCache(MemoryCacheStore());
    lists = [];
    store = MediaListStore(
      service: AniListService(
        client: mockAniList(log, (request) {
          if (request.query.contains('SaveMediaListEntry')) {
            return jsonResponse({
              'data': {
                'SaveMediaListEntry': {
                  'id': (request.variables['mediaId'] as int) * 10,
                  'status': 'CURRENT',
                  'progress': request.variables['progress'],
                },
              },
            });
          }
          return jsonResponse({
            'data': {
              'MediaListCollection': {'lists': lists},
            },
          });
        }),
      ),
      cache: cache,
      persistDelay: Duration.zero,
    );
  });

  tearDown(() => store.dispose());

  Future<void> pumpList(WidgetTester tester, {Size size = const Size(800, 2000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: cache),
        ChangeNotifierProvider<AuthService>.value(
          value: FakeAuthService(fakeToken: 'token', fakeUser: {'id': 7}),
        ),
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MaterialApp(home: MangaListScreen()),
    ));
    await tester.pumpAndSettle();
  }

  double listOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      )
      .position
      .pixels;

  testWidgets('cover hero tags are unique, even for a media also in a custom list', (tester) async {
    lists = [
      _list('Reading', [_entry(30), _entry(31)], status: 'CURRENT'),
      _list('Favs', [_entry(30)]),
    ];

    await pumpList(tester);

    final tags = tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag).toList();
    expect(tags, hasLength(3), reason: 'one cover per row');
    expect(tags.toSet(), hasLength(tags.length));
    expect(tags, containsAll(['cover:mylist-MANGA-CURRENT:30', 'cover:mylist-MANGA-custom:Favs:30']));
  });

  testWidgets('searching between results and no match neither cross-fades nor replays the cascade', (tester) async {
    lists = [
      _list('Reading', [_entry(30), _entry(31)], status: 'CURRENT'),
    ];
    await pumpList(tester);
    // A person starts typing well after the list's first cascade.
    await tester.pump(EntranceGate.window);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    // The list is swapped for the no-match message at once, not faded out.
    expect(find.byType(ListView), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final row = find.text('Manga 30');
    expect(row, findsOneWidget);
    final fades = tester.widgetList<FadeTransition>(find.ancestor(of: row, matching: find.byType(FadeTransition)));
    expect(fades.every((fade) => fade.opacity.value == 1), isTrue, reason: 'rows reappear without replaying the cascade');
  });

  testWidgets('re-selecting the tab scrolls the list back to the top', (tester) async {
    lists = [
      _list('Reading', [for (var id = 1; id <= 30; id++) _entry(id)], status: 'CURRENT'),
    ];
    await pumpList(tester, size: const Size(800, 1200));

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    final scrolled = listOffset(tester);
    expect(scrolled, greaterThan(0));

    // Another tab's reselection leaves this list alone.
    tabReselectedNotifier.reselect(0);
    await tester.pumpAndSettle();
    expect(listOffset(tester), scrolled);

    tabReselectedNotifier.reselect(_mangaTab);
    await tester.pumpAndSettle();
    expect(listOffset(tester), 0);
  });

  testWidgets('a +1 swipe rolls the row\'s progress to the new value', (tester) async {
    lists = [
      _list('Reading', [_entry(30, progress: 42)], status: 'CURRENT'),
    ];
    await pumpList(tester);
    expect(tester.widget<AnimatedCount>(find.byType(AnimatedCount)).value, 42);

    // The swipe is confirmed once the row has slid; the count then changes.
    await tester.drag(find.text('Manga 30'), const Offset(500, 0));
    int shown() => tester.widget<AnimatedCount>(find.byType(AnimatedCount)).value;
    for (var i = 0; i < 20 && shown() != 43; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(shown(), 43);
    expect(find.text('42'), findsOneWidget, reason: 'the old value is still rolling out');
    expect(find.text('43'), findsOneWidget, reason: 'the new value is rolling in');
    await tester.pumpAndSettle();

    expect(log.where((r) => r.query.contains('SaveMediaListEntry')).single.variables['progress'], 43);
    expect(find.text('43'), findsOneWidget);
    expect(find.text('42'), findsNothing, reason: 'the old value rolled away');
    // Let the undo snack bar time out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the undo snack bar goes away on its own after a few seconds', (tester) async {
    lists = [
      _list('Reading', [_entry(30, progress: 42)], status: 'CURRENT'),
    ];
    await pumpList(tester);

    await tester.drag(find.text('Manga 30'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget, reason: 'undo is offered');

    // A snack bar with an action would stay until dismissed unless told not to.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
