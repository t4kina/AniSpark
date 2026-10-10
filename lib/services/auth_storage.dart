import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive/hive.dart';

import 'secure_store.dart';

/// Persists the AniList session: the OAuth token in the platform keystore
/// and the cached profile in an encrypted Hive box.
///
/// The old plaintext `auth` box is migrated without ever losing a session:
/// its token is only removed once it has been written to the keystore and
/// read back, and a logout that couldn't reach the keystore is remembered so
/// the session can't come back. Without a usable keystore (no cipher) the
/// plaintext box keeps working exactly as before.
class AuthStorage {
  AuthStorage._(this._secure, {required Box profileBox, Box? tokenBox, required bool encrypted})
      : _profileBox = profileBox,
        _tokenBox = tokenBox,
        _encrypted = encrypted;

  static const legacyBoxName = 'auth';
  static const boxName = 'auth_v2';
  static const tokenKey = 'anilist_token';
  static const _legacyTokenKey = 'token';
  // Set in the plaintext box when a logout couldn't remove the keystore token,
  // so the next launch wipes it instead of restoring the session.
  static const _loggedOutKey = 'logged_out';
  static const _cachedKeys = ['user', 'profileExtras'];

  final SecureStore _secure;
  final Box _profileBox;
  final bool _encrypted;
  // The plaintext box while it holds the session: no keystore, or a keystore
  // that failed this launch. Null when the token lives in the keystore.
  Box? _tokenBox;

  static Future<AuthStorage> open({
    required SecureStore secure,
    required HiveCipher? cipher,
  }) async {
    if (cipher == null) {
      final legacy = await Hive.openBox(legacyBoxName);
      return AuthStorage._(secure, profileBox: legacy, tokenBox: legacy, encrypted: false);
    }
    final box = await Hive.openBox(boxName, encryptionCipher: cipher);
    final storage = AuthStorage._(secure, profileBox: box, encrypted: true);
    if (await Hive.boxExists(legacyBoxName)) await storage._migrateLegacyBox();
    return storage;
  }

  Future<String?> readToken() async {
    final tokenBox = _tokenBox;
    if (tokenBox != null) {
      final token = tokenBox.get(_legacyTokenKey);
      return token is String ? token : null;
    }
    try {
      return await _secure.read(tokenKey);
    } on Exception catch (e) {
      // Reported as logged out for this launch; nothing is deleted.
      debugPrint('[AuthStorage] Reading the token failed: $e');
      return null;
    }
  }

  Future<void> writeToken(String token) async {
    if (_encrypted && await _writeVerified(token)) {
      await _dropLegacyBox();
      return;
    }
    // No usable keystore right now: keep the session in the plaintext box,
    // as before this change; the next launch moves it to the keystore.
    final legacy = _tokenBox ??= await Hive.openBox(legacyBoxName);
    await legacy.put(_legacyTokenKey, token);
    await legacy.delete(_loggedOutKey);
  }

  /// Reads a JSON map cached under [key]; corrupted data reads as null.
  Map<String, dynamic>? readMap(String key) {
    final raw = _profileBox.get(key);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) =>
      _profileBox.put(key, jsonEncode(value));

  /// Ends the session: removes the token and the cached profile.
  Future<void> clear() async {
    if (!_encrypted) {
      await _profileBox.deleteAll([_legacyTokenKey, ..._cachedKeys]);
      await _profileBox.put(_loggedOutKey, true);
      return;
    }
    await _profileBox.deleteAll(_cachedKeys);
    if (await _deleteVerified()) {
      await _dropLegacyBox();
      return;
    }
    final legacy = _tokenBox ??= await Hive.openBox(legacyBoxName);
    await legacy.delete(_legacyTokenKey);
    await legacy.put(_loggedOutKey, true);
  }

  Future<void> _migrateLegacyBox() async {
    final legacy = await Hive.openBox(legacyBoxName);
    final token = legacy.get(_legacyTokenKey);
    final loggedOut = legacy.get(_loggedOutKey) == true;

    final bool migrated;
    if (token is String) {
      migrated = await _writeVerified(token);
      if (migrated) {
        for (final key in _cachedKeys) {
          final value = legacy.get(key);
          if (value is String && _profileBox.get(key) == null) {
            await _profileBox.put(key, value);
          }
        }
      }
    } else if (loggedOut) {
      migrated = await _deleteVerified();
    } else {
      migrated = true;
    }

    if (!migrated) {
      // Keep using the plaintext session this launch and retry next time.
      _tokenBox = legacy;
      return;
    }
    await legacy.close();
    await Hive.deleteBoxFromDisk(legacyBoxName);
  }

  Future<bool> _writeVerified(String token) async {
    try {
      await _secure.write(tokenKey, token);
      return await _secure.read(tokenKey) == token;
    } on Exception catch (e) {
      debugPrint('[AuthStorage] Saving the token to the keystore failed: $e');
      return false;
    }
  }

  Future<bool> _deleteVerified() async {
    try {
      await _secure.delete(tokenKey);
      return await _secure.read(tokenKey) == null;
    } on Exception catch (e) {
      debugPrint('[AuthStorage] Removing the token from the keystore failed: $e');
      return false;
    }
  }

  Future<void> _dropLegacyBox() async {
    final legacy = _tokenBox;
    if (legacy == null) return;
    _tokenBox = null;
    await legacy.close();
    await Hive.deleteBoxFromDisk(legacyBoxName);
  }
}
