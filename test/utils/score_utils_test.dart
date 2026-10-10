import 'package:anispark/utils/score_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toRawScore', () {
    test('converts a 0–10 score to the 0–100 raw scale', () {
      expect(toRawScore(7.5), 75);
      expect(toRawScore(10), 100);
      expect(toRawScore(0), 0);
    });

    test('rounds single-decimal scores without float drift', () {
      expect(toRawScore(7.3), 73);
      expect(toRawScore(8.6), 86);
    });

    test('clamps out-of-range values', () {
      expect(toRawScore(-1), 0);
      expect(toRawScore(12), 100);
    });
  });

  group('formatScore', () {
    test('shows the score in the user\'s AniList format', () {
      expect(formatScore(7.5, 'POINT_100'), '75');
      expect(formatScore(7.5, 'POINT_10_DECIMAL'), '7.5');
      expect(formatScore(7.5, 'POINT_10'), '8');
      expect(formatScore(8.0, 'POINT_5'), '4/5');
    });

    test('shows the 3-point format as faces', () {
      expect(formatScore(3.5, 'POINT_3'), '☹️');
      expect(formatScore(6.0, 'POINT_3'), '😐');
      expect(formatScore(8.5, 'POINT_3'), '🙂');
    });

    test('falls back to one decimal for an unknown or missing format', () {
      expect(formatScore(7.0, null), '7.0');
      expect(formatScore(7.25, 'SOMETHING_NEW'), '7.3');
    });
  });
}
