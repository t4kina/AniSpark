import 'package:anispark/utils/activity_text.dart';
import 'package:anispark/utils/review_text.dart';
import 'package:flutter_test/flutter_test.dart';

// Hostile text repeats an opener whose closer never arrives; unbounded lazy
// quantifiers made the cleaners quadratic (seconds on the UI thread).
const _reps = 32000;
const _limit = Duration(milliseconds: 1500);

void main() {
  final hostile = <String, String>{
    '<a ': '<a ' * _reps,
    '[a](': '[a](' * _reps,
    'img(': 'img(' * _reps,
    '~!': '~!' * _reps,
    '**': '**' * _reps,
    '~~': '~~' * _reps,
    '__': '__' * _reps,
    '*a ': '*a ' * _reps,
    '![': '![' * _reps,
    '<b ': '<b ' * _reps,
  };

  for (final entry in hostile.entries) {
    test('cleanActivityText stays fast on ${entry.key} x$_reps', () {
      final sw = Stopwatch()..start();
      cleanActivityText(entry.value);
      expect(sw.elapsed, lessThan(_limit));
    });
    test('cleanReviewText stays fast on ${entry.key} x$_reps', () {
      final sw = Stopwatch()..start();
      cleanReviewText(entry.value);
      expect(sw.elapsed, lessThan(_limit));
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
