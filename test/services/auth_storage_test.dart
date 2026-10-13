import 'dart:convert';
import 'dart:io';

import 'package:anispark/services/auth_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../helpers/fake_secure_store.dart';

const _user = {'id': 7, 'name': 'viewer'};

void main() {
  late Directory dir;
  late FakeSecureStore secure;
  late HiveAesCipher cipher;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anispark_auth_storage');
    Hive.init(dir.path);
    secure = FakeSecureStore();
    cipher = HiveAesCipher(Hive.generateSecureKey());
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedLegacyBox(Map<String, Object?> values) async {
    final box = await Hive.openBox(AuthStorage.legacyBoxName);
    await box.putAll(values);
    await box.close();
  }

  Future<AuthStorage> reopen({HiveAesCipher? withCipher}) async {
    await Hive.close();
    return AuthStorage.open(secure: secure, cipher: withCipher);
  }

  group('migration from the plaintext box', () {
    test('moves the token to the keystore and deletes the old box', () async {
      await seedLegacyBox({'token': 'legacy-token', 'user': jsonEncode(_user)});

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), 'legacy-token');
      expect(secure.values[AuthStorage.tokenKey], 'legacy-token');
      expect(await Hive.boxExists(AuthStorage.legacyBoxName), isFalse);
      expect(storage.readMap('user'), _user);
    });

    test('stores the cached profile encrypted at rest', () async {
      await seedLegacyBox({'token': 'legacy-token', 'user': jsonEncode(_user)});
      await AuthStorage.open(secure: secure, cipher: cipher);
      await Hive.close();

      final raw = await Hive.openBox(AuthStorage.boxName);

      expect(raw.get('user'), isNull, reason: 'unreadable without the key');
    });

    test('keeps the old box and its token when the keystore write fails', () async {
      await seedLegacyBox({'token': 'legacy-token'});
      secure.failWrites = true;

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), 'legacy-token');
      expect(await Hive.boxExists(AuthStorage.legacyBoxName), isTrue);

      secure.failWrites = false;
      final retried = await reopen(withCipher: cipher);
      expect(await retried.readToken(), 'legacy-token');
      expect(await Hive.boxExists(AuthStorage.legacyBoxName), isFalse);
    });

    test('keeps the old box when the keystore silently loses the write', () async {
      await seedLegacyBox({'token': 'legacy-token'});
      secure.dropWrites = true;

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), 'legacy-token');
      expect(await Hive.boxExists(AuthStorage.legacyBoxName), isTrue);
    });

    test('a logout recorded in the old box wipes a stale keystore token', () async {
      secure.values[AuthStorage.tokenKey] = 'stale-token';
      await seedLegacyBox({'logged_out': true});

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), isNull);
      expect(secure.values, isNot(contains(AuthStorage.tokenKey)));
    });

    test('an empty old box leaves the keystore token of this install alone', () async {
      final first = await AuthStorage.open(secure: secure, cipher: cipher);
      await first.writeToken('current-token');
      await Hive.close();
      await seedLegacyBox({});

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), 'current-token');
    });
  });

  group('with the keystore available', () {
    test('saves new tokens only in the keystore', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      await storage.writeToken('new-token');

      expect(secure.values[AuthStorage.tokenKey], 'new-token');
      expect(await Hive.boxExists(AuthStorage.legacyBoxName), isFalse);
      expect(await (await reopen(withCipher: cipher)).readToken(), 'new-token');
    });

    test('falls back to the old box when the keystore write fails, then migrates it', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      secure.failWrites = true;

      await storage.writeToken('new-token');
      expect(await storage.readToken(), 'new-token');

      secure.failWrites = false;
      final next = await reopen(withCipher: cipher);
      expect(await next.readToken(), 'new-token');
      expect(secure.values[AuthStorage.tokenKey], 'new-token');
    });

    test('clear removes the token and the cached profile', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      await storage.writeToken('token');
      await storage.writeMap('user', _user);

      await storage.clear();

      expect(await storage.readToken(), isNull);
      expect(storage.readMap('user'), isNull);
      expect(secure.values, isEmpty);
    });

    test('a logout while the keystore fails still ends logged out next launch', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      await storage.writeToken('token');
      secure.failDeletes = true;

      await storage.clear();
      expect(await storage.readToken(), isNull);

      secure.failDeletes = false;
      final next = await reopen(withCipher: cipher);
      expect(await next.readToken(), isNull);
      expect(secure.values, isNot(contains(AuthStorage.tokenKey)));
    });

    test('a failing keystore read reports no token without deleting it', () async {
      final first = await AuthStorage.open(secure: secure, cipher: cipher);
      await first.writeToken('token');
      final storage = await reopen(withCipher: cipher);
      secure.failReads = true;

      expect(await storage.readToken(), isNull);
      expect(secure.values[AuthStorage.tokenKey], 'token');
    });
  });

  group('stale sessions', () {
    Future<void> markLogoutPending() async {
      final box = await Hive.openBox(AuthStorage.boxName, encryptionCipher: cipher);
      await box.put(AuthStorage.logoutPendingKey, true);
      await Hive.close();
    }

    test('the first launch of an install ignores a token left by a previous install', () async {
      secure.values[AuthStorage.tokenKey] = 'token-from-old-install';

      final storage = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await storage.readToken(), isNull);
      expect(secure.values, isNot(contains(AuthStorage.tokenKey)));
    });

    test('a logout interrupted before reaching the keystore is completed next launch', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      await storage.writeToken('token');
      await Hive.close();
      await markLogoutPending();

      final next = await AuthStorage.open(secure: secure, cipher: cipher);

      expect(await next.readToken(), isNull);
      expect(secure.values, isNot(contains(AuthStorage.tokenKey)));
    });

    test('a pending logout keeps the session closed while the keystore fails', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      await storage.writeToken('token');
      await Hive.close();
      await markLogoutPending();
      secure.failDeletes = true;

      final next = await AuthStorage.open(secure: secure, cipher: cipher);
      expect(await next.readToken(), isNull);

      secure.failDeletes = false;
      final later = await reopen(withCipher: cipher);
      expect(await later.readToken(), isNull);
      expect(secure.values, isNot(contains(AuthStorage.tokenKey)));
    });

    test('logging in again replaces a pending logout', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: cipher);
      await storage.writeToken('old-token');
      await Hive.close();
      await markLogoutPending();
      secure.failDeletes = true;

      final next = await AuthStorage.open(secure: secure, cipher: cipher);
      await next.writeToken('new-token');
      expect(await next.readToken(), 'new-token');

      secure.failDeletes = false;
      final later = await reopen(withCipher: cipher);
      expect(await later.readToken(), 'new-token');
    });
  });

  group('without the keystore (no cipher)', () {
    test('keeps using the plaintext box exactly as before', () async {
      await seedLegacyBox({'token': 'legacy-token', 'user': jsonEncode(_user)});

      final storage = await AuthStorage.open(secure: secure, cipher: null);

      expect(await storage.readToken(), 'legacy-token');
      expect(storage.readMap('user'), _user);
      expect(secure.values, isEmpty);
    });

    test('clear empties the plaintext box and records the logout', () async {
      final storage = await AuthStorage.open(secure: secure, cipher: null);
      await storage.writeToken('token');
      await storage.writeMap('user', _user);

      await storage.clear();

      expect(await storage.readToken(), isNull);
      expect(storage.readMap('user'), isNull);
      final box = Hive.box(AuthStorage.legacyBoxName);
      expect(box.get('logged_out'), isTrue);
    });
  });

  test('corrupted cached JSON reads as null', () async {
    await seedLegacyBox({'user': 'not json', 'profileExtras': '[1,2]'});

    final storage = await AuthStorage.open(secure: secure, cipher: null);

    expect(storage.readMap('user'), isNull);
    expect(storage.readMap('profileExtras'), isNull);
  });
}
