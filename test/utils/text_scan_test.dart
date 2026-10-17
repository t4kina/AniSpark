import 'package:anispark/utils/text_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('replaceSpoilers', () {
    test('replaces each span, across lines', () {
      expect(replaceSpoilers('a ~!x\ny!~ b ~!z!~ c', '#'), 'a # b # c');
    });

    test('leaves an unclosed opener and text without spoilers alone', () {
      expect(replaceSpoilers('a ~!x b', '#'), 'a ~!x b');
      expect(replaceSpoilers('plain', '#'), 'plain');
    });

    test('handles empty spans and a closer right after the opener', () {
      expect(replaceSpoilers('~!!~', '#'), '#');
      expect(replaceSpoilers('~!a!~~!b!~', '#'), '##');
    });
  });

  group('LruMemo', () {
    test('computes once per key and evicts the least recently used', () {
      final memo = LruMemo(capacity: 2);
      var calls = 0;
      String compute(String key) => memo.of(key, () => '${calls++}$key');

      expect(compute('a'), '0a');
      expect(compute('b'), '1b');
      expect(compute('a'), '0a', reason: 'hit, and a is now the most recent');
      compute('c'); // evicts b
      expect(compute('a'), '0a');
      expect(compute('b'), '3b', reason: 'b was evicted and recomputed');
    });

    test('does not store keys over the length limit', () {
      final memo = LruMemo(maxKeyLength: 3);
      var calls = 0;
      memo.of('long', () => '${calls++}');
      memo.of('long', () => '${calls++}');
      expect(calls, 2);
    });
  });
}
