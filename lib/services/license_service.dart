import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseResult { ok, invalidFormat, invalidSignature, expired }

class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService _instance = LicenseService._();
  factory LicenseService() => _instance;

  // ⚠️ Same value as tools/keygen.dart — keep private
  static const _secret = 'anispark_lic_v1_4f9a2b7e3c8d1a6f5e0b9c4d7a2f1e8b3d5c6a9f';
  static const _prefKey = 'license_key';
  static final _epoch = DateTime.utc(2024, 1, 1);

  bool _isPremium = false;
  DateTime? _expiresAt; // null = lifetime
  String? _activeKey;

  bool get isPremium => _isPremium;
  DateTime? get expiresAt => _expiresAt;
  String? get activeKey => _activeKey;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null) {
      final result = _validate(stored);
      if (result == LicenseResult.ok) {
        _apply(stored);
      } else {
        // Key expired or tampered — remove it silently
        await prefs.remove(_prefKey);
      }
    }
  }

  /// Validate and activate a key entered by the user.
  Future<LicenseResult> activateKey(String raw) async {
    final result = _validate(raw);
    if (result == LicenseResult.ok) {
      _apply(raw);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _normalise(raw));
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
    notifyListeners();
  }

  // ─── Private ────────────────────────────────────────────────────────────

  /// Strip prefix/spaces/dashes and uppercase
  String _normalise(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');

  LicenseResult _validate(String raw) {
    final clean = _normalise(raw);
    if (clean.length != 24) return LicenseResult.invalidFormat;

    final payloadHex = clean.substring(0, 8);
    final keyHmac = clean.substring(8, 24);

    // Recompute HMAC
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final digest = hmac.convert(utf8.encode(payloadHex));
    final expected = digest.toString().substring(0, 16).toUpperCase();

    if (keyHmac != expected) return LicenseResult.invalidSignature;

    // Check expiry
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
    // Store in display format
    final groups = List.generate(6, (i) => clean.substring(i * 4, i * 4 + 4));
    _activeKey = 'ANSP-${groups.join('-')}';
  }
}
