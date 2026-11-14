import 'package:anispark/utils/haptics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> sent;

  setUp(() {
    sent = [];
    hapticsEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'HapticFeedback.vibrate') sent.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    hapticsEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('each kind of moment has its own feel', () {
    selectionHaptic();
    lightHaptic();
    mediumHaptic();
    successHaptic();
    errorHaptic();

    expect(sent, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.successNotification',
      'HapticFeedbackType.errorNotification',
    ]);
  });

  test('nothing vibrates once haptics are switched off in Settings', () {
    hapticsEnabled = false;

    selectionHaptic();
    lightHaptic();
    mediumHaptic();
    successHaptic();
    errorHaptic();

    expect(sent, isEmpty);
  });
}
