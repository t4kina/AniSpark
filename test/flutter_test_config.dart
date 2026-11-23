import 'dart:async';

import 'package:anispark/widgets/profile/profile_tint.dart';

/// Runs before every test file under `test/`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // No test downloads a picture to colour a profile: the real look leaves a
  // five second timer behind, and there is no network in tests anyway.
  ProfileTint.resolver = (_) async => null;
  await testMain();
}
