import 'dart:convert';
import 'dart:io';

import 'package:anispark/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

const _cachedViewer = {'id': 7, 'name': 'cached'};
const _freshViewer = {'id': 7, 'name': 'fresh'};

void main() {
  late Directory dir;
  late List<RecordedRequest> log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('anispark_auth_test');
    Hive.init(dir.path);
    log = [];
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedBox(Map<String, Object?> values) async {
    final box = await Hive.openBox('auth');
    await box.putAll(values);
    await box.close();
  }

  http.Client viewerClient() => mockAniList(
        log,
        (_) => jsonResponse({
          'data': {'Viewer': _freshViewer},
        }),
      );

  test('restores the cached viewer at startup when a token exists', () async {
    await seedBox({'token': 'test-token', 'user': jsonEncode(_cachedViewer)});

    await http.runWithClient(() async {
      final auth = AuthService();
      await auth.init();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user?['name'], 'cached');

      await pumpEventQueue();
      expect(auth.user?['name'], 'fresh');
    }, viewerClient);

    final box = await Hive.openBox('auth');
    expect(jsonDecode(box.get('user') as String)['name'], 'fresh');
  });

  test('ignores a cached viewer when there is no token', () async {
    await seedBox({'user': jsonEncode(_cachedViewer)});

    await http.runWithClient(() async {
      final auth = AuthService();
      await auth.init();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    }, viewerClient);
    expect(log, isEmpty);
  });

  test('survives a corrupted cached viewer', () async {
    await seedBox({'token': 'test-token', 'user': 'not json'});

    await http.runWithClient(() async {
      final auth = AuthService();
      await auth.init();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.user, isNull);
      await pumpEventQueue();
      expect(auth.user?['name'], 'fresh');
    }, viewerClient);
  });

  test('logout removes the token and the cached viewer', () async {
    await seedBox({'token': 'test-token', 'user': jsonEncode(_cachedViewer)});

    await http.runWithClient(() async {
      final auth = AuthService();
      await auth.init();
      await pumpEventQueue();

      await auth.logout();

      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    }, viewerClient);

    final box = await Hive.openBox('auth');
    expect(box.get('token'), isNull);
    expect(box.get('user'), isNull);
  });

  test('a viewer response arriving after logout is discarded', () async {
    await seedBox({'token': 'test-token'});

    await http.runWithClient(() async {
      final auth = AuthService();
      await auth.init();
      await auth.logout();
      await pumpEventQueue();

      expect(auth.user, isNull);
    }, viewerClient);

    final box = await Hive.openBox('auth');
    expect(box.get('user'), isNull);
  });
}
