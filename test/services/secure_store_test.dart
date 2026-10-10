import 'package:anispark/services/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_secure_store.dart';

void main() {
  late FakeSecureStore store;

  setUp(() => store = FakeSecureStore());

  group('loadStorageCipher', () {
    test('creates a key on first use and reuses it afterwards', () async {
      final first = await loadStorageCipher(store);
      final second = await loadStorageCipher(store);

      expect(first, isNotNull);
      expect(second?.calculateKeyCrc(), first?.calculateKeyCrc());
      expect(store.values, hasLength(1));
    });

    test('returns null when the keystore cannot be read', () async {
      store.failReads = true;

      expect(await loadStorageCipher(store), isNull);
    });

    test('returns null when the new key does not persist', () async {
      store.dropWrites = true;

      expect(await loadStorageCipher(store), isNull);
    });

    test('replaces a corrupted key', () async {
      store.values[storageKeyName] = 'not base64!';

      final cipher = await loadStorageCipher(store);

      expect(cipher, isNotNull);
      expect(store.values[storageKeyName], isNot('not base64!'));
    });
  });
}
