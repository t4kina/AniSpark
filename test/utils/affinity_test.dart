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
  group('scoreCloseness', () {
    test('is 1 for the same scores', () {
      expect(scoreCloseness([70, 80, 90], [70, 80, 90]), 1);
    });

    test('falls evenly with the gap, to nothing four points out of ten apart', () {
      expect(scoreCloseness([80], [70]), 0.75, reason: 'a point apart');
      expect(scoreCloseness([80], [60]), 0.5);
      expect(scoreCloseness([80], [50]), 0.25);
      expect(scoreCloseness([80], [40]), 0);
      expect(scoreCloseness([100], [10]), 0, reason: 'no lower than nothing');
    });

    test('is the mean over the titles', () {
      expect(scoreCloseness([80, 80], [80, 60]), 0.75);
    });

    test('is null without pairs or for mismatched lengths', () {
      expect(scoreCloseness([], []), isNull);
      expect(scoreCloseness([80, 90], [80]), isNull);
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
    final ten = [for (var i = 1; i <= minScoredInCommon; i++) 50 + i * 4.0];

    test('is 100% for the same scores', () {
      final affinity = Affinity.of(_shared(ten, ten));

      expect(affinity.outcome, AffinityOutcome.computed);
      expect(affinity.percent, 100);
      expect(affinity.tier, AffinityTier.strong);
      expect(affinity.scoredInCommon, minScoredInCommon);
    });

    test('two people who mostly give the same 7 to 9 are very similar, not "different"', () {
      // What a real pair of friends looked like: many identical scores in a
      // narrow band, a few a point apart. Pearson called this about 0%.
      final mine = <double>[100.0, 80, 80, 80, 81, 85, 70, 90, 80, 75, 85, 80];
      final theirs = <double>[100.0, 80, 80, 80, 80, 80, 80, 80, 80, 80, 90, 85];
      final affinity = Affinity.of(_shared(mine, theirs));

      expect(affinity.percent, greaterThanOrEqualTo(75));
      expect(affinity.tier, AffinityTier.strong);
    });

    test('scores far apart on every title are opposite tastes', () {
      final affinity = Affinity.of(_shared(
        List<double>.filled(minScoredInCommon, 90),
        List<double>.filled(minScoredInCommon, 30),
      ));

      expect(affinity.percent, 0);
      expect(affinity.tier, AffinityTier.opposite);
    });

    test('the same score on every title is still a match', () {
      final flat = List<double>.filled(minScoredInCommon, 70);

      expect(Affinity.of(_shared(flat, flat)).percent, 100);
    });

    test('needs enough titles scored by both', () {
      final few = ten.take(minScoredInCommon - 1).toList();
      final affinity = Affinity.of(_shared(few, few));

      expect(affinity.outcome, AffinityOutcome.notEnoughTitles);
      expect(affinity.percent, isNull);
      expect(affinity.closeness, isNull);
      expect(affinity.tier, isNull);
      expect(affinity.shared, hasLength(minScoredInCommon - 1));
    });

    test('honours a custom minimum', () {
      final affinity = Affinity.of(_shared([10, 20, 30], [10, 20, 30]), minScored: 3);

      expect(affinity.percent, 100);
    });

    test('leaves out titles either user left unscored', () {
      final mine = [...ten, 0.0, 90.0];
      final theirs = [...ten, 50.0, 0.0];
      final affinity = Affinity.of(_shared(mine, theirs));

      expect(affinity.shared, hasLength(minScoredInCommon + 2));
      expect(affinity.scoredInCommon, minScoredInCommon);
      expect(affinity.percent, 100);
    });

    test("averages each user's scores over the titles both scored", () {
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
      // Closeness 1, 0.75 and 0.9 → 0.8833… → 88%.
      final affinity = Affinity.of(_shared([10, 20, 30], [10, 30, 34]), minScored: 3);

      expect(affinity.closeness, closeTo(0.88333, 1e-5));
      expect(affinity.percent, 88);
    });
  });

  group('tierOf', () {
    test('bands the percentage', () {
      expect(tierOf(100), AffinityTier.strong);
      expect(tierOf(75), AffinityTier.strong);
      expect(tierOf(74), AffinityTier.moderate);
      expect(tierOf(55), AffinityTier.moderate);
      expect(tierOf(54), AffinityTier.weak);
      expect(tierOf(35), AffinityTier.weak);
      expect(tierOf(34), AffinityTier.opposite);
      expect(tierOf(0), AffinityTier.opposite);
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
