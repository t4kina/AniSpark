import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('trf', () {
    test('fills named placeholders', () {
      expect(
        trf('test_placeholder_key {n} of {total}', 'English', {'n': 3, 'total': 12}),
        'test_placeholder_key 3 of 12',
      );
    });

    test('leaves unknown placeholders untouched', () {
      expect(trf('{a} {b}', 'English', {'a': 1}), '1 {b}');
    });
  });

  test('the System appearance follows the device theme', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'appearance': 'System'});
    final settings = SettingsProvider();

    await settings.load();

    expect(settings.themeMode, ThemeMode.system);
  });
}
