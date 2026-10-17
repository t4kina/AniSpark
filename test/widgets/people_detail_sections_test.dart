import 'dart:io';

import 'package:anispark/screens/staff_screen.dart';
import 'package:anispark/screens/studio_screen.dart';
import 'package:anispark/services/api_cache.dart';
import 'package:anispark/widgets/detail/staff_section.dart';
import 'package:anispark/widgets/detail/studio_links.dart';
import 'package:anispark/widgets/people/person_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_cache_store.dart';
import '../screens/screen_harness.dart';

Map<String, dynamic> _edge(int id, String name, String role) => {
      'role': role,
      'node': {
        'id': id,
        'name': {'full': name},
        'image': {'medium': null},
      },
    };

void main() {
  // Pages opened from these widgets load from the network, which is offline.
  final offline = OfflineHttpOverrides();
  late ApiCache cache;

  setUpAll(() => HttpOverrides.global = offline);

  setUp(() {
    offline.requests = 0;
    cache = ApiCache(MemoryCacheStore());
  });

  Widget app(Widget child) =>
      screenApp(Scaffold(body: SingleChildScrollView(child: child)), cache: cache);

  group('StaffSection', () {
    testWidgets('hides itself when there is nobody to show', (tester) async {
      await tester.pumpWidget(app(const StaffSection(edges: [])));
      expect(find.byType(PersonCard), findsNothing);
      expect(find.text('STAFF'), findsNothing);
      expect(find.byType(Divider), findsNothing);

      await tester.pumpWidget(app(const StaffSection(edges: [
        {'role': 'Director'},
        {'role': 'Music', 'node': {'id': 3}},
        'junk',
      ])));
      expect(find.byType(PersonCard), findsNothing);
      expect(offline.requests, 0);
    });

    testWidgets('shows each person once with all their roles', (tester) async {
      await tester.pumpWidget(app(StaffSection(edges: [
        _edge(1, 'Shinichirou Watanabe', 'Director'),
        _edge(2, 'Yoko Kanno', 'Music'),
        _edge(1, 'Shinichirou Watanabe', 'Storyboard'),
      ])));

      expect(find.text('STAFF'), findsOneWidget);
      expect(find.byType(PersonCard), findsNWidgets(2));
      expect(find.text('Shinichirou Watanabe'), findsOneWidget);
      expect(find.text('Director, Storyboard'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
    });

    testWidgets('opens the staff page of a tapped person', (tester) async {
      await tester.pumpWidget(app(StaffSection(edges: [_edge(2, 'Yoko Kanno', 'Music')])));

      await tester.tap(find.text('Yoko Kanno'));
      await tester.pumpAndSettle();

      final screen = tester.widget<StaffScreen>(find.byType(StaffScreen));
      expect(screen.staffId, 2);
      expect(screen.name, 'Yoko Kanno');
      expect(find.text(loadErrorText), findsOneWidget, reason: 'offline, nothing cached');
    });
  });

  group('StudioLinks', () {
    const studios = [
      {'id': 14, 'name': 'Sunrise', 'isAnimationStudio': true},
      {'id': 17, 'name': 'Aniplex', 'isAnimationStudio': false},
      {'name': 'Bandai Visual', 'isAnimationStudio': false},
    ];

    testWidgets('shows every studio, tappable only when it has an id', (tester) async {
      await tester.pumpWidget(app(const StudioLinks(studios: studios)));

      expect(find.text('Sunrise'), findsOneWidget);
      expect(find.text('Aniplex'), findsOneWidget);
      expect(find.text('Bandai Visual'), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(2));
      expect(find.widgetWithText(Chip, 'Bandai Visual'), findsOneWidget);
    });

    testWidgets('chips show the name with a small chevron, not a generic icon', (tester) async {
      await tester.pumpWidget(app(const StudioLinks(studios: studios)));

      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      expect(chips.every((chip) => chip.avatar == null), isTrue);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2), reason: 'one per tappable studio');
      expect(find.byIcon(Icons.movie_filter_outlined), findsNothing);
      expect(find.byIcon(Icons.business_outlined), findsNothing);
    });

    testWidgets('filters animation studios or producers', (tester) async {
      await tester.pumpWidget(app(const StudioLinks(studios: studios, isAnimationStudio: true)));
      expect(find.text('Sunrise'), findsOneWidget);
      expect(find.text('Aniplex'), findsNothing);

      await tester.pumpWidget(app(const StudioLinks(studios: studios, isAnimationStudio: false)));
      expect(find.text('Sunrise'), findsNothing);
      expect(find.text('Aniplex'), findsOneWidget);
      expect(find.text('Bandai Visual'), findsOneWidget);
    });

    testWidgets('renders nothing without studios', (tester) async {
      await tester.pumpWidget(app(const StudioLinks(studios: [])));
      expect(find.byType(Wrap), findsNothing);

      await tester.pumpWidget(app(
        const StudioLinks(studios: studios, isAnimationStudio: true, alignment: WrapAlignment.center),
      ));
      expect(tester.widget<Wrap>(find.byType(Wrap)).alignment, WrapAlignment.center);
    });

    testWidgets('opens the studio page of a tapped studio', (tester) async {
      await tester.pumpWidget(app(const StudioLinks(studios: studios)));

      await tester.tap(find.text('Sunrise'));
      await tester.pumpAndSettle();

      final screen = tester.widget<StudioScreen>(find.byType(StudioScreen));
      expect(screen.studioId, 14);
      expect(find.text('Sunrise'), findsWidgets, reason: 'the known name is shown while loading');
      expect(find.text(loadErrorText), findsOneWidget);
    });
  });
}
