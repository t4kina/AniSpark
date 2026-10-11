import 'dart:async';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart' show rateLimitActiveNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/mock_anilist.dart';

void main() {
  const ok = {'data': {'Viewer': {'id': 1}}};

  tearDown(() => rateLimitActiveNotifier.value = false);

  Future<(AniListService, List<Duration>)> serviceWith(
    List<http.Response Function()> replies,
  ) async {
    final waits = <Duration>[];
    var i = 0;
    final client = MockClient((_) async => replies[i++]());
    final service = AniListService(
      client: client,
      retryDelay: (d) async => waits.add(d),
    );
    return (service, waits);
  }

  Future<void> run(AniListService s) => s.request('query { a }', const {});

  test('retries once after the Retry-After seconds', () async {
    final (service, waits) = await serviceWith([
      () => jsonResponse({}, status: 429, headers: {'retry-after': '7'}),
      () => jsonResponse(ok),
    ]);
    await run(service);
    expect(waits, [const Duration(seconds: 7)]);
    expect(rateLimitActiveNotifier.value, isFalse);
  });

  test('clamps an absurd Retry-After to two minutes', () async {
    final (service, waits) = await serviceWith([
      () => jsonResponse({}, status: 429, headers: {'retry-after': '99999999'}),
      () => jsonResponse(ok),
    ]);
    await run(service);
    expect(waits, [const Duration(seconds: 120)]);
  });

  test('waits at least one second, also for zero or negative values', () async {
    for (final value in ['0', '-5']) {
      final (service, waits) = await serviceWith([
        () => jsonResponse({}, status: 429, headers: {'retry-after': value}),
        () => jsonResponse(ok),
      ]);
      await run(service);
      expect(waits, [const Duration(seconds: 1)], reason: value);
    }
  });

  test('uses 60 seconds when Retry-After is missing', () async {
    final (service, waits) = await serviceWith([
      () => jsonResponse({}, status: 429),
      () => jsonResponse(ok),
    ]);
    await run(service);
    expect(waits, [const Duration(seconds: 60)]);
  });

  test('clears the rate-limit flag when the retried request throws', () async {
    final (service, _) = await serviceWith([
      () => jsonResponse({}, status: 429, headers: {'retry-after': '1'}),
      () => throw TimeoutException('boom'),
    ]);
    await expectLater(run(service), throwsA(isA<TimeoutException>()));
    expect(rateLimitActiveNotifier.value, isFalse);
  });
}
