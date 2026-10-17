import 'package:anispark/screens/compare_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/utils/affinity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_service.dart';
import '../helpers/memory_cache_store.dart';

SharedTitle _title(int id, String name, double mine, double theirs, {String? myStatus, String? theirStatus}) =>
    SharedTitle(
      mediaId: id,
      myScore: mine,
      theirScore: theirs,
      myStatus: myStatus,
      theirStatus: theirStatus,
      title: {'english': name},
    );

final _shared = [
  _title(1, 'Alpha', 90, 40),
  _title(2, 'Bravo', 70, 70),
  _title(3, 'Charlie', 50, 60),
  _title(4, 'Delta', 0, 80),
];

void main() {
  late ApiCache cache;

  setUp(() => cache = ApiCache(MemoryCacheStore()));

  Future<void> pumpCompare(WidgetTester tester, Affinity affinity, {String? scoreFormat}) async {
    // Tall enough for every row to be built.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWith(
      CompareScreen(affinity: affinity, userName: 'faye', type: 'ANIME'),
      cache: cache,
      auth: FakeAuthService(fakeToken: 'tok', fakeUser: {
        'id': 1,
        'mediaListOptions': {'scoreFormat': ?scoreFormat},
      }),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapSort(WidgetTester tester, String key) async {
    // The chips scroll sideways when their labels are long.
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  List<String> titlesTopToBottom(WidgetTester tester) {
    final names = ['Alpha', 'Bravo', 'Charlie', 'Delta'];
    return names..sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));
  }

  testWidgets('lists the shared titles by agreement, unscored last', (tester) async {
    await pumpCompare(tester, Affinity.of(_shared));

    expect(titlesTopToBottom(tester), ['Bravo', 'Charlie', 'Alpha', 'Delta']);
  });

  testWidgets('re-sorts by disagreement and by title', (tester) async {
    await pumpCompare(tester, Affinity.of(_shared));

    await tapSort(tester, 'compare-sort-disagreement');
    expect(titlesTopToBottom(tester), ['Alpha', 'Charlie', 'Bravo', 'Delta']);

    await tapSort(tester, 'compare-sort-title');
    expect(titlesTopToBottom(tester), ['Alpha', 'Bravo', 'Charlie', 'Delta']);
  });

  testWidgets('shows both scores in the viewer\'s score format, a dash when unscored', (tester) async {
    await pumpCompare(tester, Affinity.of(_shared), scoreFormat: 'POINT_100');

    final alpha = find.ancestor(of: find.text('Alpha'), matching: find.byType(InkWell));
    expect(find.descendant(of: alpha, matching: find.text('90')), findsOneWidget);
    expect(find.descendant(of: alpha, matching: find.text('40')), findsOneWidget);
    final delta = find.ancestor(of: find.text('Delta'), matching: find.byType(InkWell));
    expect(find.descendant(of: delta, matching: find.text('–')), findsOneWidget);
    expect(find.descendant(of: delta, matching: find.text('80')), findsOneWidget);
  });

  testWidgets('summarises the means over titles both scored', (tester) async {
    // Means over Alpha, Bravo, Charlie: (90+70+50)/3 = 70 and (40+70+60)/3 ≈ 56.7.
    await pumpCompare(tester, Affinity.of(_shared), scoreFormat: 'POINT_100');

    expect(find.text('70'), findsWidgets);
    expect(find.text('57'), findsOneWidget);
  });

  testWidgets('shows the percentage when there is enough to compare', (tester) async {
    final shared = [for (var i = 1; i <= 10; i++) _title(i, 'Show $i', i * 9.0, i * 9.0)];

    await pumpCompare(tester, Affinity.of(shared));

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('shows no percentage without enough titles', (tester) async {
    await pumpCompare(tester, Affinity.of(_shared));

    expect(find.textContaining('%'), findsNothing);
  });
}
