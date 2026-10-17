import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

void main() {
  const token = 'test-token';
  late List<RecordedRequest> log;

  AniListService serviceReturning(Object body, {int status = 200}) =>
      AniListService(
        client: mockAniList(log, (_) => jsonResponse(body, status: status)),
      );

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
    rateLimitActiveNotifier.value = false;
  });

  group('saveListEntry', () {
    final savedResponse = {
      'data': {
        'SaveMediaListEntry': {'id': 1, 'status': 'CURRENT', 'progress': 5},
      },
    };

    test('progress-only update sends only mediaId and progress and returns the entry', () async {
      final service = serviceReturning(savedResponse);

      final saved = await service.saveListEntry(
        mediaId: 42,
        progress: 5,
        token: token,
      );

      expect(saved, containsPair('progress', 5));
      expect(log.single.query, contains('score(format: POINT_10_DECIMAL)'));
      expect(log.single.variables, {'mediaId': 42, 'progress': 5});
      for (final field in ['score', 'scoreRaw', 'notes', 'customLists', 'status']) {
        expect(log.single.query, isNot(contains('\$$field')),
            reason: '$field must not be declared on a progress-only update');
      }
    });

    test('score is written as format-independent scoreRaw', () async {
      final service = serviceReturning(savedResponse);

      await service.saveListEntry(mediaId: 42, scoreRaw: 75, token: token);

      expect(log.single.variables, {'mediaId': 42, 'scoreRaw': 75});
      expect(log.single.query, contains('scoreRaw: \$scoreRaw'));
      expect(log.single.query, isNot(contains('score: \$score')));
    });

    test('sends status, notes and custom lists when provided', () async {
      final service = serviceReturning(savedResponse);

      await service.saveListEntry(
        mediaId: 42,
        status: 'COMPLETED',
        progress: 12,
        notes: '',
        customLists: const [],
        token: token,
      );

      expect(log.single.variables, {
        'mediaId': 42,
        'status': 'COMPLETED',
        'progress': 12,
        'notes': '',
        'customLists': <String>[],
      });
    });

    test('sends the bearer token', () async {
      final service = serviceReturning(savedResponse);

      await service.saveListEntry(mediaId: 42, progress: 1, token: token);

      expect(log.single.authorization, 'Bearer $token');
    });

    test('returns null when the response has no entry', () async {
      final service = serviceReturning({
        'data': {'SaveMediaListEntry': null},
        'errors': [
          {'message': 'Validation error'},
        ],
      });

      final saved = await service.saveListEntry(mediaId: 42, progress: 1, token: token);

      expect(saved, isNull);
    });

    test('returns null and fires authExpiredNotifier on 401', () async {
      final service = serviceReturning({'errors': []}, status: 401);

      final saved = await service.saveListEntry(mediaId: 42, progress: 1, token: token);

      expect(saved, isNull);
      expect(authExpiredNotifier.value, 1);
    });
  });

  group('deleteListEntry', () {
    test('sends the entry id with the bearer token', () async {
      final service = serviceReturning({
        'data': {
          'DeleteMediaListEntry': {'deleted': true},
        },
      });

      final ok = await service.deleteListEntry(entryId: 7, token: token);

      expect(ok, isTrue);
      expect(log.single.variables, {'id': 7});
      expect(log.single.authorization, 'Bearer $token');
    });

    test('returns false when AniList does not confirm the deletion', () async {
      final service = serviceReturning({
        'data': {
          'DeleteMediaListEntry': {'deleted': false},
        },
      });

      final ok = await service.deleteListEntry(entryId: 7, token: token);

      expect(ok, isFalse);
    });
  });

  group('toggleFavourite', () {
    test('uses animeId for anime', () async {
      final service = serviceReturning({
        'data': {
          'ToggleFavourite': {
            'anime': {'nodes': []},
          },
        },
      });

      final ok = await service.toggleFavourite(mediaId: 5, token: token);

      expect(ok, isTrue);
      expect(log.single.query, contains('animeId: \$id'));
      expect(log.single.variables, {'id': 5});
      expect(log.single.authorization, 'Bearer $token');
    });

    test('uses mangaId for manga', () async {
      final service = serviceReturning({
        'data': {
          'ToggleFavourite': {
            'manga': {'nodes': []},
          },
        },
      });

      final ok = await service.toggleFavourite(
        mediaId: 9,
        isManga: true,
        token: token,
      );

      expect(ok, isTrue);
      expect(log.single.query, contains('mangaId: \$id'));
      expect(log.single.query, isNot(contains('animeId')));
    });

    test('returns false when the response has no data', () async {
      final service = serviceReturning({
        'data': {'ToggleFavourite': null},
      });

      final ok = await service.toggleFavourite(mediaId: 5, token: token);

      expect(ok, isFalse);
    });
  });

  group('network failures', () {
    late AniListService offline;

    setUp(() {
      offline = AniListService(
        client: mockAniList(log, (_) => throw http.ClientException('offline')),
      );
    });

    test('saveListEntry returns null instead of throwing', () async {
      final saved = await offline.saveListEntry(mediaId: 42, progress: 1, token: token);

      expect(saved, isNull);
    });

    test('deleteListEntry returns false instead of throwing', () async {
      final ok = await offline.deleteListEntry(entryId: 7, token: token);

      expect(ok, isFalse);
    });

    test('toggleFavourite returns false instead of throwing', () async {
      final ok = await offline.toggleFavourite(mediaId: 5, token: token);

      expect(ok, isFalse);
    });

    test('a non-JSON 200 body is treated as a failed save', () async {
      final service = AniListService(
        client: mockAniList(log, (_) => http.Response('<html>oops</html>', 200)),
      );

      final saved = await service.saveListEntry(mediaId: 42, progress: 1, token: token);

      expect(saved, isNull);
    });
  });

  group('user list queries', () {
    test('anime list reads scores with decimals', () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {'lists': []},
        },
      });

      await service.getUserAnimeList(1, token);

      expect(log.single.query, contains('score(format: POINT_10_DECIMAL)'));
    });

    test('manga list reads scores with decimals', () async {
      final service = serviceReturning({
        'data': {
          'MediaListCollection': {'lists': []},
        },
      });

      await service.getUserMangaList(1, token);

      expect(log.single.query, contains('score(format: POINT_10_DECIMAL)'));
    });
  });
}
