import 'dart:async';

import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/session_expiry.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/mock_anilist.dart';

/// A session whose logout can be held open and counted.
class _CountingAuth extends FakeAuthService {
  _CountingAuth(String? token) : super(fakeToken: token);

  int logouts = 0;
  Completer<void>? holdLogout;

  @override
  Future<void> logout() async {
    logouts++;
    await holdLogout?.future;
  }
}

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  AniListService serviceAnswering(http.Response Function(RecordedRequest request) handler) =>
      AniListService(client: mockAniList(log, handler), retryDelay: (_) async {});

  /// Runs [action] and returns the rejected token each notification carried.
  Future<List<String?>> rejectedTokensDuring(Future<void> Function() action) async {
    final seen = <String?>[];
    void listener() => seen.add(authExpiredNotifier.rejectedToken);
    authExpiredNotifier.addListener(listener);
    addTearDown(() => authExpiredNotifier.removeListener(listener));
    await action();
    return seen;
  }

  group('AniListService reports 401s with the token that was rejected', () {
    test('once per rejected request, carrying its token', () async {
      final service = serviceAnswering((_) => jsonResponse({'errors': []}, status: 401));

      final seen = await rejectedTokensDuring(() async {
        await expectLater(
          service.request('query { Viewer { id } }', const {}, token: 'old'),
          throwsA(isA<AniListRequestException>()),
        );
      });

      expect(seen, ['old']);
      expect(authExpiredNotifier.value, 1);
    });

    test('also from the older query methods, without double counting', () async {
      final service = serviceAnswering((_) => jsonResponse({'errors': []}, status: 401));

      final seen = await rejectedTokensDuring(() async {
        final saved = await service.saveListEntry(mediaId: 1, progress: 2, token: 'tok');
        expect(saved, isNull);
      });

      expect(seen, ['tok']);
    });

    test('forgets the token as soon as listeners have been told', () async {
      final service = serviceAnswering((_) => jsonResponse({'errors': []}, status: 401));

      await expectLater(
        service.request('query { Viewer { id } }', const {}, token: 'old'),
        throwsA(isA<AniListRequestException>()),
      );

      expect(authExpiredNotifier.rejectedToken, isNull);
    });

    test('ignores a 401 for a request sent without a token', () async {
      final service = serviceAnswering((_) => jsonResponse({'errors': []}, status: 401));

      final seen = await rejectedTokensDuring(() async {
        await expectLater(
          service.request('query { Page { media { id } } }', const {}),
          throwsA(isA<AniListRequestException>()),
        );
      });

      expect(seen, isEmpty);
      expect(authExpiredNotifier.value, 0);
    });

    test('reports a 401 that follows a rate-limit retry once', () async {
      var calls = 0;
      final service = serviceAnswering((_) => ++calls == 1
          ? jsonResponse({'errors': []}, status: 429)
          : jsonResponse({'errors': []}, status: 401));

      final seen = await rejectedTokensDuring(() async {
        await expectLater(
          service.request('query { Viewer { id } }', const {}, token: 'tok'),
          throwsA(isA<AniListRequestException>()),
        );
      });

      expect(seen, ['tok']);
    });
  });

  group('watchSessionExpiry', () {
    test('logs out and tells the user when the current token is rejected', () async {
      final auth = _CountingAuth('current');
      var told = 0;
      final stop = watchSessionExpiry(auth, onExpired: () => told++);
      addTearDown(stop);

      authExpiredNotifier.report('current');
      await pumpEventQueue();

      expect(auth.logouts, 1);
      expect(told, 1);
    });

    test('ignores a late 401 for the token of a previous session', () async {
      final auth = _CountingAuth('new-account');
      var told = 0;
      final stop = watchSessionExpiry(auth, onExpired: () => told++);
      addTearDown(stop);

      authExpiredNotifier.report('old-account');
      await pumpEventQueue();

      expect(auth.logouts, 0);
      expect(told, 0);
    });

    test('does nothing when nobody is logged in', () async {
      final auth = _CountingAuth(null);
      var told = 0;
      final stop = watchSessionExpiry(auth, onExpired: () => told++);
      addTearDown(stop);

      authExpiredNotifier.report('anything');
      await pumpEventQueue();

      expect(auth.logouts, 0);
      expect(told, 0);
    });

    test('logs out once when several requests are rejected together', () async {
      final auth = _CountingAuth('current')..holdLogout = Completer<void>();
      var told = 0;
      final stop = watchSessionExpiry(auth, onExpired: () => told++);
      addTearDown(stop);

      authExpiredNotifier.report('current');
      authExpiredNotifier.report('current');
      auth.holdLogout!.complete();
      await pumpEventQueue();

      expect(auth.logouts, 1);
      expect(told, 1);
    });

    test('stops listening once the returned function is called', () async {
      final auth = _CountingAuth('current');
      final stop = watchSessionExpiry(auth, onExpired: () {});

      stop();
      authExpiredNotifier.report('current');
      await pumpEventQueue();

      expect(auth.logouts, 0);
    });
  });
}
