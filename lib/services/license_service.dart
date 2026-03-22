import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseResult { ok, invalidFormat, invalidSignature, expired, notLoggedIn }

class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService _instance = LicenseService._();
  factory LicenseService() => _instance;

  // ⚠️ Same value as tools/keygen.dart — keep private
  static const _secret = 'anispark_lic_v1_4f9a2b7e3c8d1a6f5e0b9c4d7a2f1e8b3d5c6a9f';
  static const _prefKey = 'license_key';
  static const _prefUserKey = 'license_user_id';
  static final _epoch = DateTime.utc(2024, 1, 1);

  bool _isPremium = false;
  DateTime? _expiresAt; // null = lifetime
  String? _activeKey;

  bool get isPremium => _isPremium;
  DateTime? get expiresAt => _expiresAt;
  String? get activeKey => _activeKey;

  /// Call at startup after AuthService.init(). Pass the logged-in userId (or null).
  Future<void> init(int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    final storedUserId = prefs.getInt(_prefUserKey);

    if (stored == null || userId == null) return;

    // Key belongs to a different account — clear silently
    if (storedUserId != userId) {
      await prefs.remove(_prefKey);
      await prefs.remove(_prefUserKey);
      return;
    }

    final result = _validate(stored, userId);
    if (result == LicenseResult.ok) {
      _apply(stored);
    } else {
      await prefs.remove(_prefKey);
      await prefs.remove(_prefUserKey);
    }
  }

  /// Validate and activate a key entered by the user.
  Future<LicenseResult> activateKey(String raw, int? userId) async {
    if (userId == null) return LicenseResult.notLoggedIn;
    final result = _validate(raw, userId);
    if (result == LicenseResult.ok) {
      _apply(raw);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _normalise(raw));
      await prefs.setInt(_prefUserKey, userId);
      notifyListeners();
    }
    return result;
  }

  Future<void> deactivate() async {
    _isPremium = false;
    _expiresAt = null;
    _activeKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_prefUserKey);
    notifyListeners();
  }

  // ─── Private ────────────────────────────────────────────────────────────

  String _normalise(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');

  LicenseResult _validate(String raw, int userId) {
    final clean = _normalise(raw);
    if (clean.length != 24) return LicenseResult.invalidFormat;

    final payloadHex = clean.substring(0, 8);
    final keyHmac = clean.substring(8, 24);

    // HMAC over payload + userId so the key is bound to this specific account
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final digest = hmac.convert(utf8.encode(payloadHex + userId.toString()));
    final expected = digest.toString().substring(0, 16).toUpperCase();

    if (keyHmac != expected) return LicenseResult.invalidSignature;

    final expiryDays = int.parse(payloadHex, radix: 16);
    if (expiryDays != 0) {
      final expiresAt = _epoch.add(Duration(days: expiryDays));
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        return LicenseResult.expired;
      }
    }

    return LicenseResult.ok;
  }

  void _apply(String raw) {
    final clean = _normalise(raw);
    final expiryDays = int.parse(clean.substring(0, 8), radix: 16);
    _isPremium = true;
    _expiresAt = expiryDays == 0 ? null : _epoch.add(Duration(days: expiryDays));
    final groups = List.generate(6, (i) => clean.substring(i * 4, i * 4 + 4));
    _activeKey = 'ANSP-${groups.join('-')}';
  }
}
