import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive/hive.dart';

import 'secure_store.dart';

/// Persists the AniList session: the OAuth token in the platform keystore
/// and the cached profile in an encrypted Hive box.
///
/// Two guarantees drive the design:
/// - A valid session is never lost: the old plaintext `auth` box is migrated
///   by writing its token to the keystore and reading it back before the
///   old copy is removed; if the keystore fails, that launch keeps using the
///   plaintext session and the migration retries next time.
/// - A logged-out session never comes back: a logout is recorded before the
///   keystore token is deleted (so an interrupted logout is finished on the
///   next launch), and the first launch of an install wipes any token left in
///   the iOS Keychain by a previous install.
///
/// Without a usable keystore (no cipher) the plaintext box keeps working
/// exactly as before.
class AuthStorage {
  AuthStorage._(this._secure, {required Box profileBox, Box? tokenBox, required bool encrypted})
      : _profileBox = profileBox,
        _tokenBox = tokenBox,
        _encrypted = encrypted;

  static const legacyBoxName = 'auth';
  static const boxName = 'auth_v2';
  static const tokenKey = 'anilist_token';
  static const logoutPendingKey = 'logout_pending';
  static const _legacyTokenKey = 'token';
  // Set in the plaintext box by a logout without a keystore, so a migration
  // knows the session ended.
  static const _loggedOutKey = 'logged_out';
  static const _installedKey = 'installed';
  static const _stateEchoKey = 'oauth_state_echoed';
  static const _cachedKeys = ['user', 'profileExtras'];

  final SecureStore _secure;
  final Box _profileBox;
  final bool _encrypted;
  // The plaintext box while it holds the session: no keystore, or a keystore
  // that failed this launch. Null when the token lives in the keystore.
  Box? _tokenBox;
  // Set when a token that must not be used (left by a previous install or by
  // an unfinished logout) couldn't be deleted yet; retried next launch.
  bool _ignoreKeystoreToken = false;

  static Future<AuthStorage> open({
    required SecureStore secure,
    required HiveCipher? cipher,
  }) async {
    if (cipher == null) {
      final legacy = await _openOrRecreate(legacyBoxName);
      return AuthStorage._(secure, profileBox: legacy, tokenBox: legacy, encrypted: false);
    }
    final box = await _openOrRecreate(boxName, cipher: cipher);
    final storage = AuthStorage._(secure, profileBox: box, encrypted: true);
    await storage._settleKeystore();
    return storage;
  }

  Future<String?> readToken() async {
    final tokenBox = _tokenBox;
    if (tokenBox != null) {
      final token = tokenBox.get(_legacyTokenKey);
      return token is String ? token : null;
    }
    if (_ignoreKeystoreToken) return null;
    try {
      return await _secure.read(tokenKey);
    } on Exception catch (e) {
      // Reported as logged out for this launch; nothing is deleted.
      debugPrint('[AuthStorage] Reading the token failed: $e');
      return null;
    }
  }

  /// Saves the session's token. Never throws: if nothing can be persisted the
  /// session still works until the app is closed.
  Future<void> writeToken(String token) async {
    if (_encrypted && await _writeVerified(token)) {
      _ignoreKeystoreToken = false;
      await _tryHive('clearing logout markers', () async {
        await _profileBox.delete(logoutPendingKey);
        await _profileBox.put(_installedKey, true);
      });
      await _tryHive('removing the plaintext session', _dropLegacyBox);
      return;
    }
    // No usable keystore right now: keep the session in the plaintext box,
    // as before this change; the next launch moves it to the keystore.
    await _tryHive('saving the session in the plaintext box', () async {
      final legacy = _tokenBox ??= await _openOrRecreate(legacyBoxName);
      await legacy.put(_legacyTokenKey, token);
      await legacy.delete(_loggedOutKey);
    });
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

  /// Whether AniList has been seen echoing the OAuth `state`; once it has,
  /// callbacks without one are rejected.
  bool get stateEchoSeen => _profileBox.get(_stateEchoKey) == true;

  Future<void> rememberStateEcho() =>
      _tryHive('remembering the state echo', () => _profileBox.put(_stateEchoKey, true));

  /// Ends the session: removes the token and the cached profile.
  Future<void> clear() async {
    if (!_encrypted) {
      await _tryHive('clearing the plaintext session', () async {
        await _profileBox.deleteAll([_legacyTokenKey, ..._cachedKeys]);
        await _profileBox.put(_loggedOutKey, true);
      });
      return;
    }
    // Written first so a logout interrupted at any point below is finished
    // on the next launch instead of restoring the session.
    await _tryHive('recording the logout', () => _profileBox.put(logoutPendingKey, true));
    await _tryHive('clearing the cached profile', () => _profileBox.deleteAll(_cachedKeys));
    if (await _deleteVerified()) {
      await _tryHive('finishing the logout', () async {
        await _profileBox.delete(logoutPendingKey);
        await _dropLegacyBox();
      });
      return;
    }
    _ignoreKeystoreToken = true;
    final legacy = _tokenBox;
    if (legacy != null) {
      await _tryHive('clearing the plaintext session', () => legacy.delete(_legacyTokenKey));
    }
  }

  /// Brings the keystore in line with this install before the token is read.
  Future<void> _settleKeystore() async {
    final hasLegacyBox = await Hive.boxExists(legacyBoxName);
    if (_profileBox.get(_installedKey) != true && !hasLegacyBox) {
      // First launch of this install. iOS keeps Keychain items after an
      // uninstall; a token from a previous install must not log anyone in.
      if (await _deleteVerified()) {
        await _profileBox.put(_installedKey, true);
      } else {
        _ignoreKeystoreToken = true;
      }
    }
    if (_profileBox.get(logoutPendingKey) == true) {
      if (await _deleteVerified()) {
        await _profileBox.delete(logoutPendingKey);
      } else {
        _ignoreKeystoreToken = true;
      }
    }
    if (hasLegacyBox) {
      await _migrateLegacyBox();
      await _profileBox.put(_installedKey, true);
    }
  }

  Future<void> _migrateLegacyBox() async {
    final legacy = await _openOrRecreate(legacyBoxName);
    final token = legacy.get(_legacyTokenKey);
    final loggedOut = legacy.get(_loggedOutKey) == true;

    final bool migrated;
    if (token is String) {
      migrated = await _writeVerified(token);
      if (migrated) {
        // The plaintext session is newer than any pending logout marker.
        _ignoreKeystoreToken = false;
        await _profileBox.delete(logoutPendingKey);
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

  /// Opens a box, recreating it if its file can't be read, so a corrupted
  /// file never stops the app from starting. Whatever it held was unreadable.
  static Future<Box> _openOrRecreate(String name, {HiveCipher? cipher}) async {
    try {
      return await Hive.openBox(name, encryptionCipher: cipher);
    } on Object catch (e) {
      // Hive reports unreadable boxes as HiveError, which is an Error.
      debugPrint('[AuthStorage] Box $name could not be opened, recreating it: $e');
      await Hive.deleteBoxFromDisk(name);
      return Hive.openBox(name, encryptionCipher: cipher);
    }
  }

  /// Runs a best-effort Hive write; storage errors (Hive throws Errors) are
  /// logged instead of breaking login or logout.
  static Future<void> _tryHive(String what, Future<void> Function() write) async {
    try {
      await write();
    } on Object catch (e) {
      debugPrint('[AuthStorage] Failed $what: $e');
    }
  }
}
