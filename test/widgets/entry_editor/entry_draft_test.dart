import 'package:anispark/widgets/entry_editor/entry_draft.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fullEntry({
  String status = 'CURRENT',
  int progress = 5,
  Map<String, dynamic>? startedAt,
  Map<String, dynamic>? completedAt,
}) =>
    {
      'id': 99,
      'status': status,
      'progress': progress,
      'progressVolumes': 1,
      'score': 7.5,
      'repeat': 2,
      'private': true,
      'hiddenFromStatusLists': false,
      'notes': 'note',
      'customLists': {'Favs': true, 'Other': false},
      'startedAt': startedAt ?? {'year': null, 'month': null, 'day': null},
      'completedAt': completedAt ?? {'year': null, 'month': null, 'day': null},
    };

final _today = DateTime(2026, 10, 10);
const _todayDate = FuzzyDate(year: 2026, month: 10, day: 10);

void main() {
  group('FuzzyDate', () {
    test('reads AniList dates and treats all-null parts as empty', () {
      expect(FuzzyDate.fromJson({'year': 2024, 'month': 3, 'day': 9}),
          const FuzzyDate(year: 2024, month: 3, day: 9));
      expect(FuzzyDate.fromJson({'year': null, 'month': null, 'day': null}).isEmpty, isTrue);
      expect(FuzzyDate.fromJson(null).isEmpty, isTrue);
    });

    test('an empty date becomes the input that clears it', () {
      expect(FuzzyDate.empty.toInput(), {'year': null, 'month': null, 'day': null});
      expect(const FuzzyDate(year: 2024).toInput(), {'year': 2024, 'month': null, 'day': null});
    });

    test('converts to a picker date, filling missing parts with the first', () {
      expect(const FuzzyDate(year: 2024).toDateTime(), DateTime(2024));
      expect(FuzzyDate.empty.toDateTime(), isNull);
    });
  });

  group('EntryDraft.fromEntry', () {
    test('reads every field of a full entry', () {
      final draft = EntryDraft.fromEntry(_fullEntry(startedAt: {'year': 2024, 'month': 1, 'day': 2}));

      expect(draft.status, 'CURRENT');
      expect(draft.progress, 5);
      expect(draft.progressVolumes, 1);
      expect(draft.score, 7.5);
      expect(draft.repeat, 2);
      expect(draft.private, isTrue);
      expect(draft.hiddenFromStatusLists, isFalse);
      expect(draft.notes, 'note');
      expect(draft.customLists, {'Favs'});
      expect(draft.startedAt, const FuzzyDate(year: 2024, month: 1, day: 2));
      expect(draft.completedAt.isEmpty, isTrue);
      expect(draft.unknown, isEmpty);
    });

    test('fields missing from older cached data are unknown, not empty', () {
      final draft = EntryDraft.fromEntry({
        'id': 1,
        'status': 'PLANNING',
        'progress': 0,
        'score': 0,
        'notes': null,
        'customLists': null,
      });

      expect(draft.unknown, {
        EntryField.progressVolumes,
        EntryField.repeat,
        EntryField.private,
        EntryField.hiddenFromStatusLists,
        EntryField.startedAt,
        EntryField.completedAt,
      });
      expect(draft.notes, '');
      expect(draft.customLists, isEmpty);
    });

    test('a null value is known (AniList has no value), not unknown', () {
      final draft = EntryDraft.fromEntry({..._fullEntry(), 'progressVolumes': null, 'repeat': null});

      expect(draft.unknown, isEmpty);
      expect(draft.progressVolumes, 0);
      expect(draft.repeat, 0);
    });
  });

  group('withStatus auto-fill', () {
    test('watching an entry without a start date starts it today', () {
      final draft = EntryDraft.fromEntry(_fullEntry(status: 'PLANNING', progress: 0))
          .withStatus('CURRENT', today: _today);

      expect(draft.status, 'CURRENT');
      expect(draft.startedAt, _todayDate);
      expect(draft.completedAt.isEmpty, isTrue);
    });

    test('never replaces a start date the user already has', () {
      const started = {'year': 2020, 'month': 5, 'day': 1};
      final draft = EntryDraft.fromEntry(_fullEntry(status: 'PLANNING', startedAt: started))
          .withStatus('CURRENT', today: _today);

      expect(draft.startedAt, const FuzzyDate(year: 2020, month: 5, day: 1));
    });

    test('completing finishes today and sets progress and volumes to the totals', () {
      final draft = EntryDraft.fromEntry(_fullEntry(progress: 5))
          .withStatus('COMPLETED', today: _today, totalProgress: 12, totalVolumes: 3);

      expect(draft.completedAt, _todayDate);
      expect(draft.progress, 12);
      expect(draft.progressVolumes, 3);
    });

    test('completing keeps a finish date that is already set and an unknown total', () {
      const finished = {'year': 2021, 'month': null, 'day': null};
      final draft = EntryDraft.fromEntry(_fullEntry(completedAt: finished))
          .withStatus('COMPLETED', today: _today);

      expect(draft.completedAt, const FuzzyDate(year: 2021));
      expect(draft.progress, 5);
    });

    test('dates that are unknown are never auto-filled', () {
      final draft = EntryDraft.fromEntry({'status': 'PLANNING', 'progress': 0})
          .withStatus('CURRENT', today: _today)
          .withStatus('COMPLETED', today: _today);

      expect(draft.startedAt.isEmpty, isTrue);
      expect(draft.completedAt.isEmpty, isTrue);
    });

    test('switching away again undoes what the previous status filled in', () {
      final initial = EntryDraft.fromEntry(_fullEntry(progress: 5));
      final draft = initial
          .withStatus('COMPLETED', today: _today, totalProgress: 12)
          .withStatus('PAUSED', today: _today);

      expect(draft.progress, 5);
      expect(draft.completedAt.isEmpty, isTrue);
      expect(draft.changesFrom(initial, isNew: false).toArguments(), {'status': 'PAUSED'});
    });

    test('a value the user edits after the auto-fill is kept', () {
      final draft = EntryDraft.fromEntry(_fullEntry(progress: 5))
          .withStatus('COMPLETED', today: _today, totalProgress: 12)
          .withProgress(11)
          .withStatus('PAUSED', today: _today);

      expect(draft.progress, 11);
      expect(draft.completedAt.isEmpty, isTrue);
    });
  });

  group('changesFrom', () {
    test('an untouched entry has no changes', () {
      final initial = EntryDraft.fromEntry(_fullEntry());

      expect(initial.changesFrom(initial, isNew: false).isEmpty, isTrue);
    });

    test('only the changed fields are sent', () {
      final initial = EntryDraft.fromEntry(_fullEntry());
      final edited = initial
          .withProgress(6)
          .copyWith(score: 8.25, private: false, customLists: {'Favs', 'Other'})
          .withCompletedAt(const FuzzyDate(year: 2026, month: 1, day: 2));

      expect(edited.changesFrom(initial, isNew: false).toArguments(), {
        'progress': 6,
        'scoreRaw': 83,
        'private': false,
        'customLists': ['Favs', 'Other'],
        'completedAt': {'year': 2026, 'month': 1, 'day': 2},
      });
    });

    test('clearing a date sends the clearing input', () {
      final initial = EntryDraft.fromEntry(_fullEntry(startedAt: {'year': 2024, 'month': 1, 'day': 2}));
      final edited = initial.withStartedAt(FuzzyDate.empty);

      expect(edited.changesFrom(initial, isNew: false).toArguments(), {
        'startedAt': {'year': null, 'month': null, 'day': null},
      });
    });

    test('a score that rounds to the same raw value is unchanged', () {
      final initial = EntryDraft.fromEntry(_fullEntry());

      expect(initial.copyWith(score: 7.5).changesFrom(initial, isNew: false).isEmpty, isTrue);
    });

    test('notes are compared and sent trimmed', () {
      final initial = EntryDraft.fromEntry(_fullEntry());

      expect(initial.copyWith(notes: ' note  ').changesFrom(initial, isNew: false).isEmpty, isTrue);
      expect(initial.copyWith(notes: ' new ').changesFrom(initial, isNew: false).toArguments(),
          {'notes': 'new'});
    });

    test('a new entry always sends its status', () {
      final initial = EntryDraft.newEntry();

      expect(initial.status, 'PLANNING');
      expect(initial.changesFrom(initial, isNew: true).toArguments(), {'status': 'PLANNING'});
    });
  });

  test('status translation keys use reading words for manga', () {
    expect(entryStatusKey('CURRENT', manga: false), 'watching');
    expect(entryStatusKey('CURRENT', manga: true), 'reading');
    expect(entryStatusKey('PLANNING', manga: true), 'plan_to_read');
    expect(entryStatusKey('REPEATING', manga: true), 'rereading');
    expect(entryStatusKey('REPEATING', manga: false), 'rewatching');
    expect(entryStatusKey('PAUSED', manga: true), 'on_hold');
    expect(entryStatusKey('COMPLETED', manga: true), 'completed');
    expect(entryStatusKey('DROPPED', manga: false), 'dropped');
  });
}
