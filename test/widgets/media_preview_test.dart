import 'dart:async';
import 'dart:io';

import 'package:anispark/screens/detail_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/app_button.dart';
import 'package:anispark/widgets/entry_editor/entry_draft.dart' show entryStatusKey;
import 'package:anispark/widgets/media_preview.dart';
import 'package:anispark/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';
import '../screens/screen_harness.dart';

String _en(String key) => tr(key, 'English');

/// What a list or a card already has of the media.
const _known = {
  'id': 1,
  'type': 'ANIME',
  'title': {'english': 'Cowboy Bebop'},
  'coverImage': {'large': null},
  'averageScore': 86,
};

http.Response _answer({Map<String, dynamic>? entry}) => jsonResponse({
      'data': {
        'Media': {
          'id': 1,
          'type': 'ANIME',
          'format': 'TV',
          'episodes': 26,
          'chapters': null,
          'averageScore': 86,
          'seasonYear': 1998,
          'genres': ['Action', 'Sci-Fi', 'Drama', 'Adventure'],
          'description': 'In 2071, the crew of the <i>Bebop</i> hunt bounties.',
          'mediaListEntry': entry,
        },
      },
    });

FakeAuthService _loggedIn() => FakeAuthService(fakeToken: 'token', fakeUser: {'id': 7, 'name': 'Faye'});

void main() {
  late List<RecordedRequest> log;

  // The detail page a preview opens loads with the shared client.
  setUpAll(() => HttpOverrides.global = OfflineHttpOverrides());

  setUp(() => log = []);

  /// Holds the cover of a page, which opens the preview.
  Future<void> openPreview(
    WidgetTester tester, {
    required AniListService service,
    AuthService? auth,
    VoidCallback? onEdit,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) => GestureDetector(
              onLongPress: () => showMediaPreview(context, media: _known, onEdit: onEdit, service: service),
              child: const SizedBox(width: 100, height: 140, child: Text('cover')),
            ),
          ),
        ),
      ),
      cache: ApiCache(MemoryCacheStore()),
      auth: auth,
    ));
    await tester.longPress(find.text('cover'));
    await tester.pump();
  }

  AniListService answering(http.Response Function(RecordedRequest) handler) =>
      AniListService(client: mockAniList(log, handler));

  /// The entrance plays out and the answer is shown; the skeleton never settles.
  Future<void> arrive(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  final card = find.descendant(of: find.byType(MediaPreview), matching: find.byType(Material)).first;

  testWidgets('shows at once what the page knew, with the shape of the rest while it loads', (tester) async {
    final answer = Completer<http.Response>();
    await openPreview(tester, service: AniListService(client: MockClient((_) => answer.future)));
    await arrive(tester);

    expect(find.descendant(of: card, matching: find.text('Cowboy Bebop')), findsOneWidget);
    expect(find.textContaining('★ 8.6'), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(Skeleton)), findsOneWidget);
    final loadingHeight = tester.getSize(card).height;

    answer.complete(_answer());
    await tester.pump();
    await tester.pump();

    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('In 2071, the crew of the Bebop hunt bounties.'), findsOneWidget, reason: 'markup is stripped');
    expect(find.text('★ 8.6 · TV · 26 eps · 1998'), findsOneWidget);
    expect(find.text('Action · Sci-Fi · Drama'), findsOneWidget, reason: 'the first three genres');
    expect(tester.getSize(card).height, loadingHeight, reason: 'what loads has its room from the start');
  });

  testWidgets('grows out of what was held, over a page that goes out of focus', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()));
    await tester.pump(const Duration(milliseconds: 60));

    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: find.byType(MediaPreview), matching: find.byType(ScaleTransition)).first,
    );
    expect(scale.scale.value, inExclusiveRange(0.8, 1));
    expect(scale.alignment.x, lessThan(0), reason: 'the cover was at the left');
    expect(scale.alignment.y, lessThan(0), reason: 'and at the top');
    expect(find.byType(BackdropFilter), findsOneWidget);

    await arrive(tester);
    expect(scale.scale.value, 1);
  });

  testWidgets('offers to add what is not in the list', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()), auth: _loggedIn());
    await arrive(tester);

    expect(find.widgetWithText(AppButton, _en('add_to_list')), findsOneWidget);
    expect(find.widgetWithText(AppButton, _en('tooltip_edit_entry')), findsNothing);
    expect(log, hasLength(1));
  });

  testWidgets('says where it is in the list and offers to edit it', (tester) async {
    await openPreview(
      tester,
      service: answering((_) => _answer(entry: {'id': 9, 'status': 'CURRENT', 'progress': 12})),
      auth: _loggedIn(),
    );
    await arrive(tester);

    expect(find.text('${_en(entryStatusKey('CURRENT', manga: false))} · 12'), findsOneWidget);
    expect(find.widgetWithText(AppButton, _en('tooltip_edit_entry')), findsOneWidget);
    expect(find.widgetWithText(AppButton, _en('add_to_list')), findsNothing);
  });

  testWidgets('the edit button hands over to the page that has the entry', (tester) async {
    var edits = 0;
    await openPreview(tester, service: answering((_) => _answer()), auth: _loggedIn(), onEdit: () => edits++);
    await arrive(tester);
    expect(find.widgetWithText(AppButton, _en('tooltip_edit_entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview-edit')));
    await tester.pumpAndSettle();

    expect(edits, 1);
    expect(find.byType(MediaPreview), findsNothing);
  });

  testWidgets('logged out it only offers to open it', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()));
    await arrive(tester);

    expect(find.byKey(const ValueKey('preview-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview-edit')), findsNothing);
  });

  testWidgets('open closes the preview and opens its page', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()));
    await arrive(tester);

    await tester.tap(find.byKey(const ValueKey('preview-open')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MediaPreview), findsNothing);
    expect(tester.widget<DetailScreen>(find.byType(DetailScreen)).animeId, 1);
  });

  testWidgets('a tap off the card closes it, a tap on it does not', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()));
    await arrive(tester);

    await tester.tap(find.text('In 2071, the crew of the Bebop hunt bounties.'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreview), findsOneWidget);

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPreview), findsNothing);
  });

  testWidgets('when the rest cannot be loaded it keeps what it knew, without a placeholder', (tester) async {
    await openPreview(tester, service: answering((_) => http.Response('', 500)));
    await arrive(tester);

    expect(tester.takeException(), isNull);
    expect(find.descendant(of: card, matching: find.text('Cowboy Bebop')), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
    expect(find.byKey(const ValueKey('preview-open')), findsOneWidget);
  });

  testWidgets('add or edit comes first, open at the right', (tester) async {
    await openPreview(tester, service: answering((_) => _answer()), auth: _loggedIn());
    await arrive(tester);

    expect(
      tester.getCenter(find.byKey(const ValueKey('preview-edit'))).dx,
      lessThan(tester.getCenter(find.byKey(const ValueKey('preview-open'))).dx),
    );
  });
}
