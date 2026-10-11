import 'dart:async';

import 'package:anispark/providers/media_list_store.dart';
import 'package:anispark/services/affinity_api.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/entry_editor/entry_draft.dart';
import 'package:anispark/widgets/entry_editor/entry_editor_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/memory_cache_store.dart';
import '../../helpers/mock_anilist.dart';

const _token = 'token';
const _viewerId = 7;
const _otherId = 9;
const _media = EditorMedia(id: 1, isManga: false);

Map<String, dynamic> _collection(List<Map<String, dynamic>> entries) => {
  'data': {
    'MediaListCollection': {
      'lists': [
        {
          'name': 'Watching',
          'status': 'CURRENT',
          'isCustomList': false,
          'entries': entries,
        },
      ],
    },
  },
};

/// A fake AniList for the editor's save and delete, My List's loads and
/// affinity's list reads.
class _AniList {
  final log = <RecordedRequest>[];
  final cache = ApiCache(MemoryCacheStore());
  bool saveFails = false;

  /// While set, My List's loads wait for it.
  Completer<void>? listGate;

  late final service = AniListService(
    client: MockClient((request) async {
      final recorded = RecordedRequest(request);
      log.add(recorded);
      return _respond(recorded);
    }),
  );
  late final store = MediaListStore(
    service: service,
    cache: cache,
    persistDelay: Duration.zero,
  );
  late final affinity = AffinityApi(service: service);

  Iterable<RecordedRequest> get listLoads => log.where(
    (r) => r.query.contains('entries') && !r.query.contains('status_not'),
  );

  Iterable<RecordedRequest> viewerAffinityReads() => log.where(
    (r) =>
        r.query.contains('status_not: PLANNING') &&
        r.variables['userId'] == _viewerId,
  );

  Future<http.Response> _respond(RecordedRequest request) async {
    final query = request.query;
    if (query.contains('SaveMediaListEntry')) {
      if (saveFails) {
        return jsonResponse({
          'data': {'SaveMediaListEntry': null},
        });
      }
      return jsonResponse({
        'data': {
          'SaveMediaListEntry': {
            'id': 100,
            'status': 'CURRENT',
            'progress': 6,
            'score': 0,
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
    if (query.contains('status_not: PLANNING')) {
      return jsonResponse(
        _collection([
          {'mediaId': 1, 'status': 'CURRENT', 'score': 80},
        ]),
      );
    }
    await listGate?.future;
    return jsonResponse(
      _collection([
        {
          'id': 100,
          'mediaId': 1,
          'progress': 5,
          'score': 0,
          'media': {'id': 1},
        },
      ]),
    );
  }

  Future<Map<String, dynamic>?> save() => saveEntryChanges(
    service: service,
    store: store,
    media: _media,
    changes: const EntryChanges(progress: 6),
    token: _token,
    userId: _viewerId,
  );

  Future<void> compare() => affinity.fetchShared(
    viewerId: _viewerId,
    otherId: _otherId,
    type: 'ANIME',
    token: _token,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AniList api;

  setUp(() {
    api = _AniList();
    AffinityApi.clearViewerMemo();
  });

  tearDown(() => api.store.dispose());

  group('saveEntryChanges', () {
    test('does not download a list type My List never loaded', () async {
      final saved = await api.save();
      await pumpEventQueue();

      expect(saved, isNotNull);
      expect(api.listLoads, isEmpty, reason: 'My List loads it when opened');
    });

    test('reloads the type My List has loaded', () async {
      await api.store.load('ANIME', userId: _viewerId, token: _token);
      api.log.clear();

      await api.save();
      await pumpEventQueue();

      expect(api.listLoads, hasLength(1));
    });

    test(
      'reloads after the load My List is running, whose data may predate the save',
      () async {
        api.listGate = Completer<void>();
        final firstLoad = api.store.load(
          'ANIME',
          userId: _viewerId,
          token: _token,
        );
        await pumpEventQueue();

        await api.save();
        api.listGate!.complete();
        await firstLoad;
        await pumpEventQueue();

        expect(api.listLoads, hasLength(2));
      },
    );

    test('makes the next comparison read the viewer\'s list again', () async {
      await api.compare();
      await api.compare();
      expect(
        api.viewerAffinityReads(),
        hasLength(1),
        reason: 'memoized between profiles',
      );

      await api.save();
      await api.compare();

      expect(api.viewerAffinityReads(), hasLength(2));
    });

    test('keeps the comparison memo when AniList rejects the save', () async {
      api.saveFails = true;
      await api.compare();

      expect(await api.save(), isNull);
      await api.compare();

      expect(api.viewerAffinityReads(), hasLength(1));
    });
  });

  group('removeEntry', () {
    setUp(() {
      // The notifications plugin isn't registered under `flutter test`.
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    });

    test('makes the next comparison read the viewer\'s list again', () async {
      await api.compare();

      final ok = await removeEntry(
        service: api.service,
        store: api.store,
        media: _media,
        entryId: 100,
        token: _token,
      );
      await api.compare();

      expect(ok, isTrue);
      expect(api.viewerAffinityReads(), hasLength(2));
    });
  });
}
