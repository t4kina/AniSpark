import 'package:anispark/utils/activity_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activityStatusKey', () {
    test('maps every status AniList sends for list activities', () {
      const statuses = [
        'watched episode',
        'read chapter',
        'rewatched episode',
        'reread chapter',
        'plans to watch',
        'plans to read',
        'completed',
        'dropped',
        'paused watching',
        'paused reading',
        'watching',
        'reading',
      ];
      for (final status in statuses) {
        expect(
          activityStatusKey(status, hasProgress: false),
          isNotNull,
          reason: status,
        );
      }
    });

    test('uses the progress wording only for statuses that carry progress', () {
      expect(
        activityStatusKey('watched episode', hasProgress: true),
        isNot(activityStatusKey('watched episode', hasProgress: false)),
      );
      expect(
        activityStatusKey('completed', hasProgress: true),
        activityStatusKey('completed', hasProgress: false),
      );
    });

    test('ignores case and surrounding spaces', () {
      expect(
        activityStatusKey(' Watched Episode ', hasProgress: true),
        activityStatusKey('watched episode', hasProgress: true),
      );
    });

    test('returns null for unknown statuses', () {
      expect(activityStatusKey('did a backflip', hasProgress: false), isNull);
      expect(activityStatusKey('', hasProgress: false), isNull);
    });
  });

  group('activityStatusText', () {
    test('falls back to the raw text for an unknown status', () {
      expect(
        activityStatusText('did a backflip', null, 'English'),
        'did a backflip',
      );
    });

    test('keeps the progress next to an unknown status', () {
      final text = activityStatusText('did a backflip', 3, 'English');
      expect(text, contains('did a backflip'));
      expect(text, contains('3'));
    });

    test('is empty without a status', () {
      expect(activityStatusText(null, null, 'English'), '');
    });
  });
}
