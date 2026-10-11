import 'package:anispark/screens/calendar_screen.dart';
import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/discover_api.dart';
import 'package:anispark/utils/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';
import '../helpers/mock_anilist.dart';

String _en(String key) => tr(key, 'English');

Map<String, dynamic> _airing(int id, String title, DateTime time, {String? status}) => {
      'id': id,
      'airingAt': time.millisecondsSinceEpoch ~/ 1000,
      'episode': 3,
      'media': {
        'id': id,
        'isAdult': false,
        'title': {'english': title},
        'mediaListEntry': status == null ? null : {'status': status},
      },
    };

http.Response _page(List<Object?> schedules) => jsonResponse({
      'data': {
        'Page': {
          'pageInfo': {'hasNextPage': false},
          'airingSchedules': schedules,
        },
      },
    });

/// A session the test can switch while the screen is open.
class _SwitchableAuth extends AuthService {
  String? _token;
  Map<String, dynamic>? _user;

  void signIn(String token, int id) {
    _token = token;
    _user = {'id': id};
    notifyListeners();
  }

  void signOut() {
    _token = null;
    _user = null;
    notifyListeners();
  }

  @override
  String? get token => _token;

  @override
  Map<String, dynamic>? get user => _user;

  @override
  bool get isLoggedIn => _token != null;
}

void main() {
  late ApiCache cache;
  late List<RecordedRequest> log;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  setUp(() {
    cache = ApiCache(MemoryCacheStore());
    log = [];
  });

  DiscoverApi apiAnswering(http.Response Function(RecordedRequest) handler) =>
      DiscoverApi(service: AniListService(client: mockAniList(log, handler)));

  Future<void> pumpCalendar(WidgetTester tester, DiscoverApi api, {AuthService? auth}) async {
    await tester.pumpWidget(appWith(CalendarScreen(api: api), cache: cache, auth: auth));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  final schedules = [
    _airing(1, 'Frieren', DateTime(today.year, today.month, today.day, 12), status: 'CURRENT'),
    _airing(2, 'Dandadan', DateTime(today.year, today.month, today.day + 1, 12)),
    _airing(3, 'Kaiju No. 8', DateTime(today.year, today.month, today.day + 1, 13), status: 'COMPLETED'),
  ];

  testWidgets('logged out: shows every episode under day headers, no filter', (tester) async {
    await pumpCalendar(tester, apiAnswering((_) => _page(schedules)));

    expect(find.text(_en('cal_today')), findsOneWidget);
    expect(find.text(_en('cal_tomorrow')), findsOneWidget);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Dandadan'), findsOneWidget);
    expect(find.text('Episode 3'), findsNWidgets(3));
    expect(find.byType(SegmentedButton<bool>), findsNothing);

    final request = log.single;
    expect(request.authorization, isNull);
    expect(request.variables['withListStatus'], isFalse);
    expect(request.variables['from'], today.millisecondsSinceEpoch ~/ 1000 - 1);
    expect(await cache.read('calendar:$todayKey'), isNotNull);
  });

  testWidgets('logged in: defaults to "My list" and can switch to all', (tester) async {
    final auth = FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7});
    await pumpCalendar(tester, apiAnswering((_) => _page(schedules)), auth: auth);

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text(_en('watching')), findsOneWidget, reason: 'list badge');
    expect(find.text('Dandadan'), findsNothing);
    expect(find.text('Kaiju No. 8'), findsNothing, reason: 'completed is not CURRENT/PLANNING');
    expect(log.single.authorization, 'Bearer tok');
    expect(log.single.variables['withListStatus'], isTrue);
    expect(await cache.read(ApiCache.userKey(7, 'calendar:$todayKey')), isNotNull);
    expect(await cache.read('calendar:$todayKey'), isNull, reason: 'account data stays per user');

    await tester.tap(find.text(_en('cal_filter_all')));
    await tester.pump();

    expect(find.text('Dandadan'), findsOneWidget);
    expect(find.text('Kaiju No. 8'), findsOneWidget);
    expect(find.text(_en('completed')), findsOneWidget);
  });

  testWidgets('keeps the current day header pinned while scrolling its episodes',
      (tester) async {
    final many = [
      for (var i = 0; i < 20; i++)
        _airing(i, 'Today $i', DateTime(today.year, today.month, today.day, 0, i)),
      for (var i = 0; i < 20; i++)
        _airing(100 + i, 'Tomorrow $i', DateTime(today.year, today.month, today.day + 1, 0, i)),
    ];
    await pumpCalendar(tester, apiAnswering((_) => _page(many)));
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('Today 0'), findsNothing, reason: 'scrolled away');
    expect(tester.getTopLeft(find.text(_en('cal_today'))).dy, lessThan(top + 20),
        reason: 'pinned at the top');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
    await tester.pump();

    expect(find.text(_en('cal_today')), findsNothing, reason: 'pushed off with its day');
    expect(tester.getTopLeft(find.text(_en('cal_tomorrow'))).dy, lessThan(top + 20));
  });

  testWidgets('shows an empty state for "My list" with a way to see all', (tester) async {
    final auth = FakeAuthService(fakeToken: 'tok', fakeUser: {'id': 7});
    await pumpCalendar(tester, apiAnswering((_) => _page([schedules[1]])), auth: auth);

    expect(find.text(_en('cal_empty_my_list')), findsOneWidget);

    await tester.tap(find.text(_en('cal_show_all')));
    await tester.pump();

    expect(find.text('Dandadan'), findsOneWidget);
  });

  testWidgets('shows an error with retry when loading fails and nothing is cached',
      (tester) async {
    await pumpCalendar(tester, apiAnswering((_) => jsonResponse({'errors': []}, status: 500)));

    expect(find.text(_en('load_error')), findsOneWidget);

    await tester.tap(find.text(_en('retry')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(log, hasLength(2));
    expect(find.text(_en('load_error')), findsOneWidget);
  });

  testWidgets('shows the cached calendar when the refresh fails', (tester) async {
    await cache.write('calendar:$todayKey', schedules);

    await pumpCalendar(tester, apiAnswering((_) => jsonResponse({'errors': []}, status: 500)));

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text(_en('load_error')), findsNothing);
  });

  testWidgets('reloads with the user list when the user logs in while open', (tester) async {
    final auth = _SwitchableAuth();
    await pumpCalendar(tester, apiAnswering((_) => _page(schedules)), auth: auth);

    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('Dandadan'), findsOneWidget);
    expect(log, hasLength(1));

    auth.signIn('tok', 7);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(log, hasLength(2));
    expect(log.last.authorization, 'Bearer tok');
    expect(log.last.variables['withListStatus'], isTrue);
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Dandadan'), findsNothing, reason: '"My list" is the default once logged in');
  });

  testWidgets('drops the user list when the user logs out while open', (tester) async {
    final auth = _SwitchableAuth()..signIn('tok', 7);
    await pumpCalendar(tester, apiAnswering((_) => _page(schedules)), auth: auth);
    expect(find.text('Dandadan'), findsNothing);

    auth.signOut();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(log, hasLength(2));
    expect(log.last.authorization, isNull);
    expect(find.text('Dandadan'), findsOneWidget);
  });
}
