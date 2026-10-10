import 'package:anispark/utils/affinity.dart';
import 'package:flutter_test/flutter_test.dart';

AffinityEntry _entry(int id, double score, {String status = 'COMPLETED', String? title}) =>
    AffinityEntry(
      mediaId: id,
      score: score,
      status: status,
      title: title == null ? null : {'english': title},
    );

/// Two lists sharing ids 1..n, scored [mine] and [theirs].
List<SharedTitle> _shared(List<double> mine, List<double> theirs) => sharedTitles(
      [for (var i = 0; i < mine.length; i++) _entry(i + 1, mine[i])],
      [for (var i = 0; i < theirs.length; i++) _entry(i + 1, theirs[i])],
    );

void main() {
  group('pearson', () {
    test('is 1 for scores that rise together', () {
      expect(pearson([10, 20, 30, 40], [55, 65, 75, 85]), closeTo(1, 1e-12));
    });

    test('is -1 for opposite scores', () {
      expect(pearson([10, 20, 30, 40], [90, 80, 70, 60]), closeTo(-1, 1e-12));
    });

    test('matches a hand-computed coefficient', () {
      // x̄ = 3, ȳ = 4; Σdxdy = 9, Σdx² = 10, Σdy² = 10 → r = 0.9
      expect(pearson([1, 2, 3, 4, 5], [2, 4, 3, 5, 6]), closeTo(0.9, 1e-12));
    });

    test('is null when either side has no variance, instead of NaN', () {
      expect(pearson([70, 70, 70], [10, 50, 90]), isNull);
      expect(pearson([10, 50, 90], [80, 80, 80]), isNull);
      expect(pearson([60, 60], [60, 60]), isNull);
    });

    test('treats float noise around a constant as no variance', () {
      const tenth = 0.1;
      expect(pearson([tenth, tenth, tenth], [1, 2, 3]), isNull);
    });

    test('is null for fewer than two pairs or mismatched lengths', () {
      expect(pearson([], []), isNull);
      expect(pearson([50], [60]), isNull);
      expect(pearson([10, 20, 30], [10, 20]), isNull);
    });
  });

  group('sharedTitles', () {
    test('keeps only titles on both lists, with both scores and statuses', () {
      final shared = sharedTitles(
        [_entry(1, 80, title: 'Bebop'), _entry(2, 70), _entry(3, 0, status: 'CURRENT')],
        [_entry(3, 90, status: 'DROPPED'), _entry(1, 60), _entry(4, 50)],
      );

      expect(shared.map((t) => t.mediaId), [1, 3]);
      final bebop = shared.first;
      expect(bebop.myScore, 80);
      expect(bebop.theirScore, 60);
      expect(bebop.title, {'english': 'Bebop'});
      expect(shared.last.myStatus, 'CURRENT');
      expect(shared.last.theirStatus, 'DROPPED');
    });

    test('counts an entry repeated across custom lists once', () {
      final shared = sharedTitles(
        [_entry(1, 80), _entry(1, 80), _entry(2, 40)],
        [_entry(1, 90), _entry(2, 30), _entry(1, 90), _entry(2, 30)],
      );

      expect(shared.map((t) => t.mediaId), [1, 2]);
    });

    test('prefers a scored copy of a repeated entry', () {
      final shared = sharedTitles([_entry(1, 0), _entry(1, 75)], [_entry(1, 60)]);

      expect(shared.single.myScore, 75);
    });

    test('is empty when either list is empty', () {
      expect(sharedTitles([], [_entry(1, 50)]), isEmpty);
      expect(sharedTitles([_entry(1, 50)], []), isEmpty);
    });
  });

  group('SharedTitle', () {
    test('has a gap only when both users scored it', () {
      const both = SharedTitle(mediaId: 1, myScore: 80, theirScore: 55);
      const onlyMine = SharedTitle(mediaId: 2, myScore: 80, theirScore: 0);

      expect(both.bothScored, isTrue);
      expect(both.gap, 25);
      expect(onlyMine.bothScored, isFalse);
      expect(onlyMine.gap, isNull);
    });

    test('survives a JSON round trip', () {
      const title = SharedTitle(
        mediaId: 9,
        myScore: 85,
        theirScore: 40,
        myStatus: 'COMPLETED',
        theirStatus: 'DROPPED',
        title: {'romaji': 'Kaubōi Bibappu', 'english': 'Cowboy Bebop'},
        coverUrl: 'https://img/9.jpg',
      );

      final decoded = SharedTitle.listFromJson([title.toJson()]).single;

      expect(decoded.mediaId, 9);
      expect(decoded.myScore, 85);
      expect(decoded.theirScore, 40);
      expect(decoded.myStatus, 'COMPLETED');
      expect(decoded.theirStatus, 'DROPPED');
      expect(decoded.title, {'romaji': 'Kaubōi Bibappu', 'english': 'Cowboy Bebop'});
      expect(decoded.coverUrl, 'https://img/9.jpg');
    });

    test('skips malformed cached entries and rejects a non-list', () {
      final decoded = SharedTitle.listFromJson([
        {'id': 1, 'm': 80, 't': 70},
        {'id': 'two', 'm': 80, 't': 70},
        'junk',
        {'id': 3},
      ]);

      expect(decoded.map((t) => t.mediaId), [1, 3]);
      expect(decoded.last.myScore, 0);
      expect(() => SharedTitle.listFromJson({'id': 1}), throwsFormatException);
    });
  });

  group('Affinity.of', () {
    final ten = [for (var i = 1; i <= minScoredInCommon; i++) i * 10.0];

    test('is 100% for perfect agreement', () {
      final affinity = Affinity.of(_shared(ten, ten));

      expect(affinity.outcome, AffinityOutcome.computed);
      expect(affinity.percent, 100);
      expect(affinity.tier, AffinityTier.strong);
      expect(affinity.scoredInCommon, minScoredInCommon);
    });

    test('is -100% for opposite tastes', () {
      final affinity = Affinity.of(_shared(ten, ten.reversed.toList()));

      expect(affinity.percent, -100);
      expect(affinity.tier, AffinityTier.opposite);
    });

    test('ignores the users\' offsets, so harsh and generous scorers can agree', () {
      final harsh = [for (final s in ten) s / 2];

      expect(Affinity.of(_shared(ten, harsh)).percent, 100);
    });

    test('needs enough titles scored by both', () {
      final few = ten.take(minScoredInCommon - 1).toList();
      final affinity = Affinity.of(_shared(few, few));

      expect(affinity.outcome, AffinityOutcome.notEnoughTitles);
      expect(affinity.percent, isNull);
      expect(affinity.correlation, isNull);
      expect(affinity.tier, isNull);
      expect(affinity.shared, hasLength(minScoredInCommon - 1));
    });

    test('honours a custom minimum', () {
      final affinity = Affinity.of(_shared([10, 20, 30], [10, 20, 30]), minScored: 3);

      expect(affinity.percent, 100);
    });

    test('reports uniform scores instead of NaN', () {
      final flat = List<double>.filled(minScoredInCommon, 70);
      final affinity = Affinity.of(_shared(flat, ten));

      expect(affinity.outcome, AffinityOutcome.uniformScores);
      expect(affinity.percent, isNull);
      expect(affinity.myMean, 70);
    });

    test('leaves out titles either user left unscored', () {
      final mine = [...ten, 0.0, 90.0];
      final theirs = [...ten, 50.0, 0.0];
      final affinity = Affinity.of(_shared(mine, theirs));

      expect(affinity.shared, hasLength(minScoredInCommon + 2));
      expect(affinity.scoredInCommon, minScoredInCommon);
      expect(affinity.percent, 100);
    });

    test('averages each user\'s scores over the titles both scored', () {
      final affinity = Affinity.of(
        _shared([80, 60, 0], [40, 20, 100]),
        minScored: 2,
      );

      expect(affinity.myMean, 70);
      expect(affinity.theirMean, 30);
    });

    test('has no means without titles scored by both', () {
      final affinity = Affinity.of(_shared([80, 0], [0, 50]));

      expect(affinity.myMean, isNull);
      expect(affinity.theirMean, isNull);
    });

    test('counts shared titles only one of them completed (rewatching counts)', () {
      final affinity = Affinity.of(sharedTitles(
        [
          _entry(1, 0),
          _entry(2, 0, status: 'CURRENT'),
          _entry(3, 0, status: 'REPEATING'),
          _entry(4, 0, status: 'DROPPED'),
          _entry(5, 0, status: 'PAUSED'),
        ],
        [
          _entry(1, 0),
          _entry(2, 0),
          _entry(3, 0, status: 'PAUSED'),
          _entry(4, 0, status: 'CURRENT'),
          _entry(5, 0, status: 'REPEATING'),
        ],
      ));

      expect(affinity.completedOnlyByMe, 1, reason: 'title 3');
      expect(affinity.completedOnlyByThem, 2, reason: 'titles 2 and 5');
    });

    test('rounds the percentage', () {
      // Σdxdy = 3, Σdx² = 2, Σdy² = 42/9 → r = 3 / √(28/3) ≈ 0.982 → 98%
      final affinity = Affinity.of(_shared([10, 20, 30], [10, 20, 40]), minScored: 3);

      expect(affinity.correlation, closeTo(0.98198, 1e-5));
      expect(affinity.percent, 98);
    });
  });

  group('tierOf', () {
    test('bands the percentage', () {
      expect(tierOf(100), AffinityTier.strong);
      expect(tierOf(60), AffinityTier.strong);
      expect(tierOf(59), AffinityTier.moderate);
      expect(tierOf(30), AffinityTier.moderate);
      expect(tierOf(29), AffinityTier.weak);
      expect(tierOf(0), AffinityTier.weak);
      expect(tierOf(-1), AffinityTier.opposite);
    });
  });

  group('sortShared', () {
    const a = SharedTitle(mediaId: 1, myScore: 90, theirScore: 40, title: {'english': 'Alpha'});
    const b = SharedTitle(mediaId: 2, myScore: 70, theirScore: 70, title: {'english': 'bravo'});
    const c = SharedTitle(mediaId: 3, myScore: 50, theirScore: 60, title: {'english': 'Charlie'});
    const d = SharedTitle(mediaId: 4, myScore: 0, theirScore: 80, title: {'english': 'Delta'});
    const e = SharedTitle(mediaId: 5, myScore: 95, theirScore: 85, title: {'english': 'Echo'});
    final all = [d, c, a, e, b];
    String titleOf(SharedTitle t) => t.title?['english'] as String? ?? '';

    test('by agreement: smallest gap first, loved titles first on ties, unscored last', () {
      final sorted = sortShared(all, CompareSort.agreement, titleOf);

      expect(sorted.map((t) => t.mediaId), [2, 5, 3, 1, 4]);
    });

    test('by disagreement: biggest gap first, unscored last', () {
      final sorted = sortShared(all, CompareSort.disagreement, titleOf);

      expect(sorted.map((t) => t.mediaId), [1, 5, 3, 2, 4]);
    });

    test('by title, ignoring case', () {
      final sorted = sortShared(all, CompareSort.title, titleOf);

      expect(sorted.map((t) => t.mediaId), [1, 2, 3, 4, 5]);
    });

    test('returns a new list and leaves the input untouched', () {
      final input = [d, c];
      final sorted = sortShared(input, CompareSort.title, titleOf);

      expect(identical(sorted, input), isFalse);
      expect(input.map((t) => t.mediaId), [4, 3]);
    });
  });
}
