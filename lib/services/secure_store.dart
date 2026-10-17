import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Small key/value store backed by the platform keystore (iOS Keychain,
/// Android Keystore). Holds the OAuth token and the local storage key.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecureStore implements SecureStore {
  const DeviceSecureStore();

  static const _storage = FlutterSecureStorage(
    // Readable once the device has been unlocked after boot, and never
    // synced to other devices or included in backups.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    // If the keystore can no longer decrypt its data (e.g. its keys were
    // invalidated), wipe it so the user can simply log in again; otherwise
    // every read would keep failing and no session could be saved.
    aOptions: AndroidOptions(resetOnError: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

const storageKeyName = 'local_storage_key';

/// Returns the AES cipher for the app's Hive boxes, creating its key in the
/// keystore on first use. Returns null when the keystore can't be used, so
/// callers fall back to the previous unencrypted storage instead of failing.
/// A failure is retried once, since a briefly unavailable keystore would
/// otherwise make an existing session look logged out for that launch.
Future<HiveAesCipher?> loadStorageCipher(
  SecureStore store, {
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  final cipher = await _loadStorageCipherOnce(store);
  if (cipher != null) return cipher;
  await Future<void>.delayed(retryDelay);
  return _loadStorageCipherOnce(store);
}

Future<HiveAesCipher?> _loadStorageCipherOnce(SecureStore store) async {
  try {
    final saved = await store.read(storageKeyName);
    final savedKey = saved == null ? null : _decodeKey(saved);
    if (savedKey != null) return HiveAesCipher(savedKey);

    final key = Hive.generateSecureKey();
    final encoded = base64Encode(key);
    await store.write(storageKeyName, encoded);
    // Only use a key that really persisted, or the next launch couldn't read
    // anything written with it.
    if (await store.read(storageKeyName) != encoded) return null;
    return HiveAesCipher(key);
  } on Exception catch (e) {
    debugPrint('[SecureStore] Local storage key unavailable: $e');
    return null;
  }
}

List<int>? _decodeKey(String encoded) {
  try {
    final bytes = base64Decode(encoded);
    return bytes.length == 32 ? bytes : null;
  } on FormatException {
    return null;
  }
}
