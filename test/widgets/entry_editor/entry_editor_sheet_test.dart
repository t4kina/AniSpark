import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/widgets/entry_editor/entry_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../helpers/fake_auth_service.dart';
import '../../helpers/memory_cache_store.dart';
import '../../helpers/mock_anilist.dart';

const _emptyDate = {'year': null, 'month': null, 'day': null};

Map<String, dynamic> _entry({
  String status = 'CURRENT',
  int progress = 5,
  int progressVolumes = 0,
  double score = 7.5,
  Map<String, dynamic> startedAt = _emptyDate,
  Map<String, dynamic> completedAt = _emptyDate,
  bool private = false,
  int repeat = 0,
  Map<String, bool>? customLists,
}) =>
    {
      'id': 100,
      'status': status,
      'progress': progress,
      'progressVolumes': progressVolumes,
      'score': score,
      'repeat': repeat,
      'private': private,
      'hiddenFromStatusLists': false,
      'notes': 'Great',
      'customLists': customLists,
      'startedAt': startedAt,
      'completedAt': completedAt,
    };

const _anime = EditorMedia(id: 1, isManga: false, title: {'english': 'Frieren'}, totalProgress: 12);
const _manga = EditorMedia(
  id: 2,
  isManga: true,
  title: {'english': 'Berserk'},
  totalProgress: 380,
  totalVolumes: 10,
);

/// A fake AniList answering every request the editor and the list store send.
class _AniList {
  final log = <RecordedRequest>[];
  final cache = ApiCache(MemoryCacheStore());
  Map<String, dynamic>? lookupEntry;
  String lookupType = 'ANIME';
  bool lookupFails = false;
  bool saveFails = false;
  List<String> customListNames = const [];

  late final service = AniListService(client: mockAniList(log, _respond));
  late final store = MediaListStore(service: service, cache: cache, persistDelay: Duration.zero);

  Iterable<RecordedRequest> get saves => log.where((r) => r.query.contains('SaveMediaListEntry'));
  Iterable<RecordedRequest> get lookups => log.where((r) => r.query.contains('mediaListEntry'));
  Iterable<RecordedRequest> get listReloads => log.where((r) => r.query.contains('entries'));

  http.Response _respond(RecordedRequest request) {
    final query = request.query;
    if (query.contains('SaveMediaListEntry')) {
      if (saveFails) {
        return jsonResponse({
          'data': {'SaveMediaListEntry': null},
          'errors': [
            {'message': 'Validation error'},
          ],
        });
      }
      return jsonResponse({
        'data': {
          'SaveMediaListEntry': {
            'id': 100,
            'status': request.variables['status'] ?? 'CURRENT',
            'progress': request.variables['progress'] ?? 5,
            'score': 7.5,
          },
        },
      });
    }
    if (query.contains('DeleteMediaListEntry')) {
      return jsonResponse({
        'data': {
          'DeleteMediaListEntry': {'deleted': true},
        },
      });
    }
    if (query.contains('mediaListEntry')) {
      if (lookupFails) return jsonResponse({'errors': []}, status: 500);
      return jsonResponse({
        'data': {
          'Media': {
            'id': request.variables['id'],
            'type': lookupType,
            'episodes': lookupType == 'ANIME' ? 12 : null,
            'chapters': lookupType == 'MANGA' ? 380 : null,
            'volumes': lookupType == 'MANGA' ? 10 : null,
            'mediaListEntry': lookupEntry,
          },
        },
      });
    }
    if (query.contains('entries')) {
      return jsonResponse({
        'data': {
          'MediaListCollection': {
            'lists': [
              {
                'name': 'Watching',
                'status': 'CURRENT',
                'isCustomList': false,
                'entries': [
                  {
                    'id': 100,
                    'mediaId': 1,
                    'progress': 5,
                    'score': 7.5,
                    'notes': null,
                    'customLists': null,
                    'media': {'id': 1, 'title': {'english': 'Frieren'}, 'episodes': 12},
                  },
                ],
              },
            ],
          },
        },
      });
    }
    // Custom list names.
    return jsonResponse({
      'data': {
        'MediaListCollection': {
          'lists': [
            for (final name in customListNames) {'name': name, 'isCustomList': true},
          ],
        },
      },
    });
  }
}

final _results = <EntryEditorResult>[];

Future<void> _open(
  WidgetTester tester,
  _AniList api, {
  EditorMedia media = _anime,
  Map<String, dynamic>? entry,
  bool entryKnown = true,
  String scoreFormat = 'POINT_10_DECIMAL',
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuthService(fakeToken: 'token', fakeUser: {
    'id': 7,
    'mediaListOptions': {'scoreFormat': scoreFormat},
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider.value(value: api.cache),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider.value(value: api.store),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEntryEditor(
              context,
              media: media,
              entry: entry,
              entryKnown: entryKnown,
              service: api.service,
              onChanged: _results.add,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _inside(String key, Finder matching) => find.descendant(of: _key(key), matching: matching);

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_inside(key, find.byType(TextField))).controller!.text;

bool _chipSelected(WidgetTester tester, String status) =>
    tester.widget<ChoiceChip>(_key('entry-editor-status-$status')).selected;

SwitchListTile _switch(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(_inside(key, find.byType(SwitchListTile)));

Future<void> _save(WidgetTester tester) async {
  await tester.tap(_key('entry-editor-save'));
  await tester.pumpAndSettle();
}

Map<String, int> _todayInput() {
  final now = DateTime.now();
  return {'year': now.year, 'month': now.month, 'day': now.day};
}

void main() {
  late _AniList api;

  setUp(() {
    api = _AniList();
    _results.clear();
  });

  tearDown(() => api.store.dispose());

  testWidgets('opens with the entry\'s current values without looking it up', (tester) async {
    await _open(tester, api,
        entry: _entry(private: true, startedAt: {'year': 2024, 'month': 1, 'day': 2}));

    expect(_chipSelected(tester, 'CURRENT'), isTrue);
    expect(_chipSelected(tester, 'COMPLETED'), isFalse);
    expect(_fieldText(tester, 'entry-editor-progress'), '5');
    expect(_fieldText(tester, 'entry-editor-score'), '7.5');
    expect(_fieldText(tester, 'entry-editor-repeat'), '0');
    expect(tester.widget<TextField>(_key('entry-editor-notes')).controller!.text, 'Great');
    expect(_inside('entry-editor-started', find.text('2 Jan 2024')), findsOneWidget);
    expect(_switch(tester, 'entry-editor-private').value, isTrue);
    expect(_switch(tester, 'entry-editor-hidden').value, isFalse);
    expect(_key('entry-editor-volumes'), findsNothing, reason: 'anime have no volumes');
    expect(_key('entry-editor-remove'), findsOneWidget);
    expect(api.lookups, isEmpty);
    expect(api.saves, isEmpty);
  });

  testWidgets('sends only the fields that changed and reports the save', (tester) async {
    await _open(tester, api, entry: _entry());

    await tester.tap(_inside('entry-editor-progress', find.byIcon(Icons.add)));
    await tester.pump();
    await tester.enterText(_key('entry-editor-notes'), '  Great  ');
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'progress': 6});
    expect(_results, [EntryEditorResult.saved]);
    expect(_key('entry-editor-form'), findsNothing, reason: 'the sheet closes');
    expect(find.text('Frieren saved!'), findsOneWidget);
    expect(api.listReloads, isNotEmpty, reason: 'My List reloads the type');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('saving without changes closes the sheet without a request', (tester) async {
    await _open(tester, api, entry: _entry());

    await _save(tester);

    expect(api.saves, isEmpty);
    expect(_results, isEmpty);
    expect(_key('entry-editor-form'), findsNothing);
  });

  testWidgets('progress can be typed and is kept within the total', (tester) async {
    await _open(tester, api, entry: _entry());

    await tester.enterText(_inside('entry-editor-progress', find.byType(TextField)), '40');
    await tester.pump();

    expect(_fieldText(tester, 'entry-editor-progress'), '12');
    await _save(tester);
    expect(api.saves.single.variables, {'mediaId': 1, 'progress': 12});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('watching a planned entry starts it today', (tester) async {
    await _open(tester, api, entry: _entry(status: 'PLANNING', progress: 0));

    await tester.tap(_key('entry-editor-status-CURRENT'));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {
      'mediaId': 1,
      'status': 'CURRENT',
      'startedAt': _todayInput(),
    });
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('completing finishes it today at full progress but keeps an existing start date', (tester) async {
    await _open(tester, api, entry: _entry(startedAt: {'year': 2024, 'month': 1, 'day': 2}));

    await tester.tap(_key('entry-editor-status-COMPLETED'));
    await tester.pump();
    expect(_fieldText(tester, 'entry-editor-progress'), '12');
    await _save(tester);

    expect(api.saves.single.variables, {
      'mediaId': 1,
      'status': 'COMPLETED',
      'progress': 12,
      'completedAt': _todayInput(),
    });
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('clearing a date sends AniList\'s clearing input', (tester) async {
    await _open(tester, api, entry: _entry(startedAt: {'year': 2024, 'month': 1, 'day': 2}));

    await tester.tap(_inside('entry-editor-started', find.byIcon(Icons.close_rounded)));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'startedAt': _emptyDate});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('manga edit volumes and use reading words', (tester) async {
    await _open(tester, api, media: _manga, entry: _entry(progressVolumes: 2, progress: 20));

    expect(_key('entry-editor-volumes'), findsOneWidget);
    expect(_fieldText(tester, 'entry-editor-volumes'), '2');
    expect(_inside('entry-editor-status-CURRENT', find.text('Reading')), findsOneWidget);
    expect(_inside('entry-editor-status-PLANNING', find.text('Plan to Read')), findsOneWidget);

    await tester.tap(_inside('entry-editor-volumes', find.byIcon(Icons.add)));
    await tester.pump();
    await tester.tap(_inside('entry-editor-repeat', find.byIcon(Icons.add)));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 2, 'progressVolumes': 3, 'repeat': 1});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a 5-star user scores with stars', (tester) async {
    await _open(tester, api, entry: _entry(score: 6), scoreFormat: 'POINT_5');

    expect(tester.widget<IconButton>(_key('entry-editor-star-3')).isSelected, isTrue);
    expect(tester.widget<IconButton>(_key('entry-editor-star-4')).isSelected, isFalse);

    await tester.tap(_key('entry-editor-star-4'));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'scoreRaw': 80});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a 100-point user types the score in points', (tester) async {
    await _open(tester, api, entry: _entry(score: 7.5), scoreFormat: 'POINT_100');

    expect(_fieldText(tester, 'entry-editor-score'), '75');
    await tester.enterText(_inside('entry-editor-score', find.byType(TextField)), '83');
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'scoreRaw': 83});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a 3-face user picks a face', (tester) async {
    await _open(tester, api, entry: _entry(score: 0), scoreFormat: 'POINT_3');

    await tester.tap(_key('entry-editor-face-3'));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'scoreRaw': 85});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('custom lists come from the user\'s list names', (tester) async {
    api.customListNames = ['Favs', 'Rewatch'];
    await _open(tester, api, entry: _entry(customLists: {'Favs': true, 'Rewatch': false}));

    expect(tester.widget<FilterChip>(_key('entry-editor-list-Favs')).selected, isTrue);
    await tester.tap(_key('entry-editor-list-Rewatch'));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {
      'mediaId': 1,
      'customLists': ['Favs', 'Rewatch'],
    });
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an entry cached before the new fields is looked up first', (tester) async {
    api.lookupEntry = _entry(repeat: 3, private: true);
    final cached = {
      'id': 100,
      'status': 'CURRENT',
      'progress': 5,
      'score': 7.5,
      'notes': 'Great',
      'customLists': null,
    };

    await _open(tester, api, entry: cached);

    expect(api.lookups, hasLength(1));
    expect(_fieldText(tester, 'entry-editor-repeat'), '3');
    expect(_switch(tester, 'entry-editor-private').value, isTrue);
  });

  testWidgets('when that lookup fails, unknown fields stay locked and unsent', (tester) async {
    api.lookupFails = true;
    final cached = {
      'id': 100,
      'status': 'PLANNING',
      'progress': 0,
      'score': 0,
      'notes': '',
      'customLists': null,
    };

    await _open(tester, api, entry: cached);

    expect(_switch(tester, 'entry-editor-private').onChanged, isNull);
    expect(_key('entry-editor-repeat'), findsNothing);
    expect(_inside('entry-editor-started', find.text('—')), findsOneWidget);

    // Watching can't fill in a start date that might already exist.
    await tester.tap(_key('entry-editor-status-CURRENT'));
    await tester.pump();
    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'status': 'CURRENT'});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('quick add opens a media that isn\'t listed as a new Planning entry', (tester) async {
    await _open(tester, api, entryKnown: false);

    expect(api.lookups, hasLength(1));
    expect(_chipSelected(tester, 'PLANNING'), isTrue);
    expect(_key('entry-editor-remove'), findsNothing);
    expect(find.text('Add to List'), findsOneWidget);

    await _save(tester);

    expect(api.saves.single.variables, {'mediaId': 1, 'status': 'PLANNING'});
    expect(_results, [EntryEditorResult.saved]);
    expect(api.listReloads, isNotEmpty, reason: 'My List picks up the new entry');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('quick add of a listed media edits that entry and learns its type', (tester) async {
    api
      ..lookupType = 'MANGA'
      ..lookupEntry = _entry(status: 'CURRENT', progressVolumes: 4);
    const guessed = EditorMedia(id: 2, isManga: false, title: {'english': 'Berserk'});

    await _open(tester, api, media: guessed, entryKnown: false);

    expect(_chipSelected(tester, 'CURRENT'), isTrue);
    expect(_key('entry-editor-remove'), findsOneWidget);
    expect(_fieldText(tester, 'entry-editor-volumes'), '4');
    expect(_fieldText(tester, 'entry-editor-progress'), '5');
  });

  testWidgets('quick add shows a retry when the lookup fails and saves nothing', (tester) async {
    api.lookupFails = true;

    await _open(tester, api, entryKnown: false);

    expect(_key('entry-editor-lookup-error'), findsOneWidget);
    expect(_key('entry-editor-save'), findsNothing);

    api.lookupFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(_chipSelected(tester, 'PLANNING'), isTrue);
    expect(api.saves, isEmpty);
  });

  testWidgets('a rejected save keeps the sheet open with the error', (tester) async {
    api.saveFails = true;
    await _open(tester, api, entry: _entry());

    await tester.tap(_inside('entry-editor-progress', find.byIcon(Icons.add)));
    await tester.pump();
    await _save(tester);

    expect(find.text("Couldn't save. Please try again."), findsOneWidget);
    expect(_key('entry-editor-form'), findsOneWidget);
    expect(_results, isEmpty);
  });

  testWidgets('remove asks first, deletes the entry and drops it from My List', (tester) async {
    // The notifications plugin isn't registered under `flutter test`.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final reminderCalls = <MethodCall>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      reminderCalls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await api.store.load('ANIME', userId: 7, token: 'token');
    expect(api.store.listsOf('ANIME')!['CURRENT'], hasLength(1));
    await _open(tester, api, entry: _entry());

    await tester.tap(_key('entry-editor-remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_requests(api, 'DeleteMediaListEntry'), isEmpty);

    await tester.tap(_key('entry-editor-remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(_requests(api, 'DeleteMediaListEntry').single.variables, {'id': 100});
    expect(api.store.listsOf('ANIME')!['CURRENT'], isEmpty);
    expect(_results, [EntryEditorResult.removed]);
    expect(find.text('Removed from your list'), findsOneWidget);
    expect(reminderCalls.map((call) => (call.method, (call.arguments as Map)['id'])), [('cancel', 1)]);
    await tester.pump(const Duration(seconds: 5));
  });
}

List<RecordedRequest> _requests(_AniList api, String operation) =>
    [for (final request in api.log) if (request.query.contains(operation)) request];
