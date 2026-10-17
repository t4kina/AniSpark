import 'package:anispark/utils/airing_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

/// An AniList airing schedule entry airing at local [time].
Map<String, dynamic> _airing(int id, DateTime time, {String? status}) => {
      'id': id,
      'airingAt': time.millisecondsSinceEpoch ~/ 1000,
      'episode': 1,
      'media': {
        'id': id,
        'mediaListEntry': status == null ? null : {'status': status},
      },
    };

void main() {
  group('groupByLocalDay', () {
    test('groups episodes by the local day they air on, in time order', () {
      final days = groupByLocalDay([
        _airing(3, DateTime(2026, 10, 11, 9, 0)),
        _airing(1, DateTime(2026, 10, 10, 18, 30)),
        _airing(2, DateTime(2026, 10, 10, 23, 59)),
        _airing(4, DateTime(2026, 10, 13, 0, 0)),
      ]);

      expect(days.map((d) => d.date), [
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 13),
      ]);
      expect(days.map((d) => d.episodes.map((e) => e['id']).toList()), [
        [1, 2],
        [3],
        [4],
      ]);
    });

    test('keeps the given order of episodes airing at the same time', () {
      final time = DateTime(2026, 10, 10, 12);

      final days = groupByLocalDay([for (var id = 1; id <= 20; id++) _airing(id, time)]);

      expect(days.single.episodes.map((e) => e['id']), [for (var id = 1; id <= 20; id++) id]);
    });

    test('skips entries without a valid airingAt', () {
      final days = groupByLocalDay([
        {'id': 1, 'airingAt': null},
        {'id': 2, 'airingAt': 'soon'},
        _airing(3, DateTime(2026, 10, 10, 12)),
      ]);

      expect(days.single.episodes.map((e) => e['id']), [3]);
    });

    test('returns no days for no episodes', () {
      expect(groupByLocalDay(const []), isEmpty);
    });

    test('returns unmodifiable episode lists', () {
      final days = groupByLocalDay([_airing(1, DateTime(2026, 10, 10, 12))]);

      expect(() => days.single.episodes.add({}), throwsUnsupportedError);
    });
  });

  group('calendarDaysBetween', () {
    test('counts calendar days, not 24-hour periods', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 10, 23, 59), DateTime(2026, 10, 11, 0, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 10, 0, 1), DateTime(2026, 10, 10, 23, 59)), 0);
      expect(calendarDaysBetween(DateTime(2026, 10, 10), DateTime(2026, 10, 16)), 6);
    });

    test('is unaffected by daylight-saving changes and month ends', () {
      // Spans the EU and US spring-forward days.
      expect(calendarDaysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 30)), 23);
      expect(calendarDaysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
    });
  });

  test('localDay drops the time of day', () {
    expect(localDay(DateTime(2026, 10, 10, 23, 59, 59)), DateTime(2026, 10, 10));
  });

  test('airingTime converts epoch seconds to local time', () {
    final time = DateTime(2026, 10, 10, 18, 30);

    expect(airingTime(_airing(1, time)), time);
    expect(airingTime(const {'airingAt': null}), isNull);
  });

  test('formatClock pads hours and minutes', () {
    expect(formatClock(DateTime(2026, 10, 10, 7, 5)), '07:05');
    expect(formatClock(DateTime(2026, 10, 10, 23, 45)), '23:45');
  });

  group('list status', () {
    final time = DateTime(2026, 10, 10, 12);

    test('listStatusOf reads mediaListEntry.status', () {
      expect(listStatusOf(_airing(1, time, status: 'COMPLETED')), 'COMPLETED');
      expect(listStatusOf(_airing(1, time)), isNull);
      expect(listStatusOf(const {'media': null}), isNull);
    });

    test('isOnWatchList is true only for CURRENT and PLANNING', () {
      expect(isOnWatchList(_airing(1, time, status: 'CURRENT')), isTrue);
      expect(isOnWatchList(_airing(1, time, status: 'PLANNING')), isTrue);
      for (final status in ['COMPLETED', 'DROPPED', 'PAUSED', 'REPEATING']) {
        expect(isOnWatchList(_airing(1, time, status: status)), isFalse, reason: status);
      }
      expect(isOnWatchList(_airing(1, time)), isFalse);
    });
  });
}
