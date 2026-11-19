import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/friend_alerts.dart';
import 'package:anispark/services/social_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_anilist.dart';

const _faye = 7;
const _jet = 8;

Map<String, dynamic> _activity(int id, int userId, int createdAt, {String type = 'ANIME_LIST', Object? progress, String status = 'watched episode'}) => {
      'id': id,
      'type': type,
      'status': status,
      'progress': progress,
      'createdAt': createdAt,
      'user': {'id': userId, 'name': 'User $userId'},
      'media': {'id': 1, 'title': {'english': 'Frieren'}},
    };

void main() {
  late List<RecordedRequest> log;
  var now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
  int seconds() => now.millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    log = [];
    now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
  });

  FriendAlertsStore store() => FriendAlertsStore(clock: () => now);

  FriendAlertsChecker checker(List<Map<String, dynamic>> answer) => FriendAlertsChecker(
        api: SocialApi(
          service: AniListService(
            client: mockAniList(log, (_) => jsonResponse({
                  'data': {
                    'Page': {'activities': answer},
                  },
                })),
          ),
        ),
      );

  group('which bell an activity rings', () {
    test('an episode or chapter, a change of status, a post; not a message', () {
      expect(friendAlertKindOf(_activity(1, _faye, 0, progress: '5')), FriendAlertKind.progress);
      expect(friendAlertKindOf(_activity(1, _faye, 0, type: 'MANGA_LIST', progress: '3 - 4')), FriendAlertKind.progress);
      expect(friendAlertKindOf(_activity(1, _faye, 0, status: 'completed')), FriendAlertKind.status);
      expect(friendAlertKindOf({'type': 'TEXT'}), FriendAlertKind.text);
      expect(friendAlertKindOf({'type': 'MESSAGE'}), isNull);
    });
  });

  group('the bells kept on the device', () {
    test('a bell is kept with what it watches and since when, and comes back after a restart', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: {FriendAlertKind.text});

      final restarted = store();
      await restarted.load();
      final watch = restarted.watchOf(_faye)!;
      expect(watch.name, 'Faye');
      expect(watch.kinds, {FriendAlertKind.text});
      expect(watch.since, seconds());
    });

    test('changing what it watches keeps when it started; nothing left turns it off', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: defaultFriendAlertKinds);
      final since = bells.watchOf(_faye)!.since;
      now = now.add(const Duration(hours: 1));

      await bells.watch(userId: _faye, name: 'Faye', kinds: {FriendAlertKind.status});
      expect(bells.watchOf(_faye)!.since, since);

      await bells.watch(userId: _faye, name: 'Faye', kinds: {});
      expect(bells.watchOf(_faye), isNull);
    });

    test('logging out forgets every bell', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: defaultFriendAlertKinds);
      await bells.setLastCheckedAt(5);

      await bells.clear();

      expect(bells.watches, isEmpty);
      expect(await bells.lastCheckedAt(), isNull);
      final restarted = store();
      await restarted.load();
      expect(restarted.watches, isEmpty);
    });

    test('something saved that is not a bell is skipped', () async {
      SharedPreferences.setMockInitialValues({
        FriendAlertsStore.prefsKey: '[{"userId": "x"}, {"userId": 7, "name": "Faye", "kinds": ["text"], "since": 1}]',
      });
      final bells = store();
      await bells.load();
      expect(bells.watches.map((watch) => watch.userId), [_faye]);
    });
  });

  group('looking for news', () {
    test('without bells it asks nothing', () async {
      final fresh = await checker([]).newActivities(store(), token: 'tok');

      expect(fresh, isEmpty);
      expect(log, isEmpty);
    });

    test('tells what each friend is watched for, newer than the bell and the last look, oldest first', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: {FriendAlertKind.progress});
      await bells.watch(userId: _jet, name: 'Jet', kinds: {FriendAlertKind.text});
      final since = seconds();
      now = now.add(const Duration(hours: 1));

      final fresh = await checker([
        _activity(5, _jet, since + 50, type: 'TEXT'),
        _activity(4, _faye, since + 40, status: 'completed'),
        _activity(3, _faye, since + 30, progress: '6'),
        _activity(2, _jet, since + 20, progress: '2'),
        _activity(1, _faye, since - 10, progress: '5'),
      ]).newActivities(bells, token: 'tok');

      expect(fresh.map((activity) => activity['id']), [3, 5]);
      expect(log.single.variables['userIds'], unorderedEquals([_faye, _jet]));
      expect(log.single.variables['since'], since);
      expect(log.single.query, contains('userId_in'));
      expect(await bells.lastCheckedAt(), seconds(), reason: 'the next look starts here');
    });

    test('the next look only asks for what came after this one', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: defaultFriendAlertKinds);
      now = now.add(const Duration(hours: 1));
      await checker([]).newActivities(bells, token: 'tok');
      final lookedAt = seconds();
      now = now.add(const Duration(hours: 1));

      await checker([]).newActivities(bells, token: 'tok');

      expect(log.last.variables['since'], lookedAt);
    });

    test('when AniList can not be asked, the next look still covers this time', () async {
      final bells = store();
      await bells.watch(userId: _faye, name: 'Faye', kinds: defaultFriendAlertKinds);
      final failing = FriendAlertsChecker(
        api: SocialApi(service: AniListService(client: mockAniList(log, (_) => http.Response('', 500)))),
      );

      await expectLater(failing.newActivities(bells, token: 'tok'), throwsA(isA<AniListRequestException>()));
      expect(await bells.lastCheckedAt(), isNull);
    });
  });
}
