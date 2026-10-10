import 'package:anispark/services/secure_store.dart';
import 'package:flutter/services.dart';

/// In-memory [SecureStore] whose failures can be switched on per operation.
class FakeSecureStore implements SecureStore {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  /// Number of upcoming reads that fail before reads work again, like a
  /// keystore that is briefly unavailable.
  int failingReadsLeft = 0;

  /// Accepts writes without storing them, like a keystore that silently
  /// loses data.
  bool dropWrites = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw PlatformException(code: 'read_failed');
    if (failingReadsLeft > 0) {
      failingReadsLeft--;
      throw PlatformException(code: 'temporarily_unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw PlatformException(code: 'write_failed');
    if (!dropWrites) values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw PlatformException(code: 'delete_failed');
    values.remove(key);
  }
}
