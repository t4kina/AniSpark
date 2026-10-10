import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_anilist.dart';

void main() {
  const token = 'test-token';
  late List<RecordedRequest> log;

  AniListService service() => AniListService(
        client: mockAniList(
          log,
          (_) => jsonResponse({
            'data': {
              'SaveMediaListEntry': {'id': 1, 'status': 'CURRENT', 'progress': 5},
            },
          }),
        ),
      );

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  group('saveListEntry full entry fields', () {
    test('sends volumes, rewatches and the visibility switches with their schema types', () async {
      await service().saveListEntry(
        mediaId: 42,
        progressVolumes: 3,
        repeat: 2,
        private: true,
        hiddenFromStatusLists: false,
        token: token,
      );

      expect(log.single.variables, {
        'mediaId': 42,
        'progressVolumes': 3,
        'repeat': 2,
        'private': true,
        'hiddenFromStatusLists': false,
      });
      final query = log.single.query;
      expect(query, contains('\$progressVolumes: Int'));
      expect(query, contains('\$repeat: Int'));
      expect(query, contains('\$private: Boolean'));
      expect(query, contains('\$hiddenFromStatusLists: Boolean'));
      expect(query, contains('progressVolumes: \$progressVolumes'));
      expect(query, contains('hiddenFromStatusLists: \$hiddenFromStatusLists'));
    });

    test('sends dates as FuzzyDateInput with all three parts', () async {
      await service().saveListEntry(
        mediaId: 42,
        startedAt: const {'year': 2024, 'month': 4, 'day': 7},
        completedAt: const {'year': 2025},
        token: token,
      );

      expect(log.single.variables['startedAt'], {'year': 2024, 'month': 4, 'day': 7});
      // Missing parts are sent as null so no stale month or day survives.
      expect(log.single.variables['completedAt'], {'year': 2025, 'month': null, 'day': null});
      expect(log.single.query, contains('\$startedAt: FuzzyDateInput'));
      expect(log.single.query, contains('\$completedAt: FuzzyDateInput'));
      expect(log.single.query, contains('completedAt: \$completedAt'));
    });

    test('an empty date map clears the date with explicit nulls', () async {
      await service().saveListEntry(
        mediaId: 42,
        startedAt: const {},
        token: token,
      );

      final startedAt = log.single.variables['startedAt'] as Map;
      expect(startedAt, {'year': null, 'month': null, 'day': null});
      // The keys must be present (explicit null), not just missing.
      expect(startedAt.keys, containsAll(['year', 'month', 'day']));
      expect(log.single.body['variables'], isNot(contains('completedAt')));
    });

    test('fields that are not given are neither declared nor sent', () async {
      await service().saveListEntry(mediaId: 42, progress: 4, token: token);

      expect(log.single.variables, {'mediaId': 42, 'progress': 4});
      for (final field in [
        'progressVolumes',
        'repeat',
        'private',
        'hiddenFromStatusLists',
        'startedAt',
        'completedAt',
      ]) {
        expect(log.single.query, isNot(contains('\$$field')),
            reason: '$field must not be declared when it is not changed');
      }
    });

    test('the response includes the full entry so callers can apply it', () async {
      await service().saveListEntry(mediaId: 42, progress: 4, token: token);

      final query = log.single.query;
      for (final field in [
        'progressVolumes',
        'repeat',
        'private',
        'hiddenFromStatusLists',
        'notes',
        'startedAt { year month day }',
        'completedAt { year month day }',
      ]) {
        expect(query, contains(field));
      }
    });
  });

  test('the detail query reads every field the entry editor shows', () async {
    final service = AniListService(
      client: mockAniList(log, (_) => jsonResponse({'data': {'Media': null}})),
    );

    await service.getAnimeDetail(1, token);

    final query = log.single.query.replaceAll(RegExp(r'\s+'), ' ');
    final entry = RegExp(r'mediaListEntry \{(.*?)\} relations').firstMatch(query)?.group(1);
    expect(entry, isNotNull);
    for (final field in [
      'id',
      'status',
      'progress',
      'progressVolumes',
      'score(format: POINT_10_DECIMAL)',
      'repeat',
      'private',
      'hiddenFromStatusLists',
      'notes',
      'customLists',
      'startedAt { year month day',
      'completedAt { year month day',
    ]) {
      expect(entry, contains(field));
    }
  });
}
