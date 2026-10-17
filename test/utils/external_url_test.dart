import 'package:anispark/utils/external_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeExternalUri', () {
    test('accepts http and https links', () {
      expect(safeExternalUri('https://anilist.co/anime/1'), Uri.parse('https://anilist.co/anime/1'));
      expect(safeExternalUri('  http://example.com/path?q=1  '), Uri.parse('http://example.com/path?q=1'));
    });

    test('rejects other schemes', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'tel:123',
        'anispark://callback?code=x',
      ]) {
        expect(safeExternalUri(url), isNull, reason: url);
      }
    });

    test('rejects links without a host and unparsable text', () {
      expect(safeExternalUri('https:///nohost'), isNull);
      expect(safeExternalUri('not a url'), isNull);
      expect(safeExternalUri(''), isNull);
    });
  });
}
