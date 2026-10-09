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
}
