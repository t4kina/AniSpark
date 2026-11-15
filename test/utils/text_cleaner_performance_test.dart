import 'package:anispark/utils/activity_text.dart';
import 'package:anispark/utils/review_text.dart';
import 'package:flutter_test/flutter_test.dart';

// Hostile text repeats an opener whose closer never arrives; unbounded lazy
// quantifiers made the cleaners quadratic (seconds on the UI thread).
const _reps = 32000;

// A cleaner that went quadratic again would take many times this. It is
// loose on purpose: CI runs the whole suite at once on a slower machine,
// where a clean that takes a tenth of a second here took over a second.
const _limit = Duration(seconds: 3);

/// The quickest of a few runs of [clean]: the one least disturbed by the
/// first-run warm-up and by whatever else the machine was doing.
Duration _fastest(void Function() clean) {
  var best = const Duration(days: 1);
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    clean();
    sw.stop();
    if (sw.elapsed < best) best = sw.elapsed;
  }
  return best;
}

void main() {
  const openers = ['<a ', '[a](', 'img(', '~!', '**', '~~', '__', '*a ', '![', '<b '];

  for (final opener in openers) {
    final hostile = opener * _reps;
    test('cleanActivityText stays fast on $opener x$_reps', () {
      expect(_fastest(() => cleanActivityText(hostile)), lessThan(_limit));
    });
    test('cleanReviewText stays fast on $opener x$_reps', () {
      expect(_fastest(() => cleanReviewText(hostile)), lessThan(_limit));
    });
  }

  test('long spoilers and bold paragraphs still clean in reviews', () {
    final spoiler = 'x' * 15000;
    expect(cleanReviewText('a ~!$spoiler!~ b'), 'a [spoiler] b');
    final bold = 'word ' * 300;
    expect(cleanReviewText('**$bold**').trim(), bold.trim());
  });

  test('repeated calls return the same cleaned text', () {
    expect(cleanActivityText('**hi** ~!s!~'), cleanActivityText('**hi** ~!s!~'));
    expect(cleanActivityText('~!s!~', spoilerLabel: 'X'), 'X');
    expect(cleanActivityText('~!s!~'), '[spoiler]');
    expect(cleanReviewText('~!s!~', spoilerPlaceholder: 'X'), 'X');
    expect(cleanReviewText('~!s!~'), '[spoiler]');
  });
}
